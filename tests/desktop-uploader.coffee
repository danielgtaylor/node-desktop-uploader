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
  constructor: (opts) ->
    watcher = this
    @ignored = opts.ignored
  add: sinon.spy()
  close: sinon.spy()
  ignored: -> false

chokidar.FSWatcher = FakeFSWatcher

# Create a mock filesystem
mockFs
  '/.desktop-uploader-test.json': '{"paths": ["/tmp2"], "cache": {"/tmp2/foo": {"mtime": "2014-01-01T00:00:00.000Z"}}}'
  '/tmp1':
    'file1.txt': 'data1'
    'file2.txt': 'data2'
  '/tmp2': {}
  '/tmp3':
    'file3.txt': 'data3'
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
    extensions: ['txt']
    retries: 1

  # Uncomment for extra debug output, which may help for failing tests
  # uploader.on 'log', (message) ->
  #   console.log message

  uploader.on 'upload', (entry, done) ->
    entries.push entry
    done()

  after ->
    mockFs.restore()

  it 'Should instantiate multiple times and not require arguments', ->
    new DesktopUploader()

    # No assertions here, but all the other tests will fail if
    # anything is screwy after creating a second uploader instance.

  it 'Should add a watch directory', (done) ->
    uploader.watch '/tmp1'
    uploader.resume()
    uploader.watch '/tmp3'
    assert.ok watcher.add.called
    assert.ok uploader.get('/tmp1')
    assert.ok uploader.get('/tmp3')

    watcher.emit 'add', '/tmp1/file1.txt'
    watcher.emit 'add', '/tmp1/file2.txt'
    watcher.emit 'add', '/tmp3/file3.txt'

    delay 10, ->
      assert.equal entries.length, 3
      done()

  it 'Should upload a new file', (done) ->
    entries.length = 0
    fs.writeFileSync '/tmp1/new1.txt', 'data', 'utf-8'
    watcher.emit 'add', '/tmp1/new1.txt'

    queueFired = false
    uploader.once 'queue', (filename, root) ->
      assert.equal filename, '/tmp1/new1.txt'
      queueFired = true

    processFired = false
    uploader.once 'processed', (entry, success) ->
      assert.equal entry.path, '/tmp1/new1.txt'
      assert.ok success
      processFired = true

    drainFired = false
    uploader.once 'drain', ->
      drainFired = true

    delay 10, ->
      assert.equal entries.length, 1
      assert.equal entries[0].path, '/tmp1/new1.txt'
      assert.ok queueFired
      assert.ok processFired
      assert.ok drainFired
      done()

  it 'Should upload a changed file', (done) ->
    entries.length = 0
    watcher.emit 'change', '/tmp1/new1.txt'

    delay 10, ->
      assert.equal entries.length, 1
      assert.equal entries[0].path, '/tmp1/new1.txt'
      done()

  it 'Should handle platform case-sensitivity', (done) ->
    entries.length = 0
    platform = process.platform
    process.platform = 'linux'

    # MockFS is case-sensitive, so create this to simulate case-insensitivity
    # at the filesystem layer.
    fs.mkdirSync '/TmP1'
    fs.writeFileSync '/TmP1/New1.txt', 'data', 'utf-8'

    watcher.emit 'change', '/TmP1/New1.txt'

    delay 10, ->
      process.platform = platform
      assert.equal entries.length, 0
      done()

  it 'Should handle platform case-insensitivity', (done) ->
    entries.length = 0
    platform = process.platform
    process.platform = 'win32'

    watcher.emit 'change', '/TmP1/New1.txt'

    delay 10, ->
      process.platform = platform
      assert.equal entries.length, 1
      assert.equal entries[0].path, '/TmP1/New1.txt'
      done()

  it 'Should not queue or upload changes after unwatch', (done) ->
    entries.length = 0
    uploader.unwatch '/tmp2'

    fs.writeFileSync '/tmp2/new2.txt'
    watcher.emit 'add', '/tmp2/new2.txt'

    ignoreFired = false
    uploader.once 'ignore', (filename) ->
      assert.equal filename, '/tmp2/new2.txt'
      ignoreFired = true

    delay 10, ->
      assert.equal uploader.tasks.length, 0
      assert.equal entries.length, 0
      assert.ok ignoreFired
      done()

  it 'Should not upload queued changes after unwatch', (done) ->
    entries.length = 0
    uploader.pause()

    uploader.watch '/tmp2'
    fs.writeFileSync '/tmp2/new2.txt'
    watcher.emit 'change', '/tmp2/new2.txt'

    delay 10, ->
      assert.equal uploader.tasks.length, 1

      uploader.unwatch '/tmp2'

      ignoreFired = false
      uploader.once 'ignore', (filename) ->
        assert.equal filename, '/tmp2/new2.txt'
        ignoreFired = true

      uploader.resume()

      delay 10, ->
        assert.equal uploader.tasks.length, 0
        assert.equal entries.length, 0
        assert.ok ignoreFired
        done()

  it 'Should ignore unchanged file', ->
    assert.ok watcher.ignored '/tmp1/file1.txt'

  it 'Should ignore extension capitalization', ->
    fs.writeFileSync '/tmp1/capitalized.TxT', 'data', 'utf-8'
    assert.equal watcher.ignored('/tmp1/capitalized.TxT'), false

  it 'Should ignore unwanted extensions', ->
    fs.writeFileSync '/tmp1/ignored.pdf', 'data', 'utf-8'
    assert.ok watcher.ignored '/tmp1/ignored.pdf'

  it 'Should ignore missing extension', ->
    fs.writeFileSync '/tmp1/missing', 'data', 'utf-8'
    assert.ok watcher.ignored '/tmp1/missing'

  it 'Should not ignore directories', ->
    assert.equal watcher.ignored('/tmp1'), false

  it 'Should handle a removed file', (done) ->
    entries.length = 0
    watcher.emit 'remove', '/tmp1/new2.txt'

    delay 10, ->
      assert.equal entries.length, 0
      done()

  it 'Should list task queue', ->
    assert.ok uploader.tasks instanceof Array
    assert.equal uploader.tasks.length, 0

  it 'Should pause and resume watcher with watched paths', ->
    pauseWatcherCalled = false
    uploader.once 'pause', (type) ->
      if type is 'watcher'
        pauseWatcherCalled = true

    uploader.pauseWatcher()

    assert.ok pauseWatcherCalled
    assert.ok watcher.close.called

    uploader.resume()

    assert.ok uploader.get '/tmp1'
    assert.ok watcher.add.called

  it 'Should pause processing tasks', (done) ->
    entries.length = 0

    pauseQueueFired = false
    uploader.once 'pause', (type) ->
      if type is 'queue'
        pauseQueueFired = true

    uploader.pause()
    watcher.emit 'change', '/tmp1/new1.txt'

    delay 10, ->
      assert.ok pauseQueueFired
      assert.equal entries.length, 0
      assert.equal uploader.tasks.length, 1
      uploader.resume()
      done()

  it 'Should change concurrency', ->
    uploader.concurrency = 5
    assert.equal uploader.concurrency, 5

    uploader.concurrency = 2
    assert.equal uploader.concurrency, 2

    # TODO: Actually assert the number of items processed in parallel

  it 'Should throttle requests', (done) ->
    entries.length = 0
    uploader.throttle = 5

    watcher.emit 'change', '/tmp1/file1.txt'

    delay 10, ->
      assert.equal uploader.throttle, 5
      uploader.throttle = off

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

    watcher.emit 'change', '/tmp1/file1.txt'

    delay 10, ->
      done()

  it 'Should retry failures', (done) ->
    uploadSpy = sinon.spy (entry, done) ->
      done new Error 'Something went wrong!'

    uploader.retries = 2
    uploader.removeAllListeners 'upload'
    uploader.on 'upload', uploadSpy
    uploader.on 'error', -> false

    watcher.emit 'change', '/tmp1/file1.txt'

    delay 10, ->
      assert.equal uploader.retries, 2
      assert.equal uploadSpy.callCount, 3
      uploader.removeAllListeners 'error'
      done()

  it 'Should remove all paths', ->
    uploader.unwatch()

  it 'Should resume with no paths configured', ->
    uploader.pause()
    uploader.resume()

  it 'Should save config immediately', ->
    mtime = fs.statSync('/.desktop-uploader-test.json').mtime
    uploader.save true
    diff = fs.statSync('/.desktop-uploader-test.json').mtime - mtime
    assert.ok diff > 0
