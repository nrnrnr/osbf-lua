-- Everything to do with logging
--
-- See Copyright Notice in osbf.lua


local io, os, table, pairs, string, require, type
    = io, os, table, pairs, string, require, type 

module(...)

local cfg  = require(_PACKAGE .. 'cfg')
local util = require(_PACKAGE .. 'util')

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
  return lua('log', dt { message = string.format(...) })
end

__doc.dt = [[function(table) returns table
log.dt(t) adds 'date' and 'time' fields to table t
using os.date() and os.time(), then returns t.  
Existing 'date' and 'time' fields are undisturbed.
]]

function dt(t)
  t.date = t.date or os.date()
  t.time = t.time or os.time()
  return t
end

