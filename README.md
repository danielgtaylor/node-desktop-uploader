# Desktop Uploader

[![Dependency Status](http://img.shields.io/david/danielgtaylor/node-desktop-uploader.svg?style=flat)](https://david-dm.org/danielgtaylor/node-desktop-uploader) [![Build Status](http://img.shields.io/travis/danielgtaylor/node-desktop-uploader.svg?style=flat)](https://travis-ci.org/danielgtaylor/node-desktop-uploader) [![Coverage Status](http://img.shields.io/coveralls/danielgtaylor/node-desktop-uploader.svg?style=flat)](https://coveralls.io/r/danielgtaylor/node-desktop-uploader) [![NPM version](http://img.shields.io/npm/v/desktop-uploader.svg?style=flat)](https://www.npmjs.org/package/desktop-uploader) [![License](http://img.shields.io/npm/l/desktop-uploader.svg?style=flat)](http://dgt.mit-license.org/)


The `desktop-uploader` module lets you easily write a desktop uploader for a remote service such as Dropbox, S3, Google Storage, or your own company using Node.js. You define directories to watch and a function that uploads a file entry, and `desktop-uploader` handles the rest!

#### Features

* Recursively watch folders and files for changes
  * Uses native events (fsevents, inotify, ReadDirectoryChangesW)
* Whitelist file extensions you care about
* Persistent custom configuration values
* Persistent per-folder custom configuration
* Determine when a file is no longer being modified
* Upload files using custom business logic
* Concurrently upload many files
* Automatically handle retries of failures
* Keep a cache of info on already-uploaded files
* Throttle aggregate uploads to a set bandwidth (e.g. 100Kbytes/sec)
* Works with [atom-shell](https://github.com/atom/atom-shell) and [node-webkit](https://github.com/rogerwang/node-webkit) for a cross-platform user interface

#### Improvement Ideas

* Custom cache and ignore strategies (e.g. file hash instead of last modified time)
* Upload bandwidth auto-detection for throttling
* Allow manually adding items to the queue

## Installation
Install like any other Node.js package, with NPM:

```bash
$ npm install --save desktop-uploader
```

## Basic Example

Create a new desktop uploader instance. It takes an optional options object where you can set initial paths to watch and a few options, like the number of concurrent uploads and how many times to retry failures. **Note**: the uploader is created in a paused state.

```javascript
var DesktopUploader = require('desktop-uploader').DesktopUploader;
var request = require('request');

var uploader = new DesktopUploader({
  name: 'my-cool-app',
  paths: ['/home/daniel/Pictures'],
  concurrency: 3,
  retries: 2
});
```

Now we need to tell the uploader how to actually upload a file when that file is no longer being modified, since this is specific to your service and API. Here we are assuming that we are going to do an HTTP POST to `api.myservice.com` to the `items` collection using an OAuth bearer token for authentication. We'll be using the [request](https://github.com/mikeal/request) library to make this easier.

```javascript
uploader.on('upload', function (entry, done) {
  var url = 'https://api.myservice.com/items';
  var headers = {
    authorization: 'bearer abc123'
  };

  // Create the HTTP POST request
  var req = request.post {url: url, headers: headers}, function (err, res) {
    if (err) return done(err);
    console.log(entry.path + ' uploaded!');
    done();
  });

  // Pipe the file into the request
  entry.stream.pipe(req)
});
```

Notice that you are piping `entry.stream` into the request rather than reading it all into memory first. All that's left is to start the uploader:

```javascript
uploader.resume();
```

At this point, the uploader is running. It is recursively watching all paths that you have configured and uploading new files.

## Adjusting Paths
You can dynamically add or remove paths, as well as path-specific custom configuration.

```javascript
// Add a new path to watch, with a custom configuration which sets
// an owner. Your `upload` method can use this configuration via
// the `entry.config` attribute.
uploader.watch('/home/daniel/Documents', {owner: 'Kari'});

// Edit an existing watched path
var config = uploader.get('/home/daniel/Pictures');
config.owner = 'Daniel';

// Remove a watched path and its configuration
uploader.unwatch('/home/daniel/Documents');
```

You can then access the custom config during the upload process:

```javascript
uploader.on('upload', function (entry, done) {
  console.log(entry.config.owner);

  // Do your upload
  done()
});
```

## Upload Throttling
It's possible to automatically throttle uploads, or set throttling to a specific value. If you use the `entry.stream` to pipe data to an HTTP request then all concurrent reads will be throttled to the aggregate global throttle value. For example, if three concurrent uploads are being performed, then the combined bandwidth they consume is the throttle limit.

```javascript
// Throttle to 100 kbytes per second
uploader.throttle = 100 * 1024;

// Disable throttling
uploader.throttle = false;
```

## Advanced Example
You can find an advanced, real-world example that uploads files to S3 in [examples/example.litcoffee](https://github.com/danielgtaylor/node-desktop-uploader/blob/master/example/example.litcoffee).

# API Reference
The `DesktopUploader` class is an `EventEmitter` and has the following events, properties, and methods, as well as those [inherited from EventEmitter](http://nodejs.org/api/events.html#events_class_events_eventemitter).

### Events

#### Event: `drain`
Emitted when the last item in the queue has finished uploading (or failed). At this point, the queue is empty and no items are being processed.

```javascript
uploader.on('drain', function () {
  console.log('We are finished!');
});
```

#### Event: `error`
Emitted when an error occurs. The second argument, if present, is the filename which was being processed when the error occured.

```javascript
uploader.on('error', function (err, filename) {
  console.error('Error processing ' + filename + ':', err);
});
```

#### Event: `ignore`
Emitted when a file has been ignored (e.g. incorrect extension, no longer being watched, etc).

```javascript
uploader.on('ignore', function (filename) {
  console.log('Ignoring ' + filename);
});
```

#### Event: `log`
Log a debug message from the uploader.

```javascript
uploader.on('log', function (message) {
  console.log(message);
});
```

#### Event: `pause`
Emitted when the uploader has been paused. The `type` argument will be either `'queue'` or `'watcher'` depending on which was paused.

```javascript
uploader.on('pause', function (type) {
  console.log('Uploader ' + type + ' has been paused!');
});
```

#### Event: `processed`
Emitted after an entry is finished uploading (including retries) and is going to be removed from the queue. Parameters are the enty and whether the upload was successful.

```javascript
uploader.on('processed', function (entry, success) {
  if (success) {
    console.log(entry.path + ' successully uploaded!');
  } else {
    console.log(entry.path + ' failed to upload!');
  }
});
```

#### Event: `queue`
Emitted when an item is added to the queue. This event is fired after the item has been added or changed on disk and after a reasonable effort has been made to ensure it is no longer being written.

```javascript
uploader.on('queue', function (filename, root) {
  console.log('File: ' + filename);
  console.log('Watch path: ' + root);
});
```

#### Event: `resume`
Emitted when the uploader has resumed uploading after being created or paused.

```javascript
uploader.on('resume', function () {
  console.log('Uploader has resumed!');
});
```

#### Event: `upload`
Emitted when a file is ready to be uploaded. This is where you implement custom logic to asyncronously upload the file. The `entry` argument has the following fields:

Name   | Description                              | Example
------ | ---------------------------------------- | -------
config | Custom configuration set on `root`       | `{owner: 'daniel'}`
path   | The full path to the file                | `'/home/daniel/Pictures/2014/IMG_8088.jpg'`
root   | The watched directory path               | `'/home/daniel/Pictures'`
size   | Approximate stream length in bytes       | `102483`
stream | Read stream to pipe into an HTTP request | `ReadableStream`

If throttling is enabled, then `stream` will produce data to keep within your bandwidth limit. This event may be fired multiple times before the first upload has finished.

You **must** call the `done` function to let the uploader know that it can process the next item in the queue.

```javascript
uploader.on('upload', function (entry, done) {
  console.log('Uploading ' + entry.path);

  // Create an HTTP POST request
  var req = http.request({
    method: 'POST',
    hostname: 'your-server.com',
    path: '/widgets',
    headers: {
      authorization: 'bearer abc123def456'
    }
  });

  // Ensure we call `done` in all cases!
  req.on('error', done);

  req.on('response', function (res) {
    if (res.statusCode == 200) {
      done()
    } else {
      done(new Error('Bad response!'));
    }
  });

  // Pipe the file data into the request
  entry.stream.pipe(req);
});
```

#### Event: `unwatch`
Emitted when a folder is unwatched.

```javascript
uploader.on('unwatch', function (paths) {
  console.log('Unwatching:\n' + path.join('\n'));
});

uploader.unwatch('/some/path');
```

#### Event: `watch`
Emitted when a folder is watched.

```javascript
uploader.on('watch', function (path, config) {
  console.log('Watching ' + path);
});

uploader.watch('/some/path', {my: 'config'});
```

### Properties

#### Property: `concurrency = 2`
This value determines the number of concurrent uploads. If throttling is enabled, then all uploads are throttled to the aggregate bandwidth limit. Setting a concurrency limit of `1` means only one upload at a time.

```javascript
uploader.concurrency = 5;
```

#### Property: `modifyInterval = 5000`
This value determines how often in milliseconds a file is checked to see if it has been modified. If a file has not been modified between checks, then it is eligible to be uploaded and an `upload` event will be fired. Defaults to **5 seconds**.

#### Property `retries = 0`
This value determines the automatic retry count. Anytime the `done` function is called with an error during the `upload` event handler it is considered for a retry. The `upload` event will be emitted again up to the number of retries. Set to zero to disable retry logic.

```javascript
# Retry up to two times (total of three upload requests)
uploader.retries = 2;

# Disable retries
uploader.retries = 1;
```

#### Property: `tasks`
A **read-only** array of tasks in the queue. Each task has the following fields:

Name | Description                | Example
---- | -------------------------- | -------
path | The full path to the file  | `'/home/daniel/Pictures/2014/IMG_8088.jpg'`
root | The watched directory path | `'/home/daniel/Pictures'`

#### Property: `throttle = false`
This value determines the bandwidth throttling limit in bytes per second. Setting to `null`, `false`, or no options will disable bandwidth throttling.

```javascript
// Throttle to 10 Kbytes per second
uploader.throttle = 10240;

// Disable throttling
uploader.throttle = false;
```

### Methods

#### Method: Constructor
Create a new `DesktopUploader` instance in a paused state. Takes the following optional parameters:

Parameter      | Description                          | Default
-------------- | ------------------------------------ | -------
concurrency    | Number of concurrent uploads         | `2`
configPath     | Directory to store configuration     | `null`
extensions     | File extensions to watch             | `null`
modifyInterval | Duration in ms to check file writes  | `5000`
name           | Unique name used for configuration   | `'desktop-uploader'`
paths          | List of paths to watch               | `[]`
retries        | Number of retries for failures       | `0`
saveInterval   | Duration in ms to save configuration | `10000`
throttle       | Limit bandwidth in bytes per second  | `null`

Note: extensions are not case-sensitive. You should always supply them in lowercase.

```javascript
var uploader = new DesktopUploader({
  name: 'my-cool-uploader',
  configPath: process.env.HOME,
  paths: ['/some/path', '/another/path'],
  extensions: ['jpg', 'png'],
  throttle: 250 * 1024,
  retries: 1
});
```

#### Method: `get`
Get the configuration for a particular watched directory by its path. You may modify the returned object. If not path is passed, then it returns an object where the keys are paths and the values are configs.

```javascript
var config = uploader.get('/some/path');
config.foo = 3;

var paths = uploader.get();
console.log(paths['/some/path'].foo); // Prints out 3
```

#### Method: `pause`
Temporarily stop the uploader from firing `upload` events. Existing in-flight items will complete, but no new items will be processed until `resume` has been called. File system events will continue to add items on to the queue.

```javascript
uploader.pause();
```

#### Method: `pauseWatcher`
Temporarily ignore all file system events. No new or changed items will be added to the queue until `resume` has been called. The `upload` event will continue to be called for existing items in the queue. See the `pause` method to prevent items already in the queue from being processed.

```javascript
uploader.pauseWatcher();
```

#### Method: `resume`
Start or resume the uploader and watcher. Since the uploader and watcher are created in a paused state, you **must** call this method to begin watching and uploading. Until this method is called, *no* items will be added to the queue and *no* `upload` events are fired.

```javascript
uploader.resume();
```

#### Method: `save`
Give a hint that the uploader should save its configuration to disk in the near future. If `immediate` is `true`, then save to disk right now. If `immediate` is `false`, then at most `saveInterval` milliseconds (see the constructor method) will pass before the file is saved. When your app is about to exit, you must remember to force an immediate save, otherwise data may be lost.

```javascript
// Save in the near future, when convenient
uploader.save();

// Useful to call on app exit
uploader.save(true);
```

#### Method: `unwatch`
Remove a directory from being watched.

```javascript
uploader.unwatch('/some/path');
```

#### Method: `watch`
Add a new directory to recursively watch, with an optional config. The config will be saved between runs and is accessible during the `upload` event via `entry.config`.

```javascript
uploader.watch('/some/path', {
  some: 'optional configuration goes here',
  foo: 2
});
```

## Development
This project uses [Gulp](http://gulpjs.com/) and is written using [CoffeeScript](http://coffeescript.org/). That means that you do not edit the `.js` files in the `lib` folder - those are generated by the build system. Instead, you work on the `src` folder. You can get started like so:

```bash
$ sudo npm install -g gulp
$ git clone https://github.com/danielgtaylor/node-desktop-uploader
$ cd node-desktop-uploader
$ npm install
```

You can edit and then compile the source via:

```bash
$ gulp compile
...
```

You can test in a Node shell via:

```javascript
> var DesktopUploader = require('./lib/main').DesktopUploader;
> uploader = new DesktopUploader();
> ...
```

You can run the unit tests via:

```bash
$ gulp test
...
```

Pull requests are welcome, so please fork the project and submit one! Please keep in mind that any new features should include unit tests coverage, or they may be rejected.

## License
http://dgt.mit-license.org/
