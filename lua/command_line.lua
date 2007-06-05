local function eprintf(...) return io.stderr:write(string.format(...)) end

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
    if string.find(u, pattern) then
      table.insert(output, table.concat{prefix, prog, ' [options] ', u})
    end
    prefix = string.gsub(prefix, '.', ' ')
  end
  prefix = 'Options: '
  for _, u in ipairs(table.sorted_keys(options.usage)) do
    table.insert(output, table.concat{prefix, '--', u, options.usage[u]})
    prefix = string.gsub(prefix, '.', ' ')
  end
  return table.concat(output, '\n')
end

__doc.help = [[function(pattern)
Prints command syntax of commands which contain pattern to stdout and exits.
If pattern is nil prints syntax of all commands.
]] 

function help(pattern)
  io.stdout:write(help_string(pattern))
  os.exit(0)
end

table.insert(usage_lines, 'help')

__doc.usage = [[function(usage)
Prints command syntax to stderr and exits with error code 1.
]] 

function usage(...)
  if select('#', ...) > 0 then
    io.stderr:write(...)
    io.stderr:write '\n'
  end
  io.stderr:write(help_string())
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
  
__doc.listfun = [[function(listname)
Factory to create a closure to perform operations on listname.
The returned function requires 3 arguments:
 cmd - the operation to be performed;
 tag - the header field name;
 arg - contents of the header field to match.
]]

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
             io.stdout:write(util.validate(cmd(sfid,
               has_class and classification or nil)), '\n')
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
    io.stdout:write('SFID of ', what, ' is ', sfid, '\n')
  end
end

table.insert(usage_lines, 'sfid [<sfid|filename> ...]')

__doc.recover = [[function(sfid, ...)
Recovers message with sfid from cache and prints it to stdout.
Valid option: -attach <mime_boundary>.
]]

function recover(...)
  local nargs = select('#', ...)
  assert(nargs > 0 and nargs < 3,
    'Wrong number of args to msg.recover: Got ' .. tostring(nargs))
  local options, argv =
    util.validate(options.parse({...}, {attach = options.std.bool}))
  assert(#argv == 1)
  local sfid = argv[1]
  -- recovered message should be attached?
  if options.attach then 
    io.stdout:write(msg.attach_message(sfid))
  else
    local msg, err = cache.recover(sfid)
    msg = msg or err
    io.stdout:write(msg, '\n')
  end
end

table.insert(usage_lines, 'recover <sfid>')

__doc.recover_attached = [[function(sfid)
Recovers message with sfid from cache and and prints it wrapped
with MIME boundaries to stdout.
]]

__doc.remove = [[function(sfid) Removes sfid from cache.]]

function remove(sfid)
  local msg, err = cache.remove(sfid)
  if msg == true then
    msg = sfid .. ': removed.'
  end
  msg = msg or err
  io.stdout:write(msg, '\n')
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
    io.stdout:write(what, ' is ', show(pR, tag), '\n')
  end
end

table.insert(usage_lines, 'classify [-tag] [-cache] [<sfid|filename> ...]')

local function whitelist_from(msgspec)
  io.stdout:write('whitelist from not implemented yet.\n')
end
  
local function whitelist_subject(msgspec)
  io.stdout:write('whitelist subject not implemented yet.\n')
end

__doc.train_headers = [[function(m, subject_command) returns a RFC-2822
string message with a command in the subject line. The necessary headers
are taken from m, a message in our internal format, and  the command is
taken from the string subject_command.]]

local function train_headers(m, subject_command)
  local headers = {}
  for i in msg.header_indices(m, 'from ', 'received', 'date',
    'from', 'to') do
    if i then
      table.insert(headers, m.headers[i])
    end
  end
  local msg_id = cache.generate_sfid('H', 0)
  --XXX generate message id: table.insert(headers, 'Message-ID: ' .. msg_id))
  table.insert(headers, 'Subject: ' .. subject_command)
  return table.concat(headers, m.eol) .. m.eol .. m.eol
end

local valid_batch_cmds = {
  spam = {'learn', 'spam'}, ham = {'learn', 'ham'}, undo = {'unlearn'},
  recover = {'recover'}, remove = {'remove'}, whitelist_from = whitelist_from,
  whitelist_subject = whitelist_subject, none = true } 
 
local function run_batch_cmd(sfid, cmd, m)
  local args = valid_batch_cmds[cmd]
  if args then
    if type(args) == 'table' then
      table.insert(args, sfid)
      if cmd == 'recover' then
        -- send a separate mail with subject-line command
        local train_msg = train_headers(m, 'recover ' .. cfg.pwd ..
          ' -attach ' ..  sfid)
        msg.send_message(train_msg)
        io.stdout.write(sfid, ': recover command was issued.\n')
      else
        run(unpack(args))
        if cmd == 'ham' and cache.sfid_score(sfid) < cfg.threshold then
          -- resend message with right classification
        end
      end
    elseif type(args) == 'function' then
      args(sfid)
    else
      -- do nothing
    end
  else
    io.stdout:write('Unknown batch command: ', cmd or 'nil', m.eol or '\n')
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
remove            => remove <sfid> from cache.
]]

local function batch_train(m)
  m = util.validate(msg.of_any(m))
  string.gsub(m.body, '(sfid.-)=(%S+)', function(sfid, cmd)
                                         run_batch_cmd(sfid, cmd, m)
                                       end)
end

-- valid subject-line commands for filter command.
-- commands with value 1 require sfid. 
local subject_line_commands = { classify = 1, learn = 1, unlearn = 1,
  recover = 1, remove = 1, sfid = 1, help = 0, whitelist = 0, blacklist = 0,
  stats = 0, ['cache-report'] = 0, train_form = 0, batch_train = 0, help = 0}

local function exec_subject_line_command(cmd, m)
    assert(type(cmd) == 'table' and type(m) == 'table')
    if cmd then
      local sfid, err =
        cache.is_sfid(cmd[#cmd]) and cmd[#cmd]
          or
        msg.sfid(m)
      -- insert sfid if required by command
      if subject_line_commands[cmd[1]] == 1
      and not cache.is_sfid(cmd[#cmd]) then
        if sfid then
          table.insert(cmd, sfid)
        else
          io.stdout:write(err, '\n')
          return
        end
      end
      for i in msg.header_indices(m, 'from ', 'received', 'date',
        'from', 'to', 'message-id') do
        if i then
          io.stdout:write(m.headers[i], m.eol)
        end
      end
      io.stdout:write('Subject: Subject-line command result - ', cmd[1], m.eol)
      if cmd[1] == 'recover' then
        if not string.find(cmd[2], '%-attach') then
          table.insert(cmd, 2, '-attach')
        end
        -- make boundary from sfid
        local boundary = string.gsub(sfid, "@.*", "=-=-=")
        io.stdout:write('MIME-Version: 1.0', m.eol,
          'Content-Type: multipart/mixed;', m.eol,
          ' boundary="' .. boundary .. '"', m.eol, m.eol)
      else
        -- ends header
        io.stdout:write(m.eol)
        if cmd[1] == 'batch_train' then
          pcall(batch_train, m)
          return -- don't do normal run
        elseif cmd[1] == 'train_form' or cmd[1] == 'cache-report' then
           cmd = {'cache-report', '-send', msg.header_tagged(m, 'to')}
        end
        pcall(run, unpack(cmd))
      end
  end
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
    local cmd = msg.find_subject_command(m)
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
      msg.add_header(m, 'X-OSBF-Lua-Score', score_header)
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
    commands.write_stats(io.stdout, opts.verbose or opts.v)
  end
end
 
table.insert(usage_lines, 'stats [-v|-verbose]')

__doc.init = [[function(dbsize, ...)
Initialize OSBF-Lua's state in the filesystem.
]]

function init(dbsize, ...)
  local nb = dbsize and util.validate(util.bytes_of_human(dbsize))
  if select('#', ...) > 0 then
    usage()
  else
    if not core.isdir(cfg.dirs.user) then
      util.die('You must create the user directory before initializing it:\n',
               '  mkdir ', cfg.dirs.user)
    end
    nb = commands.init(nb)
    io.stdout:write('Created directories and databases using a total of ',
                    util.human_of_bytes(nb), '\n')
  end
end

table.insert(usage_lines, 'init [<database size in bytes>]')

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
    io.stdout:write(class, ' database resized to ',
      util.human_of_bytes(real_bytes), '\n')
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
      if not email or args[3] then usage() end
      if opts.send then
        msg.send_message(
          commands.generate_training_message(email, temail, opts.lang))
        io.stdout:write('Training form sent.\n')
      else
        commands.write_training_message(io.stdout, email, temail, opts.lang)
      end
    end
end
table.insert(usage_lines, 'cache-report [-lang=<locale>] <user-email> [<training-email>]')

-----------------------------------------------------------------

__doc.homepage = [[function()
Shows the project's home page.]]

function homepage()
  io.stdout:write(cfg.homepage, '\n')
end
table.insert(usage_lines, 'homepage')
