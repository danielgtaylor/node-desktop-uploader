_ = require 'lodash'
async = require 'async'
chokidar = require 'chokidar'
fs = require 'fs'

pathJoin = require('path').join

{EventEmitter} = require 'events'
{ThrottleGroup} = require 'stream-throttle'

delay = (ms, func) -> setTimeout func, ms

class DesktopUploader extends EventEmitter
  ### Private properties ###
  self = null
  name = 'desktop-uploader'
  configPath = null
  customConfig = {}
  cache = {}
  paths = {}
  watcher = null
  queue = null
  throttleGroup = null

  saveConfig = null

  ### Public methods ###
  constructor: (options) ->
    self = this
    concurrency = options.concurrency or 2

    if options.name then name = options.name
    if options.configPath then configPath = options.configPath
    if options.throttle then self.throttle options.throttle
    
    self.modifyInterval = options.modifyInterval or 5000

    loadConfig()

    saveConfig = _.debounce _saveConfig, options.saveInterval or 10000

    # Load paths from config
    for path, config of paths
      self.watch path, config

    # Load paths from passed options
    for path in options.paths or []
      if not paths[path] then self.watch path

    queue = async.queue upload, concurrency

  # Add a new directory to watch. Existing files will be queued for upload.
  watch: (path, config={}) ->
    log "Watching #{path}"
    @emit 'watch', path, config
    paths[fs.realpathSync path] = config
    if watcher then watcher.add fs.realpathSync(path)

  # Stop watching a directory.
  unwatch: (path) ->
    # Chokidar has no unwatch, so we remove it from our watched paths
    # list and check for this case in the `update` method below.
    if path
      log "Unwatching #{path}"
      @emit 'unwatch', [path]
      delete paths[fs.realpathSync path]
    else
      # Clear all paths, TODO: update cache?
      log "Unwatching all paths"
      @emit 'unwatch', Object.keys(paths)
      paths = {}

  # Get path custom configuration
  get: (path) ->
    if path
      paths[fs.realpathSync path]
    else
      paths

  # Get or set custom config values
  config: (name, value) ->
    if value isnt undefined
      customConfig[name] = value
      saveConfig()
      undefined
    else
      customConfig[name]

  # Start or resume uploading
  resume: ->
    # If not already running
    if not watcher
      self.emit 'resume'

      pathnames = Object.keys(paths)

      log "Creating watcher with #{pathnames[0]}..."
      watcher = new chokidar.FSWatcher
        usePolling: false
        persistent: true
        ignored: checkIgnore

      watcher.on 'add', update.bind(this, 'add')
      watcher.on 'change', update.bind(this, 'change')
      watcher.on 'remove', (filename) ->
        # Keep the cache lean if we can...
        delete cache[filename]
        saveConfig()

      for path in pathnames
        log "Adding #{path}"
        watcher.add path

  # Stop uploading
  pause: ->
    self.emit 'pause'

    watcher.close()
    watcher = null

  # Manually save config
  save: (immediate) ->
    if immediate
      _saveConfig()
    else
      saveConfig()

  # Set concurrency limit
  concurrency: (value) ->
    queue.concurrency = value

  # Set bandwidth throttling in bytes per second
  throttle: (bytes) ->
    if bytes
      log "Throttling to #{(bytes / 1024).toFixed(1)} kbytes/sec"
      throttleGroup = new ThrottleGroup rate: bytes
    else
      throttleGroup = null

  ### Private methods ###
  log = (message) ->
    self.emit 'log', message

  # saveConfig becomes a debounced version of _saveConfig
  _saveConfig = ->
    path = ".#{name}.json"
    if configPath
      path = pathJoin configPath, path

    log "Writing cache to #{path}..."

    fs.writeFileSync path, JSON.stringify {cache, paths, customConfig}

  loadConfig = ->
    path = ".#{name}.json"
    if configPath
      path = pathJoin configPath, path

    if fs.existsSync path
      config = JSON.parse(fs.readFileSync path, 'utf-8')
      for key, value of config.cache or {}
        value.mtime = new Date(value.mtime)
      
      cache = config.cache or {}
      paths = config.paths or {}
      customConfig = config.customConfig or {}

  # This gets called by chokidar to see if an updated file should be ignored
  checkIgnore = (filename) ->
    unless cache[filename] then return false

    stat = fs.statSync filename
    # Modified file?
    if stat.mtime > cache[filename].mtime
      return false

    # TODO: check hash or something?

    log "Ignoring #{filename}"
    true

  # We know a file was added or modified, and it was not ignored. Watch it
  # until the size is no longer increasing, and then add it to the queue.
  update = (event, filename, stat) ->
    size = 0
    newSize = 1
    updateSize = (done) ->
      fs.stat filename, (err, newStat) ->
        if err then return done err
        size = newSize
        newSize = newStat.size

        delay self.modifyInterval, done()

    checkSize = ->
      log "Checking size of #{filename}"
      size isnt newSize

    log "Waiting to finish writes: #{event} - #{filename}"
    async.doWhilst updateSize, checkSize, (err) ->
      if err
        log err
        return self.emit 'error', err, filename
      root = null
      for path of paths
        index = filename.indexOf path
        if index isnt -1 and filename[index + path.length] in ['/', '\\']
          root = path
          break

      # Ignore the file? No longer watched?
      if root is null
        log "Skipping #{filename} which is no longer watched"
        return

      self.emit 'queue', filename, root
      queue.push {path: filename, root}, (err) ->
        if err then self.emit 'error', err, filename

  # Process an item from the queue. This does some setup and then emits the
  # upload event for processing.
  upload = (entry, done) ->
    # It's possible the queue is very full of items when an unwatch
    # is called, so let's check here and not process those items
    unless paths[entry.root]
      log "Skipping #{entry.path} which is no longer watched"
      return done()

    entry.config = paths[entry.root]
    entry.stream = fs.createReadStream entry.path

    if throttleGroup
      entry.stream = entry.stream.pipe(throttleGroup.throttle())

    log "Going to upload #{entry.path}, #{entry.config}"

    fs.stat entry.path, (err, stat) ->
      if err
        log err
        return done err

      entry.size = stat.size

      # Here we set the length of the stream, since a lot of other libraries
      # may expect a simple fs.createReadStream which has a length.
      if throttleGroup
        entry.stream.length = stat.size

      cache[entry.path] = {mtime: stat.mtime}
      saveConfig()

      if not self.emit 'upload', entry, done
        # No event handler registered, finish the entry
        done()


module.exports = {DesktopUploader}
