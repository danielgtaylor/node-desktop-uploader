# Desktop Uploader Example
This is an example script that shows off a real-world use of the `desktop-uploader` module. It will watch a given directory and upload any new or changed files to an S3 bucket, throttled to an aggregate maximum of 10 Kbytes per second.

#### How do I run this?
This file can be executed. It is [Literate Coffeescript](http://coffeescript.org/#literate). Just make sure you have Coffeescript installed via `sudo npm install -g coffee-script`. Don't forget to `npm install` to get dependencies before the first time you run the script! It takes four required arguments, like so:

`coffee example.litcoffee PATH ACCESS_KEY SECRED_KEY BUCKET`

Try it out with a folder full of files, or on an empty folder where you copy some new files. Note that it saves state in `./desktop-uploader-example.json` between runs.

## Code
First, import our dependencies. We need the AWS SDK and the desktop uploader module.

    AWS = require 'aws-sdk'
    {DesktopUploader} = require 'desktop-uploader'

AWS needs to know who we are, so let's set the credentials and create an S3 client where we will be storing the data. The actual bucket we will write to is configured later.

    s3 = new AWS.S3
      accessKeyId: process.argv[3]
      secretAccessKey: process.argv[4]

Next, create the uploader. Set the watched path and throttle to 10 Kbytes/sec.

    uploader = new DesktopUploader
      name: 'desktop-uploader-example'
      paths: [process.argv[2]]
      throttle: 10240

This is optional, but we are going to output log info so you can see what is happening. The weird characters are Bash color codes so log messages show up gray.

    uploader.on 'log', (message) ->
      console.log "\x1b[0;90m#{message}\x1b[0m"

Here is the meat of the uploader. We take an entry, which contains a readable stream, and send it to S3 via our S3 client created above. When finished, we let the uploader know by calling `done`.

    uploader.on 'upload', (entry, done) ->
      console.log "Uploading #{entry.path}"

      # We want the path relative to the watched directory, no leading slash
      path = entry.path[entry.root.length...]
      if path[0] is '/' then path = path[1...]

      params =
        Bucket: process.argv[5]
        Key: path
        Body: entry.stream

      start = new Date()

      # Do the upload!
      s3.putObject params, (err, data) ->
        if err
          console.log err
          return done err

        duration = (new Date() - start) / 1000
        console.log "Upload of #{path} took #{duration.toFixed(1)} seconds"
        done()

Now all that's left is to start the uploads!

    uploader.resume()
    console.log 'Uploader started!'
