-- used to run code at initialization time, when options are available,
-- and at finalization time

local insert = table.insert

module(...)

local is, fs = {}, {}

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

