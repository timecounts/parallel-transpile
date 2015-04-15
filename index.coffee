fs = require 'fs'

error = (message) ->
  console.error "ERROR: #{message}"

usage = ->
  console.log """
    Usage: parallel-transpile [options] -o outputDirectory inputDirectory

      -h, --help          display this help message
      -w, --watch         watch input directories for changes
      -o, --output        the output directory
      -t, --type          add a type to be converted, see below
                            (can be called multiple times)

    Types

      Each type takes an input filter (file extension), a list of loaders, and
      an output extension.

      For example, to copy all JSON files verbatim:

        -t ".json::.json"

      To compile a CJSX file to JavaScript:

        -t ".cjsx:cjsx-loader,coffee-loader:.js"
    """

minimistOptions =
  alias:
    "h": "help"
    "o": "output"
    "w": "watch"
    "t": "type"

  string: [
    "output"
  ]

  boolean: [
    "watch"
  ]

  multiple: [
    "type"
  ]

  unknown: (o) ->
    if o[0..0] is "-"
      error("Unknown option '#{o}'")
      usage()
      process.exit(1)

argv = require('minimist')(process.argv[2..], minimistOptions)

delete argv[k] for k of argv when minimistOptions.alias[k]

for k, v of argv when k isnt "_"
  if Array.isArray(v) and minimistOptions.multiple.indexOf(k) is -1
    argv[k] = v.pop()

if argv.help
  usage()
  process.exit(0)

argv.source = argv._[0]
if argv._.length < 1
  error("No input directory specified")
  usage()
  process.exit(1)

if argv._.length > 1
  error("Only one input directory can be specified")
  usage()
  process.exit(1)

if !fs.existsSync(argv.source) or !fs.statSync(argv.source).isDirectory()
  error("Input must be a directory")
  process.exit(2)

if !argv.output
  error("No output directory specified")
  usage()
  process.exit(1)

if !fs.existsSync(argv.output) or !fs.statSync(argv.output).isDirectory()
  error("Output option must be a directory")
  process.exit(3)
