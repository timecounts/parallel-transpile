fs = require 'fs'

error = (code, message) ->
  err = new Error message
  err.code = code
  return err

module.exports = (argv, callback) ->
  if !fs.existsSync(argv.source) or !fs.statSync(argv.source).isDirectory()
    return callback error(2, "Input must be a directory")

  if !argv.output
    return callback error(1, "No output directory specified")

  if !fs.existsSync(argv.output) or !fs.statSync(argv.output).isDirectory()
    return callback error(3, "Output option must be a directory")
