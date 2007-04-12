local function eprintf(...) return io.stderr:write(string.format(...)) end

local pairs, ipairs, tostring, io, os, table, string, _G, require, select
    = pairs, ipairs, tostring, io, os, table, string, _G, require, select

local unpack, type, print, assert, tonumber
    = unpack, type, print, assert, tonumber
      

module(...)

local util = require (_PACKAGE .. 'util')
local lists = require (_PACKAGE .. 'lists')
local commands = require (_PACKAGE .. 'commands')
local msg = require (_PACKAGE .. 'msg')
local cache = require (_PACKAGE .. 'cache')
require(_PACKAGE .. 'learn') -- loaded into 'commands'

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
    

function usage(...)
  if select('#', ...) > 0 then
    io.stderr:write(...)
    io.stderr:write '\n'
  end
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
           if not lists.show_cmd[cmd] then
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
  for cmd in pairs(lists.show_cmd) do
    table.insert(usage_lines, l .. ' ' .. cmd)
  end
end

----------------------------------------------------------------
--- Learning commands.

-- @param msgspec is either a sfid, or a filename, or missing, 
-- which indicates a message on standard input.  If a filename or stdin,
-- the sfid is extracted from the message field in the l fashion.
-- @param classification is 'spam' or 'ham' or the equivalent 'nonspam', 



--- Iterator to generate multiple msg specs from command line,
--- or stdin if no specs are given.
local function msgspecs(...) --- maybe should be in util?
  local msgs = { ... }
  local stdin = false
  if #msgs == 0 then
    msgs[1] = io.stdin:read '*a'
    stdin = true
  end
  local i = 0
  return function()
           i = i + 1;
           if msgs[i] then
             local what = stdin and 'standard input' or 'message ' .. msgs[i]
             return msgs[i], what
           end
         end
end

local cltx = { nonspam = 'ham' }
function learner(cmd)
  return function(classification, ...)
           classification = cltx[classfication] or classification
           for msgspec in msgspecs(...) do
             local sfid = util.validate(msg.sfid(msgspec))
             io.stdout:write(util.validate(cmd(sfid, classification)), '\n')
           end
         end
end

learn   = learner(commands.learn)
unlearn = learner(commands.unlearn)

for _, l in ipairs { 'learn', 'unlearn' } do
  table.insert(usage_lines, l .. ' <spam|nonspam> [<sfid|filename> ...]')
end

function sfid(...)
  for msgspec, what in msgspecs(...) do
    local sfid = util.validate(msg.sfid(msgspec))
    io.stdout:write('SFID of ', what, ' is ', sfid, '\n')
  end
end

table.insert(usage_lines, 'sfid [<sfid|filename> ...]')

function classify(...)
  local options, argv =
    util.validate(util.getopt({...},
      {tag = util.options.bool, cache = util.options.bool}))
  local show =
    options.tag 
      and
    function(pR, tag) return tag end
      or
    function(pR, tag)
      local what = assert(commands.sfid_tags[tag])
      if pR then
        what = what .. string.format(' with score %03.1f', pR)
      end
      return what
    end 
  
  for msgspec, what in msgspecs(unpack(argv)) do
    local m = util.validate(msg.of_any(msgspec))
    local pR, tag = commands.classify(m)
    if options.cache then
      cache.store(cache.generate_sfid(tag, pR), msg.to_orig_string(m))
    end
    io.stdout:write(what, ' is ', show(pR, tag), '\n')
  end
end

table.insert(usage_lines, 'classify [-tag] [<sfid|filename> ...]')


--- Initialize OSBF-Lua's state in the filesystem.
-- A truly nice touch here would be to offer a -procmail option
-- that would add the recommended lines to the .procmailrc.
-- Not sure if the service is worth the extra complexity at this time.

function init(buckets, ...)
  local nb = tonumber(buckets)
  if buckets and not nb then
    usage('Number of buckets ', buckets, ' is not a number')
  elseif select('#', ...) > 0 then
    usage()
  else
    io.stdout:write('Creating directories and databases')
    if nb then io.stdout:write(' with ', nb, ' buckets') end
    io.stdout:write('... ')
    io.stdout:flush()
    commands.init(nb)
    io.stdout:write('done!\n')
    io.stdout:flush()
  end
end

table.insert(usage_lines, 'init [<number of buckets>]')
