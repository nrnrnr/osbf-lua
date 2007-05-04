-- used to run code at initialization time, when options are available,
-- and at finalization time

local insert = table.insert

module(...)

local is, fs = {}, {}

__doc = {
  __order = { 'initializer', 'finalizer', 'init', 'final' },

  initializer = [[function(f)
Registers a function f that is called by 'boot.init' with the
same arguments as 'boot.init'.  Functions are called in the 
order of registration.]],

  finalizer = [[function(f)
Registers a function f that is called by 'boot.final' with the
same arguments as 'boot.init'.  Functions are called in 
*reverse* order of registration.]],

  init = [[function(...)
Call functions registered by 'boot.initializer', in order
of registration, passing arguments as received.]],

  final = [[function(...)
Call functions registered by 'boot.finalizer', in *reverse*
order of registration, passing arguments as received.]],
}

function initializer(f)
  insert(is, f)
end

function finalizer(f)
  insert(fs, f)
end

function init(...)
  for i = 1, #is do
    is[i](...)
  end
end

function final(...)
  for i = #fs, 1, -1 do
    fs[i](...)
  end
end
