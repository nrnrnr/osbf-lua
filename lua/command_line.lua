local pairs, ipairs, tostring, io, os, table, string, _G, require, select, math
    = pairs, ipairs, tostring, io, os, table, string, _G, require, select, math

local unpack, type, print, assert, tonumber, pcall
    = unpack, type, print, assert, tonumber, pcall
      

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

local function eprintf(...) return util.write_error(string.format(...)) end

__doc = __doc or { }

local usage_lines = { }

__doc.run = [[function(cmd, ...)
Runs command cmd calling it with arguments received.
]] 

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

local function help_string(pattern)
  pattern = pattern or ''
  local output = {}
  local prog = string.gsub(_G.arg[0], '.*' .. cfg.slash, '')
  local prefix = 'Usage: '
  for _, u in ipairs(usage_lines) do
    if string.find(u, '^' .. pattern) then
      table.insert(output, table.concat{prefix, prog, ' [options] ', u})
    end
    prefix = string.gsub(prefix, '.', ' ')
  end
  prefix = 'Options: '
  for _, u in ipairs(table.sorted_keys(options.usage)) do
    table.insert(output, table.concat{prefix, '--', u, options.usage[u]})
    prefix = string.gsub(prefix, '.', ' ')
  end
  table.insert(output, '')
  return table.concat(output, '\n')
end

local function filter_help()
  util.write([[

Valid subject-line commands:

- train_form <password>
  Sends a training form.

- help <password>
  Sends this help.

- learn <password> ham|spam [<sfid>]
  Trains message. If <sfid> is not given, it's extracted
  from the header.

- unlearn <password> [ham|spam] [<sfid>]
  Undoes a previous learning.

- whitelist <password> add|del <tag> <string>
  Adds/deletes strings to/from whitelist. <tag> is a header
  name like From or Subject.  <string> is the string to
  match the whole <tag> contents.

- blacklist <password> add|del <tag> <string>
  Idem for blacklists.

- whitelist <password> add-pat|del-pat <tag> <pattern>
  Adds/deletes patterns to/from whitelist. <pattern> is a
  Lua pattern [1] to match some part of the <tag> contents.

- blacklist <password> add-pat|del-pat <tag> <pattern>
  Idem for blacklists.

- whitelist|blacklist <password> show
  Shows list contents.

- resend <password> <sfid>
  Resends message with <sfid>

[1] http://www.lua.org/manual/5.1/manual.html#5.4.1

]])
end

__doc.help = [[function(pattern)
Prints command syntax of commands which contain pattern to stdout and exits.
If pattern is nil prints syntax of all commands.
]] 

function help(pattern)
  if util.is_output_set_to_message() then
    filter_help()
  else
    util.write(help_string(pattern))
  end
end

table.insert(usage_lines, 'help')

__doc.usage = [[function(usage)
Prints command syntax to stderr and exits with error code 1.
]] 

function usage(msg, pattern)
  if msg then
    util.writeln_error(msg)
  end
  help(pattern)
  util.exit(1)
end

----------------------------------------------------------------
--- List commands.

local list_responses =
  { add = { [true] = '%s was already in %s\n', [false] = '%s added to %s\n' },
    del = { [true] = '%s deleted from %s\n', [false] = '%s was not in %s\n' },
  }

local what = { add = 'String', ['add-pat'] = 'Pattern',
               del = 'String', ['del-pat'] = 'Pattern', }
  
__doc.listfun = [[function(listname)
Factory to create a closure to perform operations on listname.
The returned function requires 3 arguments:
 cmd - the operation to be performed;
 tag - the header field name;
 arg - sfid or string with contents of the header field to match.
       If sfid, the contents of tag 'tag' of message associated
       with sfid will be used instead.
]]

local function listfun(listname)
  return function(cmd, tag, arg)
           -- if arg is SFID, replace it with its tag contents
           if cache.is_sfid(arg) then
              local message, err = cache.recover(arg)
              if message then
                local header_field = msg.header_tagged(message, tag)
                if header_field then
                  arg = header_field
                else
                  util.writeln('header ',
                    util.capitalize(tostring(tag)), ' not found in SFID.')
                  return
                end
              else
                util.writeln(err)
                return
              end
           end

           local result = lists.run(listname, cmd, tag, arg)
           if not lists.show_cmd[cmd] then
             if not (cmd and tag and arg) then
               eprintf('Bad %s commmand\n', listname)
               usage()
             end
             tag = util.capitalize(tag)
             local thing = string.format('%s %q for header %s:', what[cmd],
               arg, tag)
             local response =
               list_responses[string.gsub(cmd, '%-.*', '')][result == true]
             util.write(string.format(response, thing, listname))
           end
         end
end

__doc.blacklist = 'Closure to perform operations on the blacklist.\n'

blacklist = listfun 'blacklist'

__doc.whitelist = 'Closure to perform operations on the whitelist.\n'

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



__doc.msgspecs = [[function(...)
Iterator to generate multiple msg specs from command line,
or stdin if no specs are given.
]]

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

__doc.learner = [[function(cmd)
Factory to generate closures for learning messages as belonging
to the specified class. The first argument of the closure is the
class and the remaining are message specs.
]]

function learner(cmd)
  return function(classification, ...)
           local has_class =
             classification == 'ham' or classification == 'spam'
           if not has_class and cmd == commands.learn then
             usage('learn command requires a class, either "spam" or "ham".')
           end
           for msgspec in
             has_class and msgspecs(...) or msgspecs(classification, ... ) do
             local sfid = util.validate(msg.sfid(msgspec))
             local r, err, old_pR, new_pR = util.validate(cmd(sfid,
               has_class and classification or nil))
             if r then
               util.writeln(r)
               -- redelivers message if it was trained as ham, received any
               -- subject tag and it was a subject command 
               -- (is_output_set_to_message())
               local learned_as_ham =
                 cmd == commands.learn and classification == 'ham'
               local tagged_subject =
                 cfg.tag_subject and cache.sfid_score(sfid) < cfg.threshold
               if learned_as_ham and tagged_subject
               and util.is_output_set_to_message() then
                 local m = msg.of_sfid(sfid)
                 local subj_cmd = 'resend ' .. cfg.pwd .. ' ' .. sfid
                 r, err = msg.send_cmd_message(subj_cmd, m.eol)
                 if r then
                   util.writeln(' The original message, without subject tags, ',
                     'will be sent to you.')
                 else
                   util.writeln(' Error: unable to resend original message.')
                   util.log(err)
                 end
               end
             else
               util.writeln(err or 'Error learning as ' ..
                 tostring(classification))
             end
           end
         end
end

__doc.learn = 'Closure to learn messages as belonging to the specified class.\n'
learn   = learner(commands.learn)
__doc.unlearn = 'Closure to unlearn messages as belonging to the specified class.\n'
unlearn = learner(commands.unlearn)

table.insert(usage_lines, 'learn    <spam|ham>  [<sfid|filename> ...]')
table.insert(usage_lines, 'unlearn [<spam|ham>] [<sfid|filename> ...]')


__doc.sfid = [[function(...)
Searches SFID and prints to stdout for each message spec  
]]

function sfid(...)
  for msgspec, what in msgspecs(...) do
    local sfid = util.validate(msg.sfid(msgspec))
    util.writeln('SFID of ', what, ' is ', sfid)
  end
end

table.insert(usage_lines, 'sfid [<sfid|filename> ...]')

__doc.resend = [[function(sfid)
Recovers message with sfid from cache and writes its contents to stdout.
If it's a subject-command message, it replaces its contents.
Used by filter command to resend ham messages after a training, if the
original message received a subject tag.
]]


function resend(sfid)
  local message, err = cache.recover(sfid)
  if message then
    local m = msg.of_string(message)
    local pR, sfid_tag, subj_tag = commands.classify(m)
    if pR then
      sfid_tag = 'R' .. sfid_tag -- prefix tag to indicate a resent message
      local score_header = string.format(
        '%.2f/%.2f [%s] (v%s, Spamfilter v%s)',
        pR, cfg.min_pR_success, sfid_tag, core._VERSION, cfg.version)
      local score_header_name = cfg.score_header_name or 'X-OSBF-Lua-Score'
      msg.add_header(m, score_header_name, score_header)
      msg.insert_sfid(m, sfid, cfg.insert_sfid_in)
      util.unset_output_to_message()
      io.stdout:write(msg.to_string(m))
      util.log('resend\n', msg.to_string(m))
    else
      util.writeln(tostring(sfid_tag))
    end
  else
    util.writeln(err)
  end
end

table.insert(usage_lines, 'resend <sfid>')

__doc.recover = [[function(sfid)
Recovers message with sfid from cache and writes it to stdout.
If it is a subject-line command, the message is sent as an
atachment to the command-result message.
]]

function recover(sfid)
  local msg, err = cache.recover(sfid)
  if msg then
    util.write_message(msg)
  else
    util.write(err)
  end
end

table.insert(usage_lines, 'recover <sfid>')

__doc.remove = [[function(sfid) Removes sfid from cache.]]

function remove(sfid)
  local r, err = cache.remove(sfid)
  r = r and 'SFID removed.' or err
  util.writeln(r)
end

table.insert(usage_lines, 'remove <sfid>')

__doc.classify = [[function(...)
Reads a message from a file, sfid or stdin, classifies it
and prints the classification to stdout.
Valid option: -cache => caches the original message
]]

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
    util.write(what, ' is ', show(pR, tag), m.eol)
  end
end

table.insert(usage_lines, 'classify [-tag] [-cache] [<sfid|filename> ...]')

__doc.do_nothing = [[function(sfid) just prints the message "Nothing done.".]]

function do_nothing(sfid)
  util.writeln('Nothing done.')
end

-- checks and maps batch-commands to valid string commands
local valid_batch_cmds = {
  ham = {'learn', 'ham'},
  none = {'do_nothing'},
  recover = {'recover'},
  resend = {'resend'},
  remove = {'remove'},
  spam = {'learn', 'spam'},
  undo = {'unlearn'},
  whitelist_from = {'whitelist', 'add', 'from'},
  whitelist_subject = {'whitelist', 'add', 'subject'},
} 
 
local function run_batch_cmd(sfid, cmd, m)
  local args = {}
  if type(valid_batch_cmds[cmd]) == 'table' then
    local args = {unpack(valid_batch_cmds[cmd])}
    table.insert(args, sfid)
    util.write(tostring(sfid), ': ')
    if cmd == 'recover' or cmd == 'resend' then
      -- send a separate mail with subject-line command
      local r, err = msg.send_cmd_message(cmd .. ' ' .. cfg.pwd .. ' ' .. sfid,
        m.eol)
      if r then 
        util.writeln('The ', cmd, ' command was issued.')
        util.writeln( ' The message will be re-delivered to you if still in cache.')
      else
        util.writeln('Error: could not send the ', cmd, ' command.')
        util.log(err)
      end
    else
      run(unpack(args))
    end
  else
    util.writeln('Unknown batch command: ', tostring(cmd))
  end
end

__doc.batch_train = [[function(m)
Extracts commands from the body of m, a message in our internal format,
and executes them.  The commands must be in the format:
<sfid>=<command>
<sfid>=<command>
...

Valid commands are: 
ham               => train <sfid> as ham;
spam              => traim <sfid> as spam;
undo              => undo previous training on sfid;
whitelist_from    => add From: line of <sfid> to whitelist;
whitelist_subject => add Subject: line of <sfid> to whitelist;
recover           => recover message associated with <sfid> from
                     cache and send it attached;
resend            => recover message associated with <sfid> from
                     cache and re-delivers it;
remove            => remove <sfid> from cache.
]]

local function batch_train(m)
  local m = util.validate(msg.of_any(m))
  for sfid, cmd in string.gmatch(m.body, '(sfid.-)=(%S+)') do
    run_batch_cmd(sfid, cmd, m)
  end
end


-- valid subject-line commands for filter command.
-- commands with value 1 require sfid. 
local subject_line_commands = { classify = 1, learn = 1, unlearn = 1,
  recover = 1, resend = 1, remove = 1, sfid = 1, help = 0, whitelist = 0,
  blacklist = 0, stats = 0, ['cache-report'] = 0, train_form = 0,
  batch_train = 0, help = 0}

local function exec_subject_line_command(cmd, m)
  assert(type(cmd) == 'table' and type(m) == 'table')
  msg.set_output_to_message(m,
    'OSBF-Lua command result - ' .. cmd[1] or 'nil?!')
  -- insert sfid if required
  if subject_line_commands[cmd[1]] == 1 and not cache.is_sfid(cmd[#cmd]) then
    local sfid, err = msg.sfid(m)
      if sfid then
        table.insert(cmd, sfid)
      else
        util.writeln(err)
        return
      end
  end

  if cmd[1] == 'batch_train' then
    batch_train(m)
    return -- prevents execution of 'run' below
  elseif cmd[1] == 'train_form' or cmd[1] == 'cache-report' then
     cmd = {'cache-report', '-send', msg.header_tagged(m, 'to')}
  end
  run(unpack(cmd))
end

__doc.filter = [[function(...)
Reads a message from a file, sfid or stdin, searches for a command
in the subject line and either executes the command, if found, or
classifies and prints the classified message to stdout.
Valid options: -notag   => disables subject tagging
               -nocache => disables caching
               -nosfid  => disables sfid (implies -nocache)
]]

function filter(...)
  local options, argv =
    util.validate(options.parse({...},
      {nocache = options.std.bool, notag = options.std.bool,
       nosfid = options.std.bool}))

  for msgspec, what in msgspecs(unpack(argv)) do
    local m, err = util.validate(msg.of_any(msgspec))
    local cmd = msg.parse_subject_command(m)
    if type(cmd) == 'table' and subject_line_commands[cmd[1]] then
      exec_subject_line_command(cmd, m)
    else
      local pR, sfid_tag, subj_tag = commands.classify(m)
      if pR == nil then
      end
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
        pR or 0, cfg.min_pR_success, sfid_tag, core._VERSION, cfg.version)
      local score_header_name = cfg.score_header_name or 'X-OSBF-Lua-Score'
      msg.add_header(m, score_header_name, score_header)
      io.stdout:write(msg.to_string(m))
    end
  end
end

table.insert(usage_lines,
  'filter [-nosfid] [-nocache] [-notag] [<sfid|filename> ...]')
 
__doc.stats = [[function(...)
Writes classification and database statistics to stdout.
Valid options: -v, --verbose => adds more database statistics.
]]

do
  local opts = {verbose = options.std.bool, v = options.std.bool}
  local function table_len(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
  end
  
  function stats(...)
    local opts = util.validate(options.parse({...}, opts))
    if table_len(opts) ~= select('#', ...) then
      usage()
    end
    commands.write_stats(opts.verbose or opts.v)
  end
end
 
table.insert(usage_lines, 'stats [-v|-verbose]')


local valid_locale = { pt_BR = true, en_US = true }

__doc.init = [[function(email, dbsize)
Initialize OSBF-Lua's state in the filesystem.
email is the address for subject-line commands.
dbsize is optional. It is the total size of the databases.
Accepts option -lang to set report_locale in config.
]]

function init(...)
  local opts = {lang = options.std.val}
  local opts, args = util.validate(options.parse({...}, opts))
  if #args > 2 then usage() end
  local email, dbsize = args[1], args[2]
  if opts.lang and not valid_locale[opts.lang] then
    util.die('The locale informed is not valid: ', tostring(opts.lang))
  end
  if not (type(email) == 'string' and string.find(email, '@')) then
    usage('Init requires a valid email for subject-line commands.')
  end
  local nb = dbsize and util.validate(util.bytes_of_human(dbsize))
  if not core.isdir(cfg.dirs.user) then
    util.die('You must create the user directory before initializing it:\n',
      '  mkdir ', cfg.dirs.user)
  end
  nb = commands.init(email, nb, opts.lang)
  util.writeln('Created directories and databases using a total of ',
    util.human_of_bytes(nb))
end

table.insert(usage_lines, 'init [-lang=<locale>] <user-email> [<database size in bytes>]')

__doc.resize = [[function (class, newsize)
Changes the size of a class database.
class is either 'ham' or 'spam'.
newsize is the new size in bytes.
If the new size is lesser than the original size, contents are
pruned, less significative buckets first, to fit the new size.
XXX if resized back to 1.1M we get 95778 buckets, not 94321.
]]

function resize(class, newsize, ...)
  local nb = newsize and util.validate(util.bytes_of_human(newsize))
  if select('#', ...) > 0
  or type(class) ~= 'string' then
    usage()
  else
    local ham_index = cfg.dbset.ham_index
    local spam_index = cfg.dbset.spam_index
    local dbname =
      class == 'ham' and cfg.dbset.classes[ham_index]
        or
      class == 'spam' and cfg.dbset.classes[spam_index]
        or
      util.die('Unknown class to resize: "', class,
        '". Valid classes are "ham" or spam"')

    local stats = util.validate(core.stats(dbname))
    local tmpname = util.validate(os.tmpname())
    -- XXX non atomic...
    os.remove(tmpname) -- core.create_db doesn't overwite files (add flag to force?)
    local real_bytes = commands.create_single_db(tmpname, nb)
    util.validate(core.import(tmpname, dbname))
    util.validate(os.rename(tmpname, dbname))
    class = util.capitalize(class)
    util.writeln(class, ' database resized to ',
      util.human_of_bytes(real_bytes))
  end
end

table.insert(usage_lines, 'resize <spam|ham> <new database size in bytes>' )

__doc.internals = [[functions(s, ...)
Shows docs.
]]

function internals(s, ...)
  if select('#', ...) > 0 then
    usage()
  else
    local i = require(_PACKAGE .. 'internals')
    require(_PACKAGE .. 'core_doc')
    i(io.stdout, s)
  end
end

table.insert(usage_lines, 'internals [<module>|<module>.<function>]')

----------------------------------------------------------------

__doc['cache-report'] = [[function(email, temail)
Writes cache-report email message on standard output.
Valid options: -lang => specifies the language of the report.
If -lang is not specified, user's config locale is used. If not
specified in user's config, the server's locale is used.
If the informed locale is not known, posix is used.]]

do
  local opts = {lang = options.std.val, send = options.std.bool}
  _M['cache-report'] =
    function(...)
      local opts, args = util.validate(options.parse({...}, opts))
      local email, temail = args[1], args[2]
      email = email or cfg.command_address
      --if not email or args[3] then usage() end
      if opts.send then
        msg.send_message(
          commands.generate_training_message(email, temail, opts.lang))
        util.writeln('Training form sent.')
      else
        commands.write_training_message(email, temail, opts.lang)
      end
    end
end
table.insert(usage_lines, 'cache-report [-lang=<locale>] <user-email> [<training-email>]')

-----------------------------------------------------------------

__doc.homepage = [[function() Shows the project's home page.]]

function homepage()
  util.writeln(cfg.homepage)
end
table.insert(usage_lines, 'homepage')

