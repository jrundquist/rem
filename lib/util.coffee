Array::chunk = (n) ->
  return [] if not @.length
  [ @.slice 0, n ].concat( @.slice(n).chunk(n) )


Array::unique = ->
  output = {}
  output[@[key]] = @[key] for key in [0...@length]
  value for key, value of output



Object.defineProperty(global, '__stack',
  get: () ->
    orig = Error.prepareStackTrace;
    Error.prepareStackTrace = (_, stack) -> return stack
    err = new Error;
    Error.captureStackTrace err, arguments.callee
    stack = err.stack;
    Error.prepareStackTrace = orig;
    stack
)

Object.defineProperty(global, '__function',
  get: () -> return __stack[1].getFunctionName()
);
