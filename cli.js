// Generated by CoffeeScript 1.10.0
var argv, error, k, main, minimistOptions, usage, v;

main = require('./index');

error = function(message) {
  message = message.toString();
  if (!message.match(/^Error/)) {
    message = "Error: " + message;
  }
  return console.error(message);
};

usage = function() {
  return console.log("Usage: parallel-transpile [options] -o outputDirectory inputDirectory\n\n  -h, --help          display this help message\n  -v, --version       output version number\n  -w, --watch         watch input directories for changes\n  -o, --output        the output directory\n  -p, --parallel      how many instances to run in parallel\n                        (defaults to number of CPUs)\n  -t, --type          add a type to be converted, see below\n                        (can be called multiple times)\n  -n, --newer         only build files newer than destination files\n\nTypes\n\n  Each type takes an input filter (file extension), a list of loaders, and\n  an output extension. To copy a file verbatim, only the input filter is\n  required.\n\n  For example, to copy all JSON files verbatim:\n\n    -t \".json\"\n\n  To compile a CJSX file to JavaScript:\n\n    -t \".cjsx:coffee-loader,cjsx-loader:.js\"\n\n  Loaders operate from right to left, like in webpack.");
};

minimistOptions = {
  alias: {
    "h": "help",
    "v": "version",
    "o": "output",
    "p": "parallel",
    "w": "watch",
    "t": "type",
    "n": "newer"
  },
  string: ["output", "parallel", "type"],
  boolean: ["watch", "newer"],
  multiple: ["type"],
  unknown: function(o) {
    if (o.slice(0, 1) === "-") {
      error("Unknown option '" + o + "'");
      usage();
      return process.exit(1);
    }
  }
};

argv = require('minimist')(process.argv.slice(2), minimistOptions);

for (k in argv) {
  if (minimistOptions.alias[k]) {
    delete argv[k];
  }
}

for (k in argv) {
  v = argv[k];
  if (k !== "_") {
    if (Array.isArray(v) && minimistOptions.multiple.indexOf(k) === -1) {
      argv[k] = v.pop();
    }
  }
}

if (argv.help) {
  usage();
  process.exit(0);
}

if (argv.version) {
  console.log(require('./package.json').version);
  process.exit(0);
}

if (argv._.length < 1) {
  error("No input directory specified");
  usage();
  process.exit(1);
}

if (argv._.length > 1) {
  error("Only one input directory can be specified");
  usage();
  process.exit(1);
}

argv.source = argv._[0];

main(argv, function(err) {
  var ref;
  if (err) {
    error(err.toString());
    if (err.code === 1) {
      usage();
    }
    process.exit((ref = err.code) != null ? ref : 10);
  }
});
