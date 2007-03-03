require 'osbf'
require 'osbf.lists'

local util, lists = osbf.util, osbf.lists
local function eprintf(...) return io.stderr:write(string.format(...)) end

local ipairs, tostring, io, os, table, string, _G
    = ipairs, tostring, io, os, table, string, _G
      

module(...)

local usage_lines = { }

local list_responses =
  { add = { [true] = '%s was already in %s\n', [false] = '%s added to %s\n' },
    del = { [true] = '%s deleted from %s\n', [false] = '%s was not in %s\n' },
  }

local what = { add = 'String', ['add-pat'] = 'Pattern',
               del = 'String', ['del-pat'] = 'Pattern', }
  
local function listfun(listname)
  return function(cmd, tag, arg)
           local result = lists.run(listname, cmd, tag, arg)
           if cmd ~= 'show' then
             if not (cmd and tag and arg) then
               eprintf('Bad %s commmand\n', listname)
               usage()
             end
             tag = util.capitalize(tag)
             local thing = string.format('%s %q for header %s:', what[cmd], arg, tag)
             local response =
               list_responses[string.gsub(cmd, '%-.*', '')][result == true]
             io.stdout:write(string.format(response, thing, listname))
           end
         end
end
               
blacklist = listfun 'blacklist'
whitelist = listfun 'whitelist'

for _, l in ipairs { 'whitelist', 'blacklist' } do
  table.insert(usage_lines, l .. ' add[-pat] <tag> <string>')
  table.insert(usage_lines, l .. ' del[-pat] <tag> <string>')
  table.insert(usage_lines, l .. ' show')
end

function run(cmd, ...)
  if not cmd then
    usage()
  elseif _M[cmd] then
    _M[cmd](...)
  else
    eprintf('Unknown command %s\n', cmd)
    usage()
  end
end
    

function usage()
  local prog = string.gsub(_G.arg[0], '.*/', '')
  local prefix = 'Usage: '
  for _, u in ipairs(usage_lines) do
    io.stderr:write(prefix, prog, ' ', u, '\n')
    prefix = string.gsub(prefix, '.', ' ')
  end
  os.exit(1)
end
