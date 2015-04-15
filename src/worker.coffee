process.on 'message', (m) ->
  process.send 'complete'
