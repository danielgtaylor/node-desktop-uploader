(function() {
  var DesktopUploader, EventEmitter, ThrottleGroup, async, chokidar, delay, fs, pathJoin, _,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
    __indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

  _ = require('lodash');

  async = require('async');

  chokidar = require('chokidar');

  fs = require('fs');

  pathJoin = require('path').join;

  EventEmitter = require('events').EventEmitter;

  ThrottleGroup = require('stream-throttle').ThrottleGroup;

  delay = function(ms, func) {
    return setTimeout(func, ms);
  };

  DesktopUploader = (function(_super) {

    /* Private properties */
    var cache, checkIgnore, configPath, customConfig, extensions, loadConfig, log, name, paths, queue, saveConfig, self, throttleGroup, tryCount, update, upload, watcher, _saveConfig;

    __extends(DesktopUploader, _super);

    self = null;

    name = 'desktop-uploader';

    configPath = null;

    customConfig = {};

    cache = {};

    paths = {};

    watcher = null;

    queue = null;

    throttleGroup = null;

    extensions = null;

    tryCount = 1;

    saveConfig = null;


    /* Public methods */

    function DesktopUploader(options) {
      var concurrency, config, path, _i, _len, _ref;
      self = this;
      concurrency = options.concurrency || 2;
      if (options.name) {
        name = options.name;
      }
      if (options.configPath) {
        configPath = options.configPath;
      }
      if (options.throttle) {
        self.throttle(options.throttle);
      }
      if (options.extensions) {
        extensions = options.extensions;
      }
      if (options.retries) {
        tryCount = options.retries + 1;
      }
      self.modifyInterval = options.modifyInterval || 5000;
      loadConfig();
      saveConfig = _.debounce(_saveConfig, options.saveInterval || 10000);
      for (path in paths) {
        config = paths[path];
        self.watch(path, config);
      }
      _ref = options.paths || [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        path = _ref[_i];
        if (!paths[path]) {
          self.watch(path);
        }
      }
      queue = async.queue(upload, concurrency);
    }

    DesktopUploader.prototype.watch = function(path, config) {
      if (config == null) {
        config = {};
      }
      log("Watching " + path);
      this.emit('watch', path, config);
      paths[fs.realpathSync(path)] = config;
      if (watcher) {
        return watcher.add(fs.realpathSync(path));
      }
    };

    DesktopUploader.prototype.unwatch = function(path) {
      if (path) {
        log("Unwatching " + path);
        this.emit('unwatch', [path]);
        return delete paths[fs.realpathSync(path)];
      } else {
        log("Unwatching all paths");
        this.emit('unwatch', Object.keys(paths));
        return paths = {};
      }
    };

    DesktopUploader.prototype.get = function(path) {
      if (path) {
        return paths[fs.realpathSync(path)];
      } else {
        return paths;
      }
    };

    DesktopUploader.prototype.config = function(name, value) {
      if (value !== void 0) {
        customConfig[name] = value;
        saveConfig();
        return void 0;
      } else {
        return customConfig[name];
      }
    };

    DesktopUploader.prototype.resume = function() {
      var path, pathnames, _i, _len, _results;
      if (!watcher) {
        self.emit('resume');
        pathnames = Object.keys(paths);
        log("Creating watcher with " + pathnames[0] + "...");
        watcher = new chokidar.FSWatcher({
          usePolling: false,
          persistent: true,
          ignored: checkIgnore
        });
        watcher.on('add', update.bind(this, 'add'));
        watcher.on('change', update.bind(this, 'change'));
        watcher.on('remove', function(filename) {
          delete cache[filename];
          return saveConfig();
        });
        _results = [];
        for (_i = 0, _len = pathnames.length; _i < _len; _i++) {
          path = pathnames[_i];
          log("Adding " + path);
          _results.push(watcher.add(path));
        }
        return _results;
      }
    };

    DesktopUploader.prototype.pause = function() {
      self.emit('pause');
      watcher.close();
      return watcher = null;
    };

    DesktopUploader.prototype.save = function(immediate) {
      if (immediate) {
        return _saveConfig();
      } else {
        return saveConfig();
      }
    };

    DesktopUploader.prototype.concurrency = function(value) {
      return queue.concurrency = value;
    };

    DesktopUploader.prototype.throttle = function(bytes) {
      if (bytes) {
        log("Throttling to " + ((bytes / 1024).toFixed(1)) + " kbytes/sec");
        return throttleGroup = new ThrottleGroup({
          rate: bytes
        });
      } else {
        return throttleGroup = null;
      }
    };

    DesktopUploader.prototype.retry = function(times) {
      return tryCount = times + 1;
    };


    /* Private methods */

    log = function(message) {
      return self.emit('log', message);
    };

    _saveConfig = function() {
      var path;
      path = "." + name + ".json";
      if (configPath) {
        path = pathJoin(configPath, path);
      }
      log("Writing cache to " + path + "...");
      return fs.writeFileSync(path, JSON.stringify({
        cache: cache,
        paths: paths,
        customConfig: customConfig
      }));
    };

    loadConfig = function() {
      var config, key, path, value, _ref;
      path = "." + name + ".json";
      if (configPath) {
        path = pathJoin(configPath, path);
      }
      if (fs.existsSync(path)) {
        config = JSON.parse(fs.readFileSync(path, 'utf-8'));
        _ref = config.cache || {};
        for (key in _ref) {
          value = _ref[key];
          value.mtime = new Date(value.mtime);
        }
        cache = config.cache || {};
        paths = config.paths || {};
        return customConfig = config.customConfig || {};
      }
    };

    checkIgnore = function(filename) {
      var stat, _ref;
      if (extensions && fs.statSync(filename).isFile()) {
        if (_ref = filename.split('.').pop().toLowerCase(), __indexOf.call(extensions, _ref) < 0) {
          log("Ignoring " + filename);
          return true;
        }
      }
      if (!cache[filename]) {
        return false;
      }
      stat = fs.statSync(filename);
      if (stat.mtime > cache[filename].mtime) {
        return false;
      }
      log("Ignoring " + filename);
      return true;
    };

    update = function(event, filename, stat) {
      var checkSize, newSize, size, updateSize;
      size = 0;
      newSize = 1;
      updateSize = function(done) {
        return fs.stat(filename, function(err, newStat) {
          if (err) {
            return done(err);
          }
          size = newSize;
          newSize = newStat.size;
          return delay(self.modifyInterval, done());
        });
      };
      checkSize = function() {
        log("Checking size of " + filename);
        return size !== newSize;
      };
      log("Waiting to finish writes: " + event + " - " + filename);
      return async.doWhilst(updateSize, checkSize, function(err) {
        var index, path, root, _ref;
        if (err) {
          log(err);
          return self.emit('error', err, filename);
        }
        root = null;
        for (path in paths) {
          index = filename.indexOf(path);
          if (index !== -1 && ((_ref = filename[index + path.length]) === '/' || _ref === '\\')) {
            root = path;
            break;
          }
        }
        if (root === null) {
          log("Skipping " + filename + " which is no longer watched");
          return;
        }
        self.emit('queue', filename, root);
        return queue.push({
          path: filename,
          root: root
        }, function(err) {
          if (err) {
            return self.emit('error', err, filename);
          }
        });
      });
    };

    upload = function(entry, done) {
      if (!paths[entry.root]) {
        log("Skipping " + entry.path + " which is no longer watched");
        return done();
      }
      entry.config = paths[entry.root];
      entry.stream = fs.createReadStream(entry.path);
      if (throttleGroup) {
        entry.stream = entry.stream.pipe(throttleGroup.throttle());
      }
      log("Going to upload " + entry.path + ", " + entry.config);
      return fs.stat(entry.path, function(err, stat) {
        var tryUpload;
        if (err) {
          log(err);
          return done(err);
        }
        entry.size = stat.size;
        if (throttleGroup) {
          entry.stream.length = stat.size;
        }
        cache[entry.path] = {
          mtime: stat.mtime
        };
        saveConfig();
        tryUpload = function(entry, tryUploadDone) {
          if (!self.emit('upload', entry, tryUploadDone)) {
            return tryUploadDone();
          }
        };
        return async.retry(tryCount, tryUpload.bind(this, entry), done);
      });
    };

    return DesktopUploader;

  })(EventEmitter);

  module.exports = {
    DesktopUploader: DesktopUploader
  };

}).call(this);
