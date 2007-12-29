-- Everything to do with logging

local io, table, pairs, string, require, type
    = io, table, pairs, string, require, type 

module(...)

local util  = require(_PACKAGE .. 'util')
local cfg   = require(_PACKAGE .. 'cfg')

----------------------------------------------------------------

__doc = { }

__doc.logf = [[function(...) logs stringf(...) as a comment with date]]
__doc.lua = [[function(name, value) logs call(name, value) as a command
'name' must a a valid lua identifier.
]]
                 
local logfile
cfg.after_loading_do(function() logfile = cfg.dirs.log .. 'osbf_log' end)

function lua(f, v)
  fh = util.validate(io.open(logfile, 'a+'))
  if type(f) ~= 'string' or not string.find(f, '^%a[%w_]*$') or util.reserved[f] then
    error(tostring(f) .. ' is not a valid Lua identifier', 2)
  end
  local fmt
  if type(v) == 'string' or type(v) == 'table' then
    fmt = '(...).%s %s;\n'  -- semicolon needed to avoid ambiguity
  else
    fmt = '(...).%s (%s);\n'
  end
  fh:write(string.format(fmt, f, util.image(v)))
  fh:close()
end

function logf(...)
  return lua('log', os.date() .. ': ' .. string.format(...))
end
