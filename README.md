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

License
-------

[MIT](http://benjie.mit-license.org/)
