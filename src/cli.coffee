main = require './index'

error = (message) ->
  message = message.toString()
  message = "Error: #{message}" unless message.match /^Error/
  console.error message

usage = ->
  console.log """
    Usage: parallel-transpile [options] -o outputDirectory inputDirectory

      -h, --help          display this help message
      -v, --version       output version number
      -w, --watch         watch input directories for changes
      -o, --output        the output directory
      -p, --parallel      how many instances to run in parallel
                            (defaults to number of CPUs)
      -t, --type          add a type to be converted, see below
                            (can be called multiple times)
      -n, --newer         only build files newer than destination files

    Types

      Each type takes an input filter (file extension), a list of loaders, and
      an output extension. To copy a file verbatim, only the input filter is
      required.

      For example, to copy all JSON files verbatim:

        -t ".json"

      To compile a CJSX file to JavaScript:

        -t ".cjsx:coffee-loader,cjsx-loader:.js"

      Loaders operate from right to left, like in webpack.
    """

minimistOptions =
  alias:
    "h": "help"
    "v": "version"
    "o": "output"
    "p": "parallel"
    "w": "watch"
    "t": "type"
    "n": "newer"

  string: [
    "output"
    "parallel"
    "type"
  ]

  boolean: [
    "watch"
    "newer"
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

if argv.version
  console.log require('./package.json').version
  process.exit(0)

if argv._.length < 1
  error("No input directory specified")
  usage()
  process.exit(1)

if argv._.length > 1
  error("Only one input directory can be specified")
  usage()
  process.exit(1)

argv.source = argv._[0]

main argv, (err) ->
  if err
    error(err.toString())
    if err.code is 1
      usage()
    process.exit(err.code ? 10)
    return
