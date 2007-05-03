local function eprintf(...) return io.stderr:write(string.format(...)) end

local pairs, ipairs, tostring, io, os, table, string, _G, require, select, math
    = pairs, ipairs, tostring, io, os, table, string, _G, require, select, math

local unpack, type, print, assert, tonumber
    = unpack, type, print, assert, tonumber
      

module(...)

local util     = require (_PACKAGE .. 'util')
local cfg      = require (_PACKAGE .. 'cfg')
local core     = require (_PACKAGE .. 'core')
local lists    = require (_PACKAGE .. 'lists')
local commands = require (_PACKAGE .. 'commands')
local msg      = require (_PACKAGE .. 'msg')
local cache    = require (_PACKAGE .. 'cache')
local options  = require (_PACKAGE .. 'options')
require(_PACKAGE .. 'learn') -- loaded into 'commands'

local usage_lines = { }

local output_to = io.stdout

function set_output(out)
  -- no checks yet
  output_to = out
end

-- outputs text to stdout, stderr or sent it to email address
-- text - string to output
-- subj - subject of email (optional)
function output(text, subj)
  assert(type(text) == 'string', 'string expected, got ' .. type(text))
  if output_to == io.stdout or output_to == io.stderr then
    output_to:write(text)
  elseif type(output_to) == 'string' then
    -- assumes output_to is a valid email address
    subj = subj or 'OSBF command results'
    msg.send(output_to, subj, text) 
  else
    error('Invalid destination to output to')
  end
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
    

function usage(...)
  if select('#', ...) > 0 then
    io.stderr:write(...)
    io.stderr:write '\n'
  end
  local prog = string.gsub(_G.arg[0], '.*' .. cfg.slash, '')
  local prefix = 'Usage: '
  for _, u in ipairs(usage_lines) do
    io.stderr:write(prefix, prog, ' [options] ', u, '\n')
    prefix = string.gsub(prefix, '.', ' ')
  end
  prefix = 'Options: '
  for _, u in ipairs(table.sorted_keys(options.usage)) do
    io.stderr:write(prefix, '--', u, options.usage[u], '\n')
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
-- the sfid is extracted from the message field in the usual fashion.
-- @param classification is 'spam' or 'ham'. 



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

function learner(cmd)
  return function(classification, ...)
           for msgspec in msgspecs(...) do
             local sfid = util.validate(msg.sfid(msgspec))
             io.stdout:write(util.validate(cmd(sfid, classification)), '\n')
           end
         end
end

learn   = learner(commands.learn)
unlearn = learner(commands.unlearn)

for _, l in ipairs { 'learn', 'unlearn' } do
  table.insert(usage_lines, l .. ' <spam|ham> [<sfid|filename> ...]')
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
    util.validate(options.parse({...},
      {tag = options.std.bool, cache = options.std.bool}))
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

table.insert(usage_lines, 'classify [-tag] [-cache] [<sfid|filename> ...]')

--- Filter messages
-- reads a message from a file, sfid or stdin and searchs for
-- a command in the subject and executes, if found, or classifies
-- and prints the message.
-- valid options: -notag   => disables subject tagging
--                -nocache => disables caching
--                -nosfid  => disables sfid (implies -nocache)
function filter(...)
  local options, argv =
    util.validate(options.parse({...},
      {nocache = options.std.bool, notag = options.std.bool,
       nosfid = options.std.bool}))

  for msgspec, what in msgspecs(unpack(argv)) do
    local m = util.validate(msg.of_any(msgspec))
    local subject_command = msg.find_subject_command(m)
    if subject_command then
      -- print cmd and args for testing
      for i, v in pairs(subject_command) do
        print(v)
      end
    else
      local pR, sfid_tag, subj_tag = commands.classify(m)
      if not options.nosfid and cfg.use_sfid then
        local sfid = cache.generate_sfid(sfid_tag, pR)
        if not options.nocache and cfg.save_for_training then
          cache.store(sfid, msg.to_orig_string(m))
        end
        msg.insert_sfid(m, sfid, cfg.insert_sfid_in)
      end
      if not options.notag and cfg.tag_subject then
        msg.tag_subject(m, subj_tag)
      end
      local score_header = string.format(
        '%.2f/%.2f [%s] (v%s, Spamfilter v%s)',
        pR, cfg.min_pR_success, sfid_tag, core._VERSION, cfg.version)
      msg.add_header(m, 'X-OSBF-Lua-Score', score_header)
      io.stdout:write(msg.to_string(m))
    end
  end
end

table.insert(usage_lines,
  'filter [-nosfid] [-nocache] [-notag] [<sfid|filename> ...]')
 

do
  local opts = {verbose = options.std.bool, v = options.std.bool}
  function stats(...)
    local opts = util.validate(options.parse({...}, opts))
    commands.write_stats(io.stdout, opts.verbose or opts.v)
  end
end
 
table.insert(usage_lines, 'stats [-v|-verbose]')

--- Initialize OSBF-Lua's state in the filesystem.
-- A truly nice touch here would be to offer a -procmail option
-- that would add the recommended lines to the .procmailrc.
-- Not sure if the service is worth the extra complexity at this time.

function init(dbsize, ...)
  local nb = dbsize and util.validate(util.bytes_of_human(dbsize))
  if select('#', ...) > 0 then
    usage()
  else
    if not core.is_dir(cfg.dirs.user) then
      util.die('You must create the user directory before initializing it:\n',
               '  mkdir ', cfg.dirs.user)
    end
    nb = commands.init(nb)
    io.stdout:write('Created directories and databases using a total of ',
                    util.human_of_bytes(nb), '\n')
  end
end

table.insert(usage_lines, 'init [<database size in bytes>]')


function internals(s, ...)
  if select('#', ...) > 0 then
    usage()
  else
    local i = require(_PACKAGE .. 'internals')
    i(io.stdout, s)
  end
end

table.insert(usage_lines, 'internals [<module>|<module>.<function>]')
