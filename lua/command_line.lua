-- See Copyright Notice in osbf.lua

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
local filter   = require (_PACKAGE .. 'filter')
local output   = require (_PACKAGE .. 'output')
local sfid     = require (_PACKAGE .. 'sfid')
require(_PACKAGE .. 'learn')  -- loaded into 'commands'
require(_PACKAGE .. 'report') -- loaded into 'commands'

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
      msg = msg and msg:gsub('^.-%:%s+', '') or 'unknown error calling command ' .. cmd
      output.error:writeln((msg:gsub('\n+$', '')))
    end
  else
    output.error:writeln('Unknown command ', cmd)
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
    prefix = prefix:gsub('.', ' ')
  end
  prefix = 'Options: '
  for _, u in ipairs(table.sorted_keys(options.usage)) do
    table.insert(output, table.concat{prefix, '--', u, options.usage[u]})
    prefix = prefix:gsub('.', ' ')
  end
  table.insert(output, '')
  return table.concat(output, '\n')
end

local function filter_help()
  output.write([[

Valid subject-line commands:

- classify <password> [<sfid>] 
  Classifies a message. If <sfid> [1] is not given, it's extracted
  from the header.

- learn <password> ham|spam [<sfid>]
  Trains message. If <sfid> is not given, it's extracted
  from the header.

- unlearn <password> [ham|spam] [<sfid>]
  Undoes a previous learning.

- cache-report <password>
  Sends a training form.

- whitelist <password> add|del <tag> <string>
  Adds/deletes strings to/from whitelist. <tag> is a header
  name like From or Subject.  <string> is the string to
  match the whole <tag> contents.

- blacklist <password> add|del <tag> <string>
  Idem for blacklists.

- whitelist <password> add-pat|del-pat <tag> <pattern>
  Adds/deletes patterns to/from whitelist. <pattern> is a
  Lua pattern [2] to match some part of the <tag> contents.

- blacklist <password> add-pat|del-pat <tag> <pattern>
  Idem for blacklists.

- whitelist|blacklist <password> show
  Shows list contents.

- resend <password> <sfid>
  Resends message with <sfid>.

- recover <password> <sfid>
  Recovers a message with <sfid> as an attachment.

- remove <password> <sfid>
  Removes the message with <sfid> from cache.

- stats <password>
  Sends database and filter statistics.

- help <password>
  Sends this help.

[1] <sfid>, spamfilter id, identifies a message in filter's cache.
[2] http://www.lua.org/manual/5.1/manual.html#5.4.1

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
  if output.type() == 'message' then
    filter_help()
  else
    output.write(help_string(pattern))
  end
end

table.insert(usage_lines, 'help')

__doc.usage = [[function(usage)
Prints command syntax to stderr and exits with error code 1.
]] 

function usage(msg, pattern)
  if msg then
    output.error:writeln(msg)
  end
  help(pattern)
  output.exit(1)
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
              local message = cache.recover(arg)
              local header_field = message[tag]
              if header_field then
                arg = header_field
              else
                output.writeln('header ',
                             util.capitalize(tostring(tag)), ' not found in SFID.')
              end
           end

           local result = lists.run(listname, cmd, tag, arg)
           if not lists.show_cmd[cmd] then
             if not (cmd and tag and arg) then
               output.error:writeln('Bad ', listname, ' commmand')
               usage()
             end
             tag = util.capitalize(tag)
             local thing = string.format('%s %q for header %s:', what[cmd],
               arg, tag)
             local response =
               list_responses[cmd:gsub('%-.*', '')][result == true]
             output.write(string.format(response, thing, listname))
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
  -- reading from standard input should not call cache.msg_of_any,
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
               return cache.msg_of_any(specs[i]), specs[i]
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
      for m, sfid in has_class and msgs(...) or msgs(classification, ... ) do
        local cfn_info, crc32
        local added_to_cache = false
        if not cache.is_sfid(sfid) then
          if m:_has_sfid() then
            sfid = m:_sfid()
          elseif not (cfg.use_sfid and cfg.cache.use) then
            error('Cannot ' .. command_name .. ' messages because ' ..
                  ' the configuration file is set\n  '..
                  (cfg.use_sfid and 'not to save messages' or 'not to use sfids'))
          else
            local probs, conftab = commands.multiclassify(commands.extract_feature(m))
            --local train, conf, sfid_tag, subj_tag, class =
            local bc = commands.classify(m, probs, conftab)
            local orig = m:_to_orig_string()
            crc32 = core.crc32(orig)
            cfn_info = { probs = probs, conf = conftab, train = bc.train,
                         class = bc.class }
            sfid = cache.generate_sfid(bc.sfid_tag, bc.pR)
            cache.store(sfid, orig)
            added_to_cache = true
          end
        end

        local comment = cmd(sfid, has_class and classification or nil)
        output.writeln(comment)
        log.lua(command_name, log.dt
                    { class = classification, sfid = sfid,
                      synopsis = msg.synopsis(m),
                      crc32 = crc32 or core.crc32(msg.to_orig_string(m)),
                      classification = cfn_info,
                      added_to_cache = added_to_cache,  -- for debugging
                    })
        -- redelivers message if it was trained and config calls for a resend
        -- subject tag and it was a subject command 
        -- (is_output_set_to_message())
        local class_cfg = cfg.classes[classification]
        local tagged_and_to_be_resent =
          cfg.tag_subject and
          cmd == commands.learn and class_cfg.resend ~= false and
          cache.table_of_sfid(sfid).confidence <= class_cfg.train_below
        if tagged_and_to_be_resent and output.type() == 'message' then
          local m = msg.of_string(cache.recover(sfid))
          local subj_cmd = 'resend ' .. cfg.pwd .. ' ' .. sfid
          local ok, err = pcall(filter.send_cmd_message, subj_cmd, m.__eol)
          if ok then
            output.writeln(' The original message, without subject tags, ',
              'will be sent to you.')
          else
            output.writeln(' Error: unable to resend original message.')
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
    output.writeln('SFID of ', what, ' is ', m:_sfid())
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
  local message = cache.recover(sfid)
  local m = msg.of_string(message)
  local bc = commands.classify(m)
  local sfid_tag = 'R' .. bc.sfid_tag -- prefix tag to indicate a resent message
  local boost = cfg.classes[bc.class].conf_boost
  local score_header =
    string.format( '%.2f/%.2f [%s] (v%s, Spamfilter v%s)', bc.pR,
                  boost, sfid_tag, core._VERSION, cfg.version)
  filter.add_osbf_header(m, cfg.header_suffixes.summary, score_header)
  filter.insert_sfid(m, sfid, cfg.insert_sfid_in)
  --output.flush() -- just in case we were writing to a message, stop
                 -- XXX almost certainly broken
  io.stdout:write(msg.to_string(m))
  log.lua('resend', log.dt { msg = tostring(m) })
end

table.insert(usage_lines, 'resend <sfid>')

__doc.recover = [[function(sfid)
Recovers message with sfid from cache and writes it to stdout.
If it is a subject-line command, the message is sent as an
atachment to the command-result message.
]]

function recover(sfid)
  output.write_message(cache.recover(sfid))
end

table.insert(usage_lines, 'recover <sfid>')

__doc.remove = [[function(sfid) Removes sfid from cache.]]

function remove(sfid)
  cache.remove(sfid)
  output.writeln('SFID removed.')
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
    local probs, conf = commands.multiclassify(commands.extract_feature(m))
    local bc = commands.classify(m, probs, conf)
    local sfid
    if options.cache then
      sfid = cache.generate_sfid(tag, confidence)
      cache.store(sfid, msg.to_orig_string(m))
    end
    local crc32 = core.crc32(msg.to_orig_string(m))
    log.lua('classify', log.dt { probs = probs, conf = conf, train = bc.train,
                                 synopsis = msg.synopsis(m),
                                 class = bc.class, sfid = sfid, crc32 = crc32 })
    output.write(what, ' is ', show(bc.pR, bc.sfid_tag, bc.class),
               bc.train and ' [needs training]' or '', m.__eol)
  end
end

table.insert(usage_lines, 'classify [-tag] [-cache] [<sfid|filename> ...]')

__doc.do_nothing = [[function(sfid) just prints the message "Nothing done.".]]

function do_nothing(sfid)
  output.writeln('Nothing done.')
end

-- checks and maps batch-commands to valid string commands
local valid_batch_cmds = {
  none = {'do_nothing'},
  recover = {'recover'},
  resend = {'resend'},
  remove = {'remove'},
  undo = {'unlearn'},
  whitelist_from = {'whitelist', 'add', 'from'},
  whitelist_subject = {'whitelist', 'add', 'subject'},
} 

do
  local function make_classes_commands()
    for c in pairs(cfg.classes) do
      valid_batch_cmds[c] = valid_batch_cmds[c] or { 'learn', c }
    end
  end

  cfg.after_loading_do(make_classes_commands)
end

local function run_batch_cmd(sfid, cmd, m)
  if type(valid_batch_cmds[cmd]) == 'table' then
    local args = {unpack(valid_batch_cmds[cmd])} -- copies table
    table.insert(args, sfid)
    output.write(tostring(sfid), ': ')
    if cmd == 'recover' or cmd == 'resend' then
      -- send a separate mail with subject-line command
      local ok, err = pcall(filter.send_cmd_message, cmd .. ' ' .. cfg.pwd .. ' ' .. sfid,
                            m.__eol)
      if ok then 
        output.writeln('The ', cmd, ' command was issued.')
        output.writeln( ' The message will be re-delivered to you if still in cache.')
      else
        output.writeln('Error: could not send the ', cmd, ' command.')
        log.logf('Could not send %s: %s', cmd, err)
      end
    else
      run(unpack(args))
    end
  else
    output.writeln('Unknown batch command: ', tostring(cmd))
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
spam              => train <sfid> as spam;
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
  local m = cache.msg_of_any(m)
  for sfid, cmd in string.gmatch(m.__body, '(sfid.-)=(%S+)') do
    -- remove initial '3D' of commands in quoted-printable encoded messages
    cmd = cmd:gsub('^3[dD]', '')
    run_batch_cmd(sfid, cmd, m)
  end
end


-- valid subject-line commands for filter command.
-- commands with value 1 require the last arg to be a sfid.
local subject_line_commands = { classify = 1, learn = 1, unlearn = 1,
  recover = 1, resend = 1, remove = 1, whitelist = 0,
  blacklist = 0, stats = 0, ['cache-report'] = 0, train_form = 0,
  batch_train = 0, help = 0}

local function exec_subject_line_command(cmd, m)
  assert(type(cmd) == 'table' and type(m) == 'table')
  -- insert sfid if required
  if subject_line_commands[cmd[1]] == 1 and not cache.is_sfid(cmd[#cmd]) then
    table.insert(cmd, m:_sfid())
  end

  -- resend command replaces the result-command message completely
  if cmd[1] ~= 'resend' then
    output.set(m, 'OSBF-Lua command result - ' .. cmd[1] or 'nil?!')
  end
  if cmd[1] == 'batch_train' then
    return batch_train(m) -- prevents execution of 'run' below
  elseif cmd[1] == 'train_form' or cmd[1] == 'cache-report' then
    cmd = {'cache-report', '-send', m.to }
  end
  run(unpack(cmd))
  output.flush()
end

__doc.filter = [[function(...)
Reads a message from a file, sfid or stdin, searches for a command
in the subject line and either executes the command, if found, or
classifies and prints the classified message to stdout.
Valid options: -notag   => disables subject tagging
               -nocache => disables caching
               -nosfid  => disables sfid (implies -nocache)
]]

_M.filter = function(...)
  local options, argv =
    options.parse({...},
      {nocache = options.std.bool, notag = options.std.bool,
       nosfid = options.std.bool})

  local function filter_one(m)
    local have_subject_cmd, cmd = _G.pcall(filter.parse_subject_command, m)
    if have_subject_cmd then
      exec_subject_line_command(cmd, m)
    else
      local sfid = commands.filter(m, options)
      if sfid and not options.nocache and cfg.cache.use then
        cache.store(sfid, msg.to_orig_string(m))
      end
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
        filter.add_osbf_header(m, 'Error', err or 'unknown error')
        local maybe_class = err:match [[^Couldn't lock the file /.*/(.-)%.cfc%.$]]
        if maybe_class then -- salvage locking error on classification update
          local suffixes = cfg.header_suffixes
          filter.add_osbf_header(m, suffixes.class, maybe_class)
          filter.add_osbf_header(m, suffixes.confidence, '0.0')
          filter.add_osbf_header(m, suffixes.needs_training, 'yes')
        end
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
  -rightid      string
rightid is the rigth part of the spam filter id (sfid). if not specified,
the fully qualified host name is used.
And four options for setting the size of databases.
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
    local opts = {lang = v, dbsize = v, totalsize = v, buckets = v, totalbuckets = v, rightid = v}
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

    local rightid = opts.rightid or util.local_rightid()
    if not cache.valid_rightid(rightid) then
      util.die 'rightid must be a valid domain name'
    end
     
    nb = commands.init(email, buckets or bytes, translate[units] or units,
                       rightid, opts.lang)
    output.writeln('Created directories and databases using a total of ', 
      util.human_of_bytes(nb))
  end

  table.insert(usage_lines, 'init [-dbsize <size> | -totalsize <size> | -buckets <number> | -totalbuckets <number>] [-rightid=<domain-name>] [-lang=<locale>] <user-email>')
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
    local stats = core.stats(core.open_class(dbname))
    local tmpname = util.validate(os.tmpname())
    -- XXX non atomic...
    os.remove(tmpname) -- core.create_db doesn't overwite files (add flag to force?)
    local real_bytes = commands.create_single_db(tmpname, nb)
    core.import(tmpname, dbname)
    util.validate(os.rename(tmpname, dbname))
    class = util.capitalize(class)
    output.writeln(class, ' database resized to ', util.human_of_bytes(real_bytes))
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
    output.writeln(class, ' database dumped to ', csvfile)
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
    output.writeln(class, ' database restored from ', csvfile)
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
        filter.send_message(
          commands.generate_training_message(email, temail, opts.lang))
        output.writeln('Training form sent.')
      else
        commands.write_training_message(email, temail, opts.lang)
      end
    end
end
table.insert(usage_lines, 'cache-report [-lang=<locale>] <user-email> [<training-email>]')

-----------------------------------------------------------------

__doc.homepage = [[function() Shows the project's home page.]]

function homepage()
  output.writeln(cfg.homepage)
end
table.insert(usage_lines, 'homepage')


