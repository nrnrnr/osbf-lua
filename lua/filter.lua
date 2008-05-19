-- Infrastructure for filtering email
--
-- See Copyright Notice in osbf.lua


local require, print, pairs, ipairs, type, assert, setmetatable =
      require, print, pairs, ipairs, type, assert, setmetatable

local os, string, table, math, tostring =
      os, string, table, math, tostring

module(...)

__doc = __doc or { }

local util  = require(_PACKAGE .. 'util')
local cfg   = require(_PACKAGE .. 'cfg')
local msg   = require(_PACKAGE .. 'msg')
local core  = require(_PACKAGE .. 'core')
local log   = require(_PACKAGE .. 'log')
local cache = require(_PACKAGE .. 'cache')
local mime  = require(_PACKAGE .. 'mime')
local learn = require(_PACKAGE .. 'learn')  -- load the learning commands (need multiclassify)


__doc.add_osbf_header = [[function(T, tag, contents)
Adds a new OSBF-Lua header to the message with the given suffix and contents.
]]
function add_osbf_header(msg, suffix, contents)
  return msg:_add_header(cfg.header_prefix .. '-' .. suffix, contents)
end

__doc.tag_subject = [[function(msg.T, tag)
Prepends tag to all subject lines in msg headers.
If msg has no subject, adds one.
]]

function tag_subject(msg, tag)
  assert(type(tag) == 'string', 'Subject tag must be string')
  local saw_subject = false
  -- tag all subject lines
  for i in msg:_header_indices('subject') do
    if string.len(tag) > 0 then
      local function add_tag(hdr) return hdr .. ' ' .. tag end
         -- avoid trouble if tag contains, e.g., %0
      msg.__headers[i] = string.gsub(msg.__headers[i], '^.-:', add_tag, 1)
    end
    saw_subject = true
  end
  -- if msg has no subject, add one
  if not saw_subject then
    msg:_add_header('Subject', tag .. ' (no subject)')
  end
end

__doc.insert_sfid = [[function(T, sfid, string list)
Inserts the sfid into the headers named in the third argument.
The only acceptable headers are References: and Message-ID:.
Case is not significant.
]]

do
  local valid_tag = { references = true, ['message-id'] = true }
  local function valid_header_set(l)
    assert(type(l) == 'table', 'Expecting a table with valid header names')
    local t = { }
    for _, h in ipairs(l) do
      h = string.lower(h)
      if valid_tag[h] then
        t[h] = true
      else
        util.die([[I don't know how to insert a sfid into a ']] .. h [[' header.]])
      end
    end
    return t
  end

  local function remove_old_sfids(msg)
    local sfid_pat = '%s-[<%(]sfid%-.%d%+%-%d+%-%S-@' .. cfg.rightid .. '[>%)]'
    for i in msg:_header_indices('references', 'in-reply-to') do
      msg.__headers[i] = msg.__headers[i]:gsub(sfid_pat, '')
    end
  end

  function insert_sfid(msg, sfid, where)
    assert(msg.__headers) -- proxy for stronger test
    assert(cache.is_sfid(sfid), 'bad argument #2 to insert_sfid: sfid expected')

    -- add sfid to a header with tag, or if there's no such header, add one
    local function modify(tag, l, r, add_angles)
      -- l and r bracket the sfid
      -- comment indicates sfid should also be added in angle brackets
      for i in msg:_header_indices(tag) do
        msg.__headers[i] =
          table.concat {msg.__headers[i], msg.__eol, '\t' , l, sfid, r}
        return
      end
      -- no header found; create one and add the sfid
      local h = {l, sfid, r}
      if add_angles then --- executed only if no Message-ID, so can be expensive
        table.insert(h, 3, ' <'..sfid..'>')
      end
      msg:_add_header(tag, table.concat(h))
    end

    -- now remove the old sfids and insert the new one where called for
    remove_old_sfids(msg)
    local insert = valid_header_set(where or {'references'})
    if insert['references'] then modify('References', '<', '>')       end
    if insert['message-id'] then modify('Message-ID', '(', ')', true) end
  end
end

-- Used to check and parse subject-line commands
local subject_cmd_pattern = {
  classify = '^(%S+)',
  learn = '^(%S+)%s*(%S*)',
  unlearn = '^(%S+)%s*(%S*)',
  whitelist = '^(%S+)%s*(%S*)%s*(.*)',
  blacklist = '^(%S+)%s*(%S*)%s*(.*)',
  recover = '^(%S+)',
  resend = '^(%S+)',
  remove = '^(%S+)',
  help = '^%$',
  stats = '^$',
  ['cache-report'] = '^$',
  train_form = '^$',
  batch_train = '^$',
  help = '^$',
}

__doc.parse_subject_command = [[function(msg) searches first Subject: line
in msg for a filter command.
Returns a table with command and args or calls error
]]

function parse_subject_command(msg)
  assert(msg.__headers)
  local h = msg.subject
  if h then
    local cmd, pwd, args = string.match(h, '^(%S+)%s+(%S+)%s*(.*)')
    local cmd_pat = subject_cmd_pattern[cmd]
    if cmd_pat and pwd == cfg.pwd and cfg.password_ok(pwd) then
      local cmd_table = { cmd }
      for _, v in ipairs{string.match(args, cmd_pat)} do
        if v and v ~= '' then
          table.insert(cmd_table, v)
        end
      end
      return cmd_table
    end
  end
  error('No commands found on the first Subject: line')
end


__doc.send_message = [[function(message) Sends string message using
a tmp file and the OS mail command configured in cfg.mail_cmd.
Returns or calls error
]]

-- os.popen may not be available
function send_message(message)
  local tmpfile = os.tmpname()
  local tmp, err = io.open(tmpfile, "w")
  if tmp then
    tmp:write(message)
    tmp:close()
    os.execute(string.format(cfg.mail_cmd, tmpfile))
    os.remove(tmpfile)
  else
    log.lua('error', log.dt { command = 'msg.send_message',
                              tmpfile = tmpfile, err = err, message = message })
    error('Could not open ' .. tmpfile .. ' to send message: ' .. err)
  end
end

__doc.send_cmd_message = [[function(subject_command, eol) Sends a command
message with From: and To: set to cfg.command_address.
subject_command - command to be inserted in the subject line
eol             - end-of-line to be used in the message.
Returns or calls error.
]]

function send_cmd_message(subject_command, eol)
  assert(type(subject_command) == 'string')
  assert(type(eol) == 'string')
  if type(cfg.command_address) == 'string' and cfg.command_address ~= '' then 
    local message = table.concat({
      'From: ' .. cfg.command_address,
      'To: ' .. cfg.command_address,
      'Subject: ' .. subject_command, eol}, eol)
    return send_message(message)
  else
    error('Invalid or empty cfg.command_address')
  end
end


__doc.run = [[function(msg, options, [sfid]) returns sfid or calls error
Classify message and insert appropriate tags, headers, and sfid.
Call error() if anything goes wrong.  Does not insert message into
the cache, as this function may be used on the results of cache.recover
to re-deliver a mistakenly classified message.

'sfid' is the sfid assigned to the message, if any; it may be nil,
in which case a fresh sfid may be generated (depending on options).
Options is a required table in which keys 'notag',
and 'nosfid' can be set to disable subject tagging and sfid insertion.
Headers are always inserted; otherwise, why call this function?

This function returns the original sfid or the generated sfid, if any.
]]

function run(m, options, sfid)
  local probs, conf = learn.multiclassify(learn.extract_feature(m))
  -- find best class
  local bc = learn.classify(m, probs, conf)
  local crc32 = core.crc32(msg.to_orig_string(m))
  if not options.nosfid and cfg.use_sfid then
    sfid = sfid or cache.generate_sfid(bc.sfid_tag, bc.pR)
    insert_sfid(m, sfid, cfg.insert_sfid_in)
  end
  log.lua('filter', log.dt { probs = probs, conf = conf, train = bc.train,
                             synopsis = msg.synopsis(m),
                             class = bc.class, sfid = sfid, crc32 = crc32 })
  if not options.notag and cfg.tag_subject then
    tag_subject(m, bc.subj_tag)
  end
  local classes = cfg.classes
  local summary_header =
    string.format('%.2f/%.2f [%s] (v%s, Spamfilter v%s)',
                  bc.pR, classes[bc.class].conf_boost,
                  bc.sfid_tag, core._VERSION, cfg.version)
  local suffixes = cfg.header_suffixes
  add_osbf_header(m, suffixes.summary, summary_header)
  add_osbf_header(m, suffixes.class, bc.class)
  add_osbf_header(m, suffixes.confidence,
                            bc.pR and string.format('%.2f', bc.pR) or '0.0')
  add_osbf_header(m, suffixes.needs_training, bc.train and 'yes' or 'no')
  add_osbf_header(m, suffixes.sfid, sfid)
  return sfid
end

return _M
