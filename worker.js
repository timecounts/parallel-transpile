// Generated by CoffeeScript 1.10.0
var ApplySourceMap, Path, fs, init, loaders, mkdirp, output, send, source, utils;

fs = require('fs');

Path = require('path');

mkdirp = require('mkdirp');

ApplySourceMap = require('apply-source-map');

utils = require('./utils');

loaders = {};

source = null;

output = null;

send = function(message) {
  if (message instanceof Error) {
    console.error(message.stack);
    message = {
      error: true,
      message: message.toString(),
      stack: message.stack
    };
  }
  return process.send(message);
};

init = function(options) {
  source = options.source.replace(/\/*$/, "/");
  return output = options.output.replace(/\/+$/, "");
};

process.on('message', function(m) {
  var _, applyNext, baseName, err, error, finished, i, inExt, j, len, loader, loaderModule, mapPath, moduleName, outExt, outPath, path, query, ref, ref1, relativePath, remainingLoaderModules, requestString, sourceMaps, src, webpackLoaders;
  if (m.init) {
    return init(m.init);
  }
  if (!source) {
    throw new Error("Not initialised");
  }
  path = m.path, (ref = m.rule, inExt = ref.inExt, loaders = ref.loaders, outExt = ref.outExt);
  relativePath = path.substr(source.length);
  outPath = output + "/" + (utils.swapExtension(relativePath, inExt, outExt));
  mapPath = output + "/" + (utils.swapExtension(relativePath, inExt, ".map"));
  webpackLoaders = [];
  baseName = Path.basename(relativePath);
  requestString = baseName;
  for (j = 0, len = loaders.length; j < len; j++) {
    loader = loaders[j];
    try {
      requestString = loader + "!" + requestString;
      ref1 = loader.match(/^([^?]+)(\?.*)?$/), _ = ref1[0], moduleName = ref1[1], query = ref1[2];
      loaderModule = require(moduleName);
      webpackLoaders.push({
        request: requestString,
        path: baseName,
        query: query,
        module: loaderModule
      });
    } catch (error) {
      err = error;
      return send(err);
    }
  }
  src = fs.readFileSync(path);
  sourceMaps = [];
  remainingLoaderModules = webpackLoaders.slice(0);
  i = remainingLoaderModules.length;
  finished = function() {
    var nextMap, sourceMapString;
    mkdirp.sync(Path.dirname(outPath));
    if (sourceMaps.length && outPath.match(/\.js$/)) {
      sourceMaps.map(function(sourceMap) {
        var absoluteOutPath, absolutePath;
        sourceMap.file = Path.basename(outPath);
        absoluteOutPath = Path.resolve(outPath);
        absolutePath = Path.resolve(path);
        sourceMap.sources = [Path.relative(Path.dirname(absoluteOutPath), absolutePath)];
        return delete sourceMap.sourcesContent;
      });
      if (sourceMaps.length === 1) {
        sourceMapString = JSON.stringify(sourceMaps[0]);
      } else {
        sourceMapString = JSON.stringify(sourceMaps.shift());
        while (nextMap = sourceMaps.shift()) {
          sourceMapString = ApplySourceMap(sourceMapString, nextMap);
        }
      }
      src = (src.toString('utf8')) + "\n//# sourceMappingURL=" + (Path.basename(mapPath));
    }
    fs.writeFileSync(outPath, src);
    if (sourceMapString) {
      fs.writeFileSync(mapPath, sourceMapString);
    }
    return send('complete');
  };
  applyNext = function() {
    var asyncCallback, context, error1, input, next, out;
    next = remainingLoaderModules.pop();
    i--;
    if (!next) {
      return finished();
    }
    asyncCallback = false;
    context = {
      version: 1,
      request: next.request,
      path: next.path,
      resource: baseName,
      resourcePath: baseName,
      resourceQuery: "",
      query: next.query,
      sourceMap: true,
      loaderIndex: i,
      loaders: webpackLoaders,
      async: function() {
        return asyncCallback = true;
      },
      callback: function(err, out, map) {
        asyncCallback = true;
        if (err) {
          send(err);
          return;
        }
        if (out instanceof Buffer) {
          src = out;
        } else {
          src = new Buffer(out);
        }
        if (map) {
          sourceMaps.push(map);
        }
        return applyNext();
      }
    };
    try {
      if (next.module.raw) {
        input = src;
      } else {
        input = src.toString('utf8');
      }
      out = next.module.call(context, input);
      if (!asyncCallback) {
        if (out instanceof Buffer) {
          src = out;
        } else {
          src = new Buffer(out);
        }
        return applyNext();
      }
    } catch (error1) {
      err = error1;
      send(err);
    }
  };
  return applyNext();
});
