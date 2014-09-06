coffee = require 'gulp-coffee'
coveralls = require 'gulp-coveralls'
gulp = require 'gulp'
istanbul = require 'gulp-istanbul'
lint = require 'gulp-coffeelint'
mocha = require 'gulp-mocha'

gulp.task 'compile', ->
  gulp.src 'src/**/*.coffee'
    .pipe lint()
    .pipe lint.reporter()
    .pipe coffee()
    .pipe gulp.dest('lib')

gulp.task 'watch', ->
  gulp.watch 'src/**/*.coffee', ['compile']

gulp.task 'test', ['compile'], (done) ->
  gulp.src 'lib/**/*.js'
    .pipe istanbul()
    .on 'finish', ->
      gulp.src 'tests/**/*.coffee', read: false
        .pipe mocha(reporter: 'spec')
        .pipe istanbul.writeReports
          reporters: ['text-summary', 'html', 'lcovonly']

gulp.task 'coveralls', ->
  gulp.src 'coverage/lcov.info'
    .pipe coveralls()

gulp.task 'default', ['compile', 'watch']
