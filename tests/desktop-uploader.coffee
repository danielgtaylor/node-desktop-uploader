assert = require 'assert'
chokidar = require 'chokidar'
fs = require 'fs'
mockFs = require 'mock-fs'
sinon = require 'sinon'

{DesktopUploader} = require '../lib/main'
{EventEmitter} = require 'events'

delay = (ms, func) -> setTimeout func, ms

# We are going to stub out the Chokidar FSWatcher
# Presumably chokidar has its own tests, we just want to verify
# that the desktop uploader behaves as expected given certain
# chokidar events on a fake filesystem.
watcher = null
class FakeFSWatcher extends EventEmitter
  add: sinon.spy()
  close: sinon.spy()
  ignored: -> false

chokidar.FSWatcher = FakeFSWatcher
chokidar.watch = (path, opts) ->
  watcher = new FakeFSWatcher()
  watcher.add path
  watcher.ignored = opts.ignored
  return watcher

# Create a mock filesystem
mockFs
  '/.desktop-uploader-test.json': '{"paths": ["/tmp2"], "cache": {"/tmp2/foo": {"mtime": "2014-01-01T00:00:00.000Z"}}}'
  '/tmp1':
    file1: 'data1'
    file2: 'data2'
  '/tmp2': {}
  '/tmp3':
    file3: 'data3'
  '0': '' # <-- hack to get tests working, don't ask me why...

# Let's set up some tests!
describe 'Desktop Uploader', ->
  entries = []
  uploader = new DesktopUploader
    name: 'desktop-uploader-test'
    saveInterval: 1
    modifyInterval: 1
    configPath: '/'
    paths: ['/tmp2']
    throttle: 100

  # Uncomment for extra debug output, which may help for failing tests
  # uploader.on 'log', (message) ->
  #   console.log message

  uploader.on 'upload', (entry, done) ->
    entries.push entry
    done()

  after ->
    mockFs.restore()

  it 'Should add a watch directory', (done) ->
    uploader.watch '/tmp1'
    uploader.resume()
    uploader.watch '/tmp3'
    assert.ok watcher.add.called
    assert.ok uploader.get('/tmp1')
    assert.ok uploader.get('/tmp3')

    watcher.emit 'add', '/tmp1/file1'
    watcher.emit 'add', '/tmp1/file2'
    watcher.emit 'add', '/tmp3/file3'

    delay 10, ->
      assert.equal entries.length, 3
      done()

  it 'Should upload a new file', (done) ->
    entries.length = 0
    fs.writeFileSync '/tmp1/new1', 'data', 'utf-8'
    watcher.emit 'add', '/tmp1/new1'

    delay 10, ->
      assert.equal entries.length, 1
      assert.equal entries[0].path, '/tmp1/new1'
      done()

  it 'Should upload a changed file', (done) ->
    entries.length = 0
    watcher.emit 'change', '/tmp1/new1'

    delay 10, ->
      assert.equal entries.length, 1
      assert.equal entries[0].path, '/tmp1/new1'
      done()

  it 'Should not upload changes after unwatch', (done) ->
    entries.length = 0
    uploader.unwatch '/tmp2'

    fs.writeFileSync '/tmp2/new2'
    watcher.emit 'add', '/tmp2/new2'

    delay 10, ->
      assert.equal entries.length, 0
      done()

  it 'Should ignore unchanged file', ->
    assert.ok watcher.ignored '/tmp1/file1'

  it 'Should handle a removed file', (done) ->
    entries.length = 0
    watcher.emit 'remove', '/tmp1/new2'

    delay 10, ->
      assert.equal entries.length, 0
      done()

  it 'Should pause and resume with watched paths', ->
    uploader.pause()
    assert.ok watcher.close.called

    uploader.resume()

    assert.ok uploader.get '/tmp1'
    assert.ok watcher.add.called

  it 'Should change concurrency', ->
    uploader.concurrency 5
    uploader.concurrency 2

    # TODO: Actually assert the number of items processed in parallel

  it 'Should throttle requests', (done) ->
    entries.length = 0
    uploader.throttle 5

    watcher.emit 'change', '/tmp1/file1'

    delay 10, ->
      uploader.throttle off

      # TODO: Actually assert speed of reads

      assert.equal entries.length, 1
      done()

  it 'Should get all paths', ->
    assert.ok uploader.get()

  it 'Should set and get custom config values', ->
    uploader.config('mysetting', 'foo')

    assert.equal uploader.config('mysetting'), 'foo'

  it 'Should return undefined for missing custom config', ->
    assert.equal uploader.config('missing'), undefined

  it 'Should not blow up when missing event handlers', (done) ->
    entries.length = 0
    uploader.removeAllListeners 'upload'

    watcher.emit 'change', '/tmp1/file1'

    delay 10, ->
      done()

  it 'Should remove all paths', ->
    uploader.unwatch()

  it 'Should fail to resume with no paths configured', ->
    uploader.pause()
    try
      uploader.resume()
    catch err
      false

    assert.ok err
