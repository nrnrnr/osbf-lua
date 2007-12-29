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
local log      = require (_PACKAGE .. 'log')
require(_PACKAGE .. 'learn') -- loaded into 'commands'

local function eprintf(...) return util.write_error(string.format(...)) end

__doc  = __doc  or { } -- internal documentation

__help = __help or { } -- the detailed help
    -- still to come: overview help

pcall = _G.pcall -- exposed!!
__doc.pcall = [[A version of pcall that is overridden by the -trace option.]]

local usage_lines = { }

__doc.run = [[function(cmd, ...)
Runs command cmd calling it with arguments received.
Catches all errors and prints message to stderr.
]] 

function run(cmd, ...)
  if not cmd then
    usage()
  elseif _M[cmd] then
    local ok, msg = pcall (_M[cmd], ...)
    if not ok then
      msg = string.gsub(msg, '^.-%:%s+', '')
      util.die((string.gsub(msg or 'unknown error calling command ' .. cmd, '\n*$', '')))
    end
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

__help.help = [[
$prog help    

  Gives overview of commands on command line

$prog help <command>

  Gives detailed help about particular command
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
              local message, err = cache.try_recover(arg)
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

local listhelp = [[
The $list is a list of key-value pairs... XXX FINISH ME

$prog $list add <tag> <string>

  Ensures that any message with a header of <tag> and a value of
  string will be on the $list.

$prog $list add-pat <tag> <string>

  Ensures that any message with a header of <tag> and a value of
  string will be on the $list. I THINK NOT!!!

$prog $list del <tag> <string>

  Ensures that any message with a header of <tag> and a value of
  string will be on the $list.

$prog $list del-pat <tag> <string>

  Ensures that any message with a header of <tag> and a value of
  string will be on the $list. I THINK NOT!!!

$prog $list show

$prog $list show-add

  Give a list of add commands that could be used to reconstruct the $list
  starting from an empty $list.

$prog $list show-del

  Give a list of del commands that could be used to remove all the 
  key-value pairs from the $list.
]]


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



__doc.msgs = [[function(...)
Iterator to generate multiple messages from command line,
or from stdin if no specs are given.  Each iteration returns
two values: a message, and a string saying what specified the
message.
]]

local function msgs(...) --- maybe should be in util?
  local n =  select('#', ...) 
  -- we can't combine these two cases because for reliability,
  -- reading from standard input should not call msg.of_any,
  -- which could fail on something that doesn't look like an
  -- RFC 822 message
  if n == 0 then
    local sent = false
    return function ()
             if not sent then
               sent = true
               return msg.of_string(io.stdin:read '*a'), 'stdin'
             end
           end
  else
    local i = 0
    specs = { ... }
    return function()
             i = i + 1;
             if i <= n then
               return msg.of_any(specs[i]), specs[i]
             end
           end
  end
end

__doc.learn = [[function(class, ...)
Learn messages as belonging to the specified class. The ... are the
message specs.
]]

local function learner(command_name)
  local cmd = assert(commands[command_name])
  return function(classification, ...)
    local has_class = cfg.classes[classification]
    if cmd == commands.learn and not has_class then
      usage('learn command requires one of these classes: ' ..
            table.concat(cfg.classlist(), ', '))
    else
      for m in has_class and msgs(...) or msgs(classification, ... ) do
        local sfid, cfn_info, crc32
        if msg.has_sfid(m) then
          sfid = msg.sfid(m)
        elseif not (cfg.use_sfid and cfg.cache.use) then
          error('Cannot ' .. command_name .. ' messages because ' ..
                ' the configuration file is set\n  '..
                (cfg.use_sfid and 'not to save messages' or 'not to use sfids'))
        else
          local probs, conftag = commands.multiclassify(m.lim.msg)
          local train, conf, sfid_tag, subj_tag, class =
            commands.classify(m, probs, conf)
          local orig = msg.to_orig_string(m)
          crc32 = core.crc32(orig)
          cfn_info = { probs = probs, conf = conftab, train = train, class = class }
          sfid = cache.generate_sfid(sfid_tag, conf)
          cache.store(sfid, orig)
        end

        local comment = cmd(sfid, has_class and classification or nil)
        util.writeln(comment)
        log.lua_log(command_name,
                    { class = classification, sfid = sfid,
                      crc32 = crc32 or core.crc32(msg.to_org_string(m)),
                      classification = cfn_info })
        -- redelivers message if it was trained and config calls for a resend
        -- subject tag and it was a subject command 
        -- (is_output_set_to_message())
        local class_cfg = cfg.classes[classification]
        local tagged_and_to_be_resent =
          cfg.tag_subject and
          cmd == commands.learn and class_cfg.resend ~= false and
          cache.table_of_sfid(sfid).confidence <= class_cfg.train_below
        if tagged_and_to_be_resent and util.is_output_set_to_message() then
          local m = msg.of_sfid(sfid)
          local subj_cmd = 'resend ' .. cfg.pwd .. ' ' .. sfid
          local ok, err = pcall(msg.send_cmd_message, subj_cmd, m.eol)
          if ok then
            util.writeln(' The original message, without subject tags, ',
              'will be sent to you.')
          else
            util.writeln(' Error: unable to resend original message.')
            log.logf('Could resend message %s: %s', sfid, err)
          end
        end
      end
    end
  end
end

__doc.learn   = 'Closure to learn messages as belonging to the specified class.\n'
__doc.unlearn = 'Closure to unlearn messages as belonging to the specified class.\n'
learn   = learner 'learn'
unlearn = learner 'unlearn'

table.insert(usage_lines, 'learn    <spam|ham>  [<sfid|filename> ...]')
table.insert(usage_lines, 'unlearn [<spam|ham>] [<sfid|filename> ...]')

__doc.sfid = [[function(...)
Searches SFID and prints to stdout for each message spec  
]]

function sfid(...)
  for m, what in msgs(...) do
    local sfid = msg.extract_sfid(m)
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
  local message, err = cache.try_recover(sfid)
  if message then
    local m = msg.of_string(message)
    local train, confidence, sfid_tag, subj_tag, class = commands.classify(m)
    sfid_tag = 'R' .. sfid_tag -- prefix tag to indicate a resent message
    local boost = cfg.classes[class].conf_boost
    local score_header =
      string.format( '%.2f/%.2f [%s] (v%s, Spamfilter v%s)', confidence - boost,
                    -boost, sfid_tag, core._VERSION, cfg.version)
    msg.add_osbf_header(m, cfg.score_header_suffix, score_header)
    msg.insert_sfid(m, sfid, cfg.insert_sfid_in)
    util.unset_output_to_message()
    io.stdout:write(msg.to_string(m))
    log.lua('resend', { date = os.date(), msg = msg.to_string(m) })
      --- XXX do we have to log the whole message here, or can we just log the sfid?
      --- (trying to keep a constant among of logging per event)
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
  local msg, err = cache.try_recover(sfid)
  if msg then
    util.write_message(msg)
  else
    util.write(err)
  end
end

table.insert(usage_lines, 'recover <sfid>')

__doc.remove = [[function(sfid) Removes sfid from cache.]]

function remove(sfid)
  cache.remove(sfid)
  util.writeln('SFID removed.')
end

table.insert(usage_lines, 'remove <sfid>')

__doc.classify = [[function(...)
Reads a message from a file, sfid or stdin, classifies it
and prints the classification to stdout.
Valid option: -cache => caches the original message
]]

function classify(...)
  local options, argv =
    options.parse({...}, {tag = options.std.bool, cache = options.std.bool})
  local show =
    options.tag 
      and
    function(confidence, tag) return tag end
      or
    function(confidence, tag, class)
      local what = cache.sfid_tag_meaning[tag] or class
      if confidence then
        what = string.format('%s with confidence %4.2f, where 20 is high confidence',
                             what, confidence)
      else
        what = string.format('%s and confidence is %s and tag is %s?!',
                             what, tostring(confidence), tostring(tag))
      end
      return what
    end 
  
  for m, what in msgs(unpack(argv)) do
    local probs, conf = commands.multiclassify(m.lim.msg)
    local train, confidence, tag, _, class = commands.classify(m, probs, conf)
    local sfid
    if options.cache then
      sfid = cache.generate_sfid(tag, confidence)
      cache.store(sfid, msg.to_orig_string(m))
    end
    local crc32 = core.crc32(msg.to_orig_string(m))
    log.lua('classify', { date = os.date(), probs = probs, conf = conf,
                              class = class, sfid = sfid, crc32 = crc32,
                              train = train })
    util.write(what, ' is ', show(confidence, tag, class),
               train and ' [needs training]' or '', m.eol)
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
      local ok, err = pcall(msg.send_cmd_message, cmd .. ' ' .. cfg.pwd .. ' ' .. sfid,
                            m.eol)
      if ok then 
        util.writeln('The ', cmd, ' command was issued.')
        util.writeln( ' The message will be re-delivered to you if still in cache.')
      else
        util.writeln('Error: could not send the ', cmd, ' command.')
        log.logf('Could not send %s: %s', cmd, err)
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
  local m = msg.of_any(m)
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
    table.insert(cmd, msg.sfid(m))
  end

  if cmd[1] == 'batch_train' then
    return batch_train(m) -- prevents execution of 'run' below
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
    options.parse({...},
      {nocache = options.std.bool, notag = options.std.bool,
       nosfid = options.std.bool})

  local function filter_one(m)
    local have_subject_cmd, cmd = _G.pcall(msg.parse_subject_command, m)
    if have_subject_cmd then
      exec_subject_line_command(cmd, m)
    else
      local probs, conf = commands.multiclassify(m.lim.msg)
      local train, confidence, sfid_tag, subj_tag, class =
        commands.classify(m, probs, conf)
      local crc32 = core.crc32(msg.to_orig_string(m))
      local sfid
      if not options.nosfid and cfg.use_sfid then
        sfid = cache.generate_sfid(sfid_tag, confidence)
        if not options.nocache and cfg.cache.use then
          cache.store(sfid, msg.to_orig_string(m))
        end
        msg.insert_sfid(m, sfid, cfg.insert_sfid_in)
      end
      log.lua('filter', { date = os.date(), probs = probs, conf = conf,
                              class = class, sfid = sfid, crc32 = crc32,
                              train = train })
      if not options.notag and cfg.tag_subject then
        msg.tag_subject(m, subj_tag)
      end
      local classes = cfg.classes
      local summary_header =
        string.format('%.2f/%.2f [%s] (v%s, Spamfilter v%s)',
                      confidence, classes[class].train_below,
                      sfid_tag, core._VERSION, cfg.version)
      local suffixes = cfg.header_suffixes
      msg.add_osbf_header(m, suffixes.summary, summary_header)
      msg.add_osbf_header(m, suffixes.class, class)
      msg.add_osbf_header(m, suffixes.confidence, confidence or '0.0')
      msg.add_osbf_header(m, suffixes.needs_training, train and 'yes' or 'no')
      io.stdout:write(msg.to_string(m))
    end
  end

  if #argv == 0 then -- must *not* fail
    local s = io.stdin:read '*a'
    local ok, m = _G.pcall(msg.of_string, s)
    local ok2, err
      if ok then ok2, err = _G.pcall(filter_one, m) end -- cannot use 'and' here
    if ok then
      if not ok2 then
        msg.add_osbf_header(m, 'Error', err or 'unknown error')
        io.stdout:write(msg.to_string(m))
      end
    else
      io.stdout:write(s) -- never a loss on stdin
    end
  else
    for m in msgs(unpack(argv)) do
      filter_one(m)
    end
  end
end

cfg.after_loading_do(
  function()
    local suffixes = cfg.header_suffixes
    for _, s in ipairs { 'summary', 'class', 'confidence', 'needs_training' } do
      if not suffixes[s] then
        util.dief([[Incomplete config file: no field 'header_suffixes.%s']], s)
      end
    end
  end)

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
    local opts = options.parse({...}, opts)
    if table_len(opts) ~= select('#', ...) then
      usage()
    end
    commands.write_stats(opts.verbose or opts.v)
  end
end
 
table.insert(usage_lines, 'stats [-v|-verbose]')


local valid_locale = { pt_BR = true, en_US = true }

do
  local locales = {}
  for l in pairs(valid_locale) do table.insert(locales, l) end
  table.sort(locales)

  __doc.init = [[function(email, ...)
Initialize OSBF-Lua's state in the filesystem.
email is the address for subject-line commands.
Additional options include
  -lang         locale
and four options for setting the size of databases.
  -dbsize       size
  -totalsize    size
  -buckets      number
  -totalbuckets number
A 'size' may include a suffix such as KB, MB, or GB; 
a 'number' may not.

The system supports these locales: ]] .. table.concat(locales, ' ')

end -- local do for 'locales'

do
  local translate = { dbsize = 'bytes', totalsize = 'totalbytes' }

  function init(...)
    local v = options.std.val
    local opts = {lang = v, dbsize = v, totalsize = v, buckets = v, totalbuckets = v}
    local opts, args = options.parse({...}, opts)
    if #args ~= 1 then usage() end
    local email = args[1]
    if not (type(email) == 'string' and string.find(email, '@')) then
      usage('For subject-line commands, init requires a valid email in user@host form.')
    end
    if opts.lang and not valid_locale[opts.lang] then
      util.die('The locale informed is not valid: ', tostring(opts.lang))
    end
    if opts.dbsize and opts.totalsize then
      util.die 'Cannot specify both -dbsize and -totalsize at initialization'
    elseif opts.buckets and opts.totalbuckets then
      util.die 'Cannot specify both -buckets and -totalbuckets at initialization'
    end
    local bytes   = opts.dbsize  or opts.totalsize
    local buckets = opts.buckets or opts.totalbuckets
    if bytes and buckets then
      util.die 'Cannot specify both size and number of buckets'
    end
    buckets = buckets and
      util.insist(tonumber(buckets), 'You must use a number to specify buckets')
    bytes = bytes and util.bytes_of_human(bytes)
    local units
    if not (bytes or buckets) then
      buckets, units = 94321, 'buckets'
    end
    for u in pairs(opts) do if u ~= 'lang' then units = units or u; break end end

    if not core.isdir(cfg.dirs.user) then
      util.die('You must create the user directory before initializing it:\n',
        '  mkdir ', cfg.dirs.user)
    end
    nb = commands.init(email, buckets or bytes, translate[units] or units, opts.lang)
    util.writeln('Created directories and databases using a total of ', 
      util.human_of_bytes(nb))
  end

  table.insert(usage_lines, 'init [-dbsize <size> | -totalsize <size> | -buckets <number> | -totalbuckets <number>] [-lang=<locale>] <user-email>')
end


__doc.resize = [[function (class, newsize)
Changes the size of a class database.
newsize is the new size in bytes.
If the new size is lesser than the original size, contents are
pruned, less significative buckets first, to fit the new size.
XXX if resized back to 1.1M we get 95778 buckets, not 94321.
]]

function resize(class, newsize, ...)
  local nb = newsize and util.bytes_of_human(newsize)
  if select('#', ...) > 0 or type(class) ~= 'string' then
    usage()
  elseif not cfg.classes[class] then
    util.die('Unknown class to resize: "', class,
             '".\nValid classes are: ', table.concat(cfg.classlist(), ', '))
  else
    local dbname = cfg.classes[class].db
    local stats = core.stats(dbname)
    local tmpname = util.validate(os.tmpname())
    -- XXX non atomic...
    os.remove(tmpname) -- core.create_db doesn't overwite files (add flag to force?)
    local real_bytes = commands.create_single_db(tmpname, nb)
    core.import(tmpname, dbname)
    util.validate(os.rename(tmpname, dbname))
    class = util.capitalize(class)
    util.writeln(class, ' database resized to ', util.human_of_bytes(real_bytes))
  end
end

table.insert(usage_lines, 'resize <class> <new database size in buckets>' )

__doc.dump = [[function (class, csvfile)
Dumps class database to csv format.
csvfile is the the name of the csv file to be created or rewritten.
]]

function dump(class, csvfile, ...)
  if select('#', ...) > 0
  or type(class) ~= 'string'
  or type(csvfile) ~= 'string'
  then
    usage()
  elseif not cfg.classes[class] then
    util.die('Unknown class to dump: "', class,
             '".\nValid classes are: ', table.concat(cfg.classlist(), ', '))
  else
    local tmpname = util.validate(os.tmpname())
    local dbname = cfg.classes[class].db
    core.dump(dbname, tmpname)
    util.validate(os.rename(tmpname, csvfile))
    class = util.capitalize(class)
    util.writeln(class, ' database dumped to ', csvfile)
  end
end

table.insert(usage_lines, 'dump <class> <csvfile>' )

__doc.restore = [[function (class, csvfile)
Restores class database from csv file.
]]

function restore(class, csvfile, ...)
  if select('#', ...) > 0
  or type(class) ~= 'string'
  or type(csvfile) ~= 'string'
  then
    usage()
  elseif not cfg.classes[class] then
    util.die('Unknown class to restore: "', class,
             '".\nValid classes are: ', table.concat(cfg.classlist(), ', '))
  else
    local tmpname = util.validate(os.tmpname())
    local dbname = cfg.classes[class].db
    --os.remove(tmpname) -- core.create_db doesn't overwite files (add flag to force?)
    core.restore(tmpname, csvfile)
    util.validate(os.rename(tmpname, dbname))
    class = util.capitalize(class)
    util.writeln(class, ' database restored from ', csvfile)
  end
end

table.insert(usage_lines, 'restore <class> <csvfile>' )


__doc.internals = [[function(s, ...)
Shows docs.
]]

function internals(s, ...)
  if select('#', ...) > 0 then
    usage()
  else
    local i = require(_PACKAGE .. 'internals')
    require(_PACKAGE .. 'core_doc')
    require(_PACKAGE .. 'roc')
    i(io.stdout, s)
  end
end

table.insert(usage_lines, 'internals [<module>|<module>.<function>]')

----------------------------------------------------------------



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
      local opts, args = options.parse({...}, opts)
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


