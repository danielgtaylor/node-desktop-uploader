# Desktop Uploader
The `desktop-uploader` module lets you easily write a desktop uploader for a remote service such as Dropbox, S3, Google Storage, or your own company. You define directories to watch and a function that uploads a file entry, and `desktop-uploader` handles the rest!

#### Features

* Recursively watch folders and files for changes
  * Uses native events (fsevents, inotify, ReadDirectoryChangesW)
* Store per-folder custom configuration between runs
* Determine when a file is no longer being modified
* Upload files using custom business logic
* Concurrently upload many files
* Keep a cache of info on already-uploaded files
* Throttle aggregate uploads to a set bandwidth (e.g. 100Kbytes/sec)
* Works with [atom-shell](https://github.com/atom/atom-shell) and [node-webkit](https://github.com/rogerwang/node-webkit) for a user cross-platform interface

#### Improvement Ideas

* Custom cache and ignore strategies (e.g. file hash instead of last modified time)

## Installation
Install like any other Node.js package, with NPM:

```bash
$ npm install --save desktop-uploader
```

## Basic Example

Create a new desktop uploader instance. It takes an optional options object where you can set initial paths to watch and a few options, like the number of concurrent uploads. **Note**: the uploader is created in a paused state.

```javascript
var DesktopUploader = require('desktop-uploader').DesktopUploader;
var request = require('request');

var uploader = new DesktopUploader({
  name: 'my-cool-app',
  paths: ['/home/daniel/Pictures'],
  concurrency: 3
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
uploader.throttle(100 * 1024);

// Disable throttling
uploader.throttle(false);
```

## Advanced Example
You can find an advanced, real-world example that uploads files to S3 in [examples/example.litcoffee](/danielgtaylor/desktop-uploader/blob/master/example/example.litcoffee).

# API Reference
The `DesktopUploader` class is an `EventEmitter` and has the following events, properties, and methods, as well as those [inherited from EventEmitter](http://nodejs.org/api/events.html#events_class_events_eventemitter).

### Events

#### Event: `error`
Emitted when an error occurs. The second argument, if present, is the filename which was being processed when the error occured.

```javascript
uploader.on('error', function (err, filename) {
  console.error('Error processing ' + filename + ':', err);
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
Emitted when the uploader has been paused.

```javascript
uploader.on('pause', function () {
  console.log('Uploader has been paused!');
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

### Properties

#### Property: `modifyInterval = 5000`
This value determines how often in milliseconds a file is checked to see if it has been modified. If a file has not been modified between checks, then it is eligible to be uploaded and an `upload` event will be fired. Defaults to **5 seconds**.

### Methods

#### Method: Constructor
Create a new `DesktopUploader` instance in a paused state. Takes the following optional parameters:

Parameter      | Description                          | Default
-------------- | ------------------------------------ | -------
concurrency    | Number of concurrent uploads         | `2`
configPath     | Directory to store configuration     | `null`
modifyInterval | Duration in ms to check file writes  | `5000`
name           | Unique name used for configuration   | `'desktop-uploader'`
paths          | List of paths to watch               | `[]`
saveInterval   | Duration in ms to save configuration | `10000`
throttle       | Limit bandwidth in bytes per second  | `null`

```javascript
var uploader = new DesktopUploader({
  name: 'my-cool-uploader',
  configPath: process.env.HOME,
  paths: ['/some/path', '/another/path'],
  throttle: 250 * 1024
});
```

#### Method: `concurrency`
Set the number of concurrent uploads. If throttling is enabled, then all uploads are throttled to the aggregate bandwidth limit. Setting a concurrency limit of `1` means only one upload at a time.

```javascript
uploader.concurrency(5);
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
Stop the uploader. Existing in-flight items will complete, but no new items will be processed until `resume` has been called.

```javascript
uploader.pause();
```

#### Method: `resume`
Start or resume the uploader. Since the uploader is created in a paused state, you **must** call this method to begin uploading.

```javascript
uploader.resume();
```

#### Method: `throttle`
Set the bandwidth throttling limit in bytes per second. Passing in `null`, `false`, or no options will disable bandwidth throttling.

```javascript
// Throttle to 10 Kbytes per second
uploader.throttle(10240);

// Disable throttling
uploader.throttle();
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

## License
http://dgt.mit-license.org/
