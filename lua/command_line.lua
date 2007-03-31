local function eprintf(...) return io.stderr:write(string.format(...)) end

local ipairs, tostring, io, os, table, string, _G, require
    = ipairs, tostring, io, os, table, string, _G, require
      

module(...)

local util = require (_PACKAGE .. 'util')
local lists = require (_PACKAGE .. 'lists')
local commands = require (_PACKAGE .. 'commands')

local usage_lines = { }

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

----------------------------------------------------------------
--- List commands.

local list_responses =
  { add = { [true] = '%s was already in %s\n', [false] = '%s added to %s\n' },
    del = { [true] = '%s deleted from %s\n', [false] = '%s was not in %s\n' },
  }

local what = { add = 'String', ['add-pat'] = 'Pattern',
               del = 'String', ['del-pat'] = 'Pattern', }
  
local function listfun(listname)
  return function(cmd, tag, arg)
           local result = lists.run(listname, cmd, tag, arg)
           if not lists.is_show(cmd) then
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
  table.insert(usage_lines, l .. ' show-add')
  table.insert(usage_lines, l .. ' show-del')
end

----------------------------------------------------------------
--- Learning commands.

-- @param msgspec is either a sfid, or a filename, or missing, 
-- which indicates a message on standard input.  If a filename or stdin,
-- the sfid is extracted from the message field in the usual fashion.
-- @param classification is 'spam' or 'ham' or the equivalent 'nonspam', 



local cltx = { nonspam = 'ham' }
function learner(cmd)
  return function(msgspec, classification)
           if not classification then
             classification = msgspec
             msgspec = nil
           end
           classification = cltx[classfication] or classification
           if msgspec == nil then
             msgspec = io.stdin:read '*a'
           end
           local sfid = msg.sfid(msgspec)
           local comment, class, orig, new = cmd(sfid, classification)
           if not comment then
             io.stderr:write(class, '\n')
             io.exit(1)
           else
             io.stdout:write(comment, '\n')
           end
         end
end

learn = learner(commands.learn)
unlearn = learner(commands.unlearn)

function sfid(msgspec)
  local sfid = msg.sfid(msgspec)
  if sfid then
    io.stdout:write('SFID of message ', msgspec, ' is ', sfid, '\n')
  else
    io.stderr:write("Can't find a SFID\n")
    os.exit(1)
  end
end
