// Generated by CoffeeScript 1.10.0
exports.swapExtension = function(path, a, b) {
  if (path.substr(path.length - a.length) === a) {
    return path.substr(0, path.length - a.length) + b;
  }
  return path;
};

//# sourceMappingURL=utils.js.map
