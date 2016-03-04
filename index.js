// Generated by CoffeeScript 1.10.0
var Bucket, EventEmitter, Path, Queue, STATE_FILENAME, chokidar, cluster, debug, endsWith, error, fs, os, utils, versionFromLoaderString, watcher,
  bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
  extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  hasProp = {}.hasOwnProperty,
  slice = [].slice,
  indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

fs = require('fs');

cluster = require('cluster');

utils = require('./utils');

debug = require('debug')('parallelTranspile');

Path = require('path');

STATE_FILENAME = ".parallel-transpile.state";

cluster.setupMaster({
  exec: __dirname + "/worker",
  args: []
});

if (!cluster.isMaster) {
  require(__dirname + "/worker");
  return;
}

EventEmitter = require('events');

chokidar = require('chokidar');

os = require('os');

error = function(code, message) {
  var err;
  err = new Error(message);
  err.code = code;
  return err;
};

endsWith = function(str, end) {
  return str.substr(str.length - end.length) === end;
};

versionFromLoaderString = function(l) {
  var loaderName;
  loaderName = l.replace(/\?.*$/, "");
  return require(loaderName + "/package.json").version;
};

watcher = null;

Bucket = (function(superClass) {
  extend(Bucket, superClass);

  function Bucket(options1) {
    var ref;
    this.options = options1 != null ? options1 : {};
    this.receive = bind(this.receive, this);
    this.capacity = (ref = this.options.bucketCapacity) != null ? ref : 3;
    this.queue = [];
    this.child = cluster.fork();
    this.id = this.child.id;
    this.child.send({
      init: this.options
    });
    this.child.on('message', this.receive);
  }

  Bucket.prototype.receive = function(message) {
    var task;
    task = this.queue.shift();
    this.perform();
    if ((message != null ? message.msg : void 0) === 'complete') {
      return this.emit('complete', this, null, task, message.details);
    } else {
      return this.emit('complete', this, message, task);
    }
  };

  Bucket.prototype.add = function(task) {
    this.queue.push(task);
    if (this.queue.length === 1) {
      return this.perform();
    }
  };

  Bucket.prototype.perform = function() {
    var task;
    task = this.queue[0];
    if (!task) {
      return;
    }
    return this.child.send(task);
  };

  Bucket.prototype.destroy = function() {
    return this.child.kill();
  };

  return Bucket;

})(EventEmitter);

Queue = (function(superClass) {
  extend(Queue, superClass);

  function Queue(options1, oneshot) {
    this.options = options1;
    this.oneshot = oneshot;
    this.remove = bind(this.remove, this);
    this.add = bind(this.add, this);
    this.complete = bind(this.complete, this);
    this.destroy = bind(this.destroy, this);
    this.paused = true;
    this.queue = [];
    this.inProgress = [];
  }

  Queue.prototype.destroy = function() {
    var bucket, j, len, ref;
    if (!this.buckets) {
      return;
    }
    process.removeListener('exit', this.destroy);
    ref = this.buckets;
    for (j = 0, len = ref.length; j < len; j++) {
      bucket = ref[j];
      bucket.destroy();
    }
    return this.buckets = null;
  };

  Queue.prototype.complete = function(bucket, err, task, details) {
    var base, deps, i, outPath, path;
    if (details == null) {
      details = {};
    }
    path = task.path;
    if (err) {
      if (typeof (base = this.options).onError === "function") {
        base.onError(err);
      }
      debug("[" + bucket.id + "] Failed: " + path);
    } else {
      deps = Object.keys(details.dependencies).slice(1);
      if (deps.length) {
        if (watcher) {
          deps.forEach(function(p) {
            return watcher.add(p);
          });
        }
        deps = deps.map((function(_this) {
          return function(p) {
            return Path.relative(_this.options.source, p);
          };
        })(this));
        debug("[" + bucket.id + "] Processed: " + path + " (deps: " + deps + ")");
      } else {
        debug("[" + bucket.id + "] Processed: " + path);
      }
      outPath = details.outPath;
      delete details.outPath;
      details.loaders = task.rule.loaders.map(function(l) {
        return [
          l, {
            version: versionFromLoaderString(l)
          }
        ];
      });
      details.ruleDependencies = (task.rule.dependencies || []).map(function(dep) {
        var depStat;
        depStat = fs.statSync(dep);
        return [
          dep, {
            mtime: depStat.mtime
          }
        ];
      });
      this.options.setFileState(outPath, details);
    }
    i = this.inProgress.indexOf(path);
    if (i === -1) {
      throw new Error("This shouldn't be able to happen");
    }
    this.inProgress.splice(i, 1);
    this.processNext();
    if (this.inProgress.length === 0) {
      this.emit('empty');
      if (this.oneshot) {
        this.destroy();
      }
    }
  };

  Queue.prototype.run = function() {
    var bucket, i, j, ref;
    this.buckets = [];
    for (i = j = 0, ref = this.options.parallel; 0 <= ref ? j < ref : j > ref; i = 0 <= ref ? ++j : --j) {
      bucket = new Bucket(this.options);
      bucket.on('complete', this.complete);
      this.buckets.push(bucket);
    }
    process.on('exit', this.destroy);
    delete this.paused;
    this.processNext();
    if (!(this.inProgress.length > 0)) {
      this.emit('empty');
    }
    return this;
  };

  Queue.prototype.rule = function(path) {
    var j, len, ref, rule;
    ref = this.options.rules;
    for (j = 0, len = ref.length; j < len; j++) {
      rule = ref[j];
      if (endsWith(path, rule.inExt)) {
        return rule;
      }
    }
    return null;
  };

  Queue.prototype.add = function(path) {
    if (this.queue.indexOf(path) === -1 && this.rule(path)) {
      this.queue.push(path);
      return this.processNext();
    }
  };

  Queue.prototype.remove = function(path) {
    var i;
    i = this.queue.indexOf(path);
    if (i !== -1) {
      return this.queue.splice(i, 1);
    }
  };

  Queue.prototype.processNext = function() {
    var availablePath, bestBucket, bestBucketScore, bucket, i, j, k, len, len1, path, ref, ref1, score;
    if (this.paused) {
      return;
    }
    if (!this.queue.length) {
      return;
    }
    bestBucket = null;
    bestBucketScore = 0;
    ref = this.buckets;
    for (j = 0, len = ref.length; j < len; j++) {
      bucket = ref[j];
      if ((score = bucket.capacity - bucket.queue.length) > 0) {
        if (!bestBucket || score > bestBucketScore) {
          bestBucket = bucket;
        }
      }
    }
    if (!bestBucket) {
      return;
    }
    ref1 = this.queue;
    for (i = k = 0, len1 = ref1.length; k < len1; i = ++k) {
      path = ref1[i];
      if (!(this.inProgress.indexOf(path) === -1)) {
        continue;
      }
      availablePath = path;
      this.queue.splice(i, 1);
      break;
    }
    if (!availablePath) {
      return;
    }
    this.inProgress.push(availablePath);
    bestBucket.add({
      path: availablePath,
      rule: this.rule(availablePath)
    });
    return this.processNext();
  };

  return Queue;

})(EventEmitter);

module.exports = function(options, callback) {
  var base, error1, errorOccurred, getStatus, inExt, j, len, loaders, matches, oldOnError, outExt, queue, recurse, ref, ref1, ref2, ref3, state, type, upToDate, watchChange, watchQueue, watchRemove;
  if (!fs.existsSync(options.source) || !fs.statSync(options.source).isDirectory()) {
    return callback(error(2, "Input must be a directory"));
  }
  if (!options.output) {
    return callback(error(1, "No output directory specified"));
  }
  if (!fs.existsSync(options.output) || !fs.statSync(options.output).isDirectory()) {
    return callback(error(3, "Output option must be a directory"));
  }
  options.output = Path.resolve(options.output);
  options.source = Path.resolve(options.source);
  if (options.rules == null) {
    options.rules = [];
  }
  if (options.type && !Array.isArray(options.type)) {
    options.type = [options.type];
  }
  ref1 = (ref = options.type) != null ? ref : [];
  for (j = 0, len = ref1.length; j < len; j++) {
    type = ref1[j];
    matches = type.match(/^([^:]*)(?::([^:]*)(?::([^:]*))?)?$/);
    if (!matches) {
      return callback(error(1, "Invalid type specification: '" + type + "'"));
    }
    ref2 = matches.slice(1), inExt = ref2[0], loaders = ref2[1], outExt = ref2[2];
    if (loaders == null) {
      loaders = "";
    }
    if (outExt == null) {
      outExt = inExt;
    }
    options.rules.push({
      inExt: inExt,
      loaders: loaders.split(",").filter(function(a) {
        return a.length > 0;
      }),
      outExt: outExt
    });
  }
  if (options.parallel != null) {
    options.parallel = parseInt(options.parallel, 10);
    if (!isFinite(options.parallel) || options.parallel < 0) {
      delete options.parallel;
      console.error("Did not understand parallel option value, discarding it.");
    }
  }
  if (options.maxParallel != null) {
    options.maxParallel = parseInt(options.maxParallel, 10);
    if (!isFinite(options.maxParallel) || options.maxParallel < 0) {
      delete options.maxParallel;
      console.error("Did not understand maxParallel option value, discarding it.");
    }
  }
  options.parallel || (options.parallel = os.cpus().length);
  options.parallel = Math.min(options.parallel, (ref3 = options.maxParallel) != null ? ref3 : 16);
  if (options.watch) {
    watchQueue = new Queue(options);
    watchChange = function(file) {
      var dependencies, deps, ref4, ref5, results, self, sourceWithSlash, stateFile;
      sourceWithSlash = options.source + "/";
      if (file.substr(0, sourceWithSlash.length) === sourceWithSlash) {
        watchQueue.add(file);
      }
      ref4 = options.state.files;
      results = [];
      for (stateFile in ref4) {
        dependencies = ref4[stateFile].dependencies;
        ref5 = Object.keys(dependencies), self = ref5[0], deps = 2 <= ref5.length ? slice.call(ref5, 1) : [];
        if (indexOf.call(deps, file) >= 0) {
          results.push(watchQueue.add(self));
        } else {
          results.push(void 0);
        }
      }
      return results;
    };
    watchRemove = function(file) {
      return watchQueue.remove(file);
    };
    watcher = chokidar.watch(options.source);
    watcher.on('ready', function() {
      watcher.on('add', watchChange);
      watcher.on('change', watchChange);
      return watcher.on('unlink', watchRemove);
    });
  }
  oldOnError = options.onError;
  errorOccurred = false;
  options.onError = function() {
    errorOccurred = true;
    return oldOnError != null ? oldOnError.apply(this, arguments) : void 0;
  };
  try {
    state = JSON.parse(fs.readFileSync(options.output + "/" + STATE_FILENAME));
  } catch (error1) {
    state = {};
  }
  options.state = state;
  if ((base = options.state).files == null) {
    base.files = {};
  }
  options.setFileState = function(filename, obj) {
    options.state.files[filename] = obj;
    return fs.writeFileSync(options.output + "/" + STATE_FILENAME, JSON.stringify(options.state));
  };
  upToDate = function(filename, rule) {
    var c, currentVersion, file, k, l, len1, loaderConfigs, mtime, obj, ref4, ref5, ref6, ref7, stat2, version;
    obj = options.state.files[filename];
    if (!obj) {
      return false;
    }
    ref4 = obj.dependencies;
    for (file in ref4) {
      mtime = ref4[file].mtime;
      stat2 = (function() {
        try {
          return fs.statSync(file);
        } catch (undefined) {}
      })();
      if (!stat2) {
        return false;
      }
      if (+stat2.mtime > mtime) {
        return false;
      }
    }
    loaderConfigs = (ref5 = obj.loaders) != null ? ref5.map(function(c) {
      return c[0];
    }) : void 0;
    if (rule.loaders.join("$$") !== (loaderConfigs != null ? loaderConfigs.join("$$") : void 0)) {
      return false;
    }
    ref6 = obj.loaders;
    for (k = 0, len1 = ref6.length; k < len1; k++) {
      c = ref6[k];
      l = c[0], (ref7 = c[1], version = ref7.version);
      currentVersion = versionFromLoaderString(l);
      if (currentVersion !== version) {
        return false;
      }
    }
    return true;
  };
  queue = new Queue(options, true);
  recurse = function(path) {
    var aRule, file, filePath, files, k, len1, len2, m, outPath, ref4, relativePath, rule, shouldAdd, stat;
    files = fs.readdirSync(path);
    for (k = 0, len1 = files.length; k < len1; k++) {
      file = files[k];
      if (!(!file.match(/^\.+$/))) {
        continue;
      }
      filePath = path + "/" + file;
      stat = fs.statSync(filePath);
      if (stat.isDirectory()) {
        recurse(filePath);
      } else if (stat.isFile()) {
        shouldAdd = true;
        if (options.newer) {
          rule = null;
          ref4 = options.rules;
          for (m = 0, len2 = ref4.length; m < len2; m++) {
            aRule = ref4[m];
            if (!(endsWith(filePath, aRule.inExt))) {
              continue;
            }
            rule = aRule;
            break;
          }
          if (rule) {
            inExt = rule.inExt, outExt = rule.outExt;
            relativePath = filePath.substr(options.source.length);
            outPath = Path.resolve(options.output + "/" + (utils.swapExtension(relativePath, inExt, outExt)));
            if (upToDate(outPath, rule)) {
              shouldAdd = false;
            }
          }
        }
        if (shouldAdd) {
          queue.add(filePath);
        }
      }
    }
  };
  recurse(options.source);
  getStatus = function(clear) {
    if (errorOccurred) {
      if (clear) {
        errorOccurred = false;
      }
      return new Error("An error occurred");
    } else {
      return null;
    }
  };
  queue.on('empty', function() {
    var status;
    debug("INITIAL BUILD COMPLETE");
    status = getStatus(false);
    if (typeof options.initialBuildComplete === "function") {
      options.initialBuildComplete(status);
    }
    queue.destroy();
    queue = null;
    if (watchQueue != null) {
      errorOccurred = false;
      watchQueue.on('empty', function() {
        return typeof options.watchBuildComplete === "function" ? options.watchBuildComplete(getStatus(true)) : void 0;
      });
      return watchQueue.run();
    } else {
      return callback(status);
    }
  });
  queue.run();
  return {
    kill: function() {
      if (queue != null) {
        queue.destroy();
      }
      if (watchQueue != null) {
        watchQueue.destroy();
      }
      return watcher != null ? watcher.close() : void 0;
    }
  };
};

//# sourceMappingURL=index.js.map
