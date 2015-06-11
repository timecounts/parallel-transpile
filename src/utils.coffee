exports.swapExtension = (path, a, b) ->
  if path.substr(path.length - a.length) is a
    return path.substr(0, path.length - a.length) + b
  return path
