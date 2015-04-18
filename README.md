Parallel Transpile
==================

This npm module uses webpack loaders and all your CPUs to transpile
source as quick as it can.

Installation
------------

`npm install -g parallel-transpile`

Usage
-----

```
Usage: parallel-transpile [options] -o outputDirectory inputDirectory

  -h, --help          display this help message
  -w, --watch         watch input directories for changes
  -o, --output        the output directory
  -t, --type          add a type to be converted, see below
                        (can be called multiple times)

Types

  Each type takes an input filter (file extension), a list of loaders, and
  an output extension. To copy a file verbatim, only the input filter is
  required.

  For example, to copy all JSON files verbatim:

    -t ".json"

  To compile a CJSX file to JavaScript:

    -t ".cjsx:coffee-loader,cjsx-loader:.js"

  Loaders operate from right to left, like in webpack.
```

Example
-------

The following example recurses through the `src` folder, converting all
`.cjsx`, `.coffee` and `.litcoffee` files to `.js` and copying all `.js`
and `.json` files verbatim into the `build` directory. It also watches
for changes in `src` (including additions), updating the build directory
as required.

```
parallel-transpile \
  -o build \
  -w \
  -t .cjsx:jsx-loader,coffee-loader,cjsx-loader:.js \
  -t .coffee:coffee-loader:.js \
  -t .litcoffee:coffee-loader?literate:.js \
  -t .json \
  -t .js \
  src
```

Usage as a module
-----------------

You can also use parallel-transpile as a module, which can be useful
e.g. in grunt. For a simple parallel build you might do something like:

```
var parallelTranspile = require('parallel-transpile');

grunt.registerTask("parallel-transpile", function() {
  var done = @async();
  var options = {
    output: "build",
    source: "src",

    types: [
      ".cjsx:jsx-loader,coffee-loader,cjsx-loader:.js",
      ".coffee:coffee-loader:.js",
      ".litcoffee:coffee-loader?literate:.js",
      ".json",
      ".js"
    ]
  };

  parallelTranspile(options, done);
});

```

The real power comes when you combine this with watching for changes.
You can have your grunt task wait for the initial build to complete
before moving on to the next grunt task but continue watching for
changes in the background, like this:

```
var parallelTranspile = require('parallel-transpile');

grunt.registerTask("parallel-transpile:watch", function() {
  var done = @async();
  var options = {
    output: "build",
    source: "src",

    types: [
      ".cjsx:jsx-loader,coffee-loader,cjsx-loader:.js",
      ".coffee:coffee-loader:.js",
      ".litcoffee:coffee-loader?literate:.js",
      ".json",
      ".js"
    ],

    watch: true,
    initialBuildComplete: done
  };

  parallelTranspile(options, function() {
    console.error("Parallel-transpile exited");
  });
});

```

License
-------

[MIT](http://benjie.mit-license.org/)