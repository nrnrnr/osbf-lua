-- See Copyright Notice in osbf.lua

local require, print, pairs, ipairs, type, error, assert, loadfile, setmetatable =
      require, print, pairs, ipairs, type, error, assert, loadfile, setmetatable

local tostring, pcall =
      tostring, pcall

local function eprintf(...) return io.stderr:write(string.format(...)) end

local io, os, string, table, coroutine, tonumber =
      io, os, string, table, coroutine, tonumber

module(...)

local cfg   = require(_PACKAGE .. 'cfg')
local util  = require(_PACKAGE .. 'util')
local cache = require(_PACKAGE .. 'cache')

__doc = { }

__doc.__overview = [[
The system understands four different representations of an RFC 822
email message, the last of which is canonical.

  1. The string representation specified by the RFC
  2. The SFID of that message
  3. The name of a file containing the message
  4. A message table documented as type T
]] 

__doc.T = [[a table
The main representation of a message is a table with these elements:

    { headers   = list of header strings,
      header_fields = string containing the original header of the
                      message. It will also contain the EOL which
                      separates the body from the header, if present
                      in the message final part,
      sep       = EOL which separates the header from body, or the empty
                  string if there's no separator (and no body),
      body      = string containing the original body,
      eol       = string with the eol used by the message,
      lim = { header = string.sub(header_fields, 1, cfg.text_limit),
              msg = string.sub(header_fields .. body, 1, cfg.text_limit)
            },
      header_index = a table giving index in list of every
                     occurrence of each header, indexed by all
                     lower case
    }

An example of the header_index table (abbreviated) might be

 { ['return-path'] = { 1, 4 },
   ['delivery-date'] = { 2, 3 },
   ['delivered-to'] = { 5 },
   ['received'] = { 6, 7, 8, 9, 10, 11 },
   ['to'] = { 12 },
   ['subject'] = { 13 },
 }

Some fields might be generated on demand by a metatable.

It is intended that a client may mutate the message headers or body and
then return a new message in string form.
]]

local demand_fields = { }
demand_fields.lim = function(t, k)
  return { header = string.sub(t.header_fields, 1, cfg.text_limit),
           msg = string.sub(to_orig_string(t), 1, cfg.text_limit)
         }
end

demand_fields.header_index = function(t, k)
  local index = util.table_tab { }
  local hs = t.headers
  local start_idx = 1
  -- handle envelope 'From ' header
  if string.find(hs[1], '^From ') then
    table.insert(index['from '], 1)
    start_idx = 2
  end
  for i = start_idx, #hs do
    -- io.stderr:write(string.format('Header is %q\n', hs[i]))
    local h = string.match(hs[i], '^(%S-)%s*:')
    if h then
      table.insert(index[string.lower(h)], i)
    else
      if cfg.verbose then eprintf('Bad line in RFC 822 header: %q\n', hs[i]) end
    end
  end
  return index
end

local msg_meta = {
  __index = function(t, k)
              if demand_fields[k] then
                local v = demand_fields[k](t, k)
                t[k] = v
                return v
              end
            end
}

---------------------------------------------------------------------
---- Conversions

__doc.of_string = [[function(s, uncertain) returns T
Takes a message in RFC 822 format and returns our internal table-based
representation of type T.  If the input string 's' is not actually an
RFC 822 message, the results are unpredictable, but if the function
can't find an EOL sequence or two colons and if uncertain is true, the
function returns nil.  Otherwise the function does its best to turn
garbage into a message.  (N.B. this function is intended to accept and
parse spam, even when the spam violates the RFC.)

Norman is less unhappy with the state of this function than he used to be.
]]

function of_string(s, uncertain)
  -- Detect header fields, body and eol
  local header_fields, body, sep
  local i, j, eol = string.find(s, '\r?\n(\r?\n)')
  sep = '' -- assume not EOL between headers and body
  if eol then
    -- last header field is empty - OK and necessary if body is not empty
    header_fields = string.sub(s, 1, j)
    body = string.sub(s, j+1)
    sep = eol
  else
    if uncertain and not string.find(s, '%:.*%:') then return nil end
    eol = string.match(s, '(\r?\n)$')  -- only header fileds? only body?
    if eol and string.find(s, '%a%:') then -- treat s as headers
      header_fields = s .. '\n'  -- for uniform headers extraction
      body = ''
    else
      -- if a valid EOL is not detected we add a warning Subject:
      header_fields =
        string.format('Subject: OSBF-Lua-Warning: No %s found in this message!\n\n',
                      eol and 'headers' or 'EOL')
      -- but if we can't find two colons, this just can't be a message
      body = s
      eol = '\n'
      sep = eol
    end
  end

  -- header fields extraction
  local headers = {}
  do
    local lfc = ''
    for h, nfc in string.gmatch(header_fields, '(.-)\r?\n([^ \t])') do
      table.insert(headers, lfc .. h)
      lfc = nfc
    end
  end
  local msg = { headers = headers, header_fields = header_fields,
                body = body, sep = sep, eol = eol }
  setmetatable(msg, msg_meta)
  return msg
end
 
---------- auxiliary converters

__doc.of_openfile = [[
function(f) returns T
f is a file handle open for reading; it should contain an RFC 822
message as described for 'msg.of_string'.]]

__doc.of_file = [[
function(filename) returns T
filename is the name of a file that contains an RFC 822 message as
described for 'msg.of_string'.]]

__doc.of_sfid = [[
function(sfid) returns T, status
Looks in the cache for the file designated by sfid, which is
an original, unmodified message.  If found, returns the message
and its cache status; if not found, returns nil, 'missing'.]]

local function of_openfile(f)
  local ok, msg = pcall(of_string, util.validate(f:read '*a'))
  f:close()
  if ok then
    return msg
  else
    error(msg)
  end
end

function of_file(filename)
  return of_openfile(assert(io.open(filename, 'r')))
end

function of_sfid(sfid)
  local openfile, status = cache.file_and_status(sfid)
  if openfile then
    return of_openfile(openfile), status
  else
    assert(status == 'missing')
    return nil, status
  end
end

---------- guess which converter

__doc.of_any = [[function(v) returns T
Takes v and tries to return a table of type T.
Possibilities in order:
  v is already a table
  v is a sfid
  v is a readable file
  v is a string containing a message
Generally to be used from the command line, not from
functions that know what they're doing.]]


function of_any(v)
  if type(v) == 'table' then
    return v
  elseif cache.is_sfid(v) then
    local m = of_sfid(v)
    if not m then error('sfid ' .. v .. ' is missing from the cache') end
    return m
  else
    assert(type(v) == 'string')
    local f = io.open(v, 'r')
    if f then
      return of_openfile(f)
    else
      local msg = of_string(v, true)
      if not msg then
        util.errorf("'%s' is not a sfid, a readable file, or an RFC 822 message", v)
      end
      return msg
    end
  end
end

-------
__doc.to_string = [[function(v) returns string
Takes a 'v' in any form acceptable to of_any
and returns a string containing the message.
Most commonly used to convert a T to a string,
e.g., for output.]]

__doc.to_orig_string = [[function(v) returns string
Takes a 'v' in any form acceptable to of_any
and returns a string containing the original message.
Differs from to_string only when applied to a table
whose headers or body have been modified.]]

function to_string(v)
  v = of_any(v)
  return table.concat{table.concat(v.headers, v.eol), v.eol, v.sep, v.body}
end

function to_orig_string(v)
  v = of_any(v)
  return v.header_fields .. v.body
end

----------------------------------------------------------------

__doc.headers_tagged = [[function(msg, tag, ...) returns iterator
Iterator successively yields the (untagged) value of each header
tagged with any of the tags passed in.]]

__doc.header_tagged = [[function(msg, tag, ...) returns string or nil
Returns the value of the first header tagged with any of the
tags passed in, if any such header exists.]]

__doc.header_indices = [[function(msg, tag, ...) returns iterator
Iterator successively yields *index* of each header tagged with any of
the tags passed in.]]


--- return indices of headers with each tag in turn
local yield = coroutine.yield
function header_indices(msg, ...)
  msg = of_any(msg)
  local tags = { ... }
  return coroutine.wrap(function()
                          for _, tag in ipairs(tags) do
                            local t = msg.header_index[string.lower(tag)]
                            for i = 1, #t do
                              yield(t[i])
                            end
                          end
                        end)
end


--- pass in list of tags and return iterator that will pass through 
--- every header with any of the tags
function headers_tagged(msg, ...)
  local hs = msg.headers
  local f = header_indices(msg, ...)
  return function()
           local hi = f()
           if hi then
             return string.gsub(hs[hi], '^.-:%s*', '')
           end
         end
end

function header_tagged(msg, ...)
  return (headers_tagged(msg, ...)())
end

----------------------------------------------------------------

local function is_rfc2822_field_name(name)
  return type(name) == 'string'
         and string.len(name) > 0
         and not string.find(name, '[^\33-\57\59-\126]') -- '[^!-9;-~]'
end

__doc.add_header = [[function(T, tag, contents)
Adds a new header to the message with the given tag and contents.
]]

function add_header(msg, tag, contents)
  assert(is_rfc2822_field_name(tag), 'Not a valid RFC2822 field name')
  assert(type(contents) == 'string' or type(contents) == 'number',
         'Header contents must be string or number')
  msg = of_any(msg)
  table.insert(msg.headers, tag .. ': ' .. contents)
  msg.lim = nil
  msg.header_index = nil
end

__doc.add_osbf_header = [[function(T, tag, contents)
Adds a new OSBF-Lua header to the message with the given suffix and contents.
]]
function add_osbf_header(msg, suffix, contents)
  return add_header(msg, cfg.header_prefix .. '-' .. suffix, contents)
end

__doc.del_header = [[function(T, tag, ...)
Deletes all headers with any of the tags passed in.
]]

function del_header(msg, ...)
  msg = of_any(msg)
  tags = { ... }
  for _, tag in ipairs(tags) do
    if is_rfc2822_field_name(tag) then
      local indices = {}
      -- collect header indices
      for i in header_indices(msg, string.lower(tag)) do
        table.insert(indices, i)
      end
      -- remove from last to first
      for i=#indices, 1, -1 do
        table.remove(msg.headers, indices[i])
      end
    else
      log.logf('del_header tried to delete header with invalid tag name %s',
               tostring(tag))
    end
  end
  msg.lim = nil
  msg.header_index = nil
end 

__doc.tag_subject = [[function(msg, tag)
Prepends tag to all subject lines in msg headers.
If msg has no subject, adds one.
]]

function tag_subject(msg, tag)
  msg = of_any(msg)
  assert(type(tag) == 'string', 'Subject tag must be string')
  local saw_subject = false
  -- tag all subject lines
  for i in header_indices(msg, 'subject') do
    if string.len(tag) > 0 then
      local function add_tag(hdr) return hdr .. ' ' .. tag end
         -- avoid trouble if tag contains, e.g., %0
      msg.headers[i] = string.gsub(msg.headers[i], '^.-:', add_tag, 1)
    end
    saw_subject = true
  end
  -- if msg has no subject, add one
  if not saw_subject then
    add_header(msg, 'Subject', tag .. ' (no subject)')
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
    for i in header_indices(msg, 'references', 'in-reply-to') do
      msg.headers[i] = string.gsub(msg.headers[i], sfid_pat, '')
    end
  end

  function insert_sfid(msg, sfid, where)
    msg = of_any(msg)
    assert(cache.is_sfid(sfid), 'bad argument #2 to insert_sfid: sfid expected')

    -- add sfid to a header with tag, or if there's no such header, add one
    local function modify(tag, l, r, add_angles)
      -- l and r bracket the sfid
      -- comment indicates sfid should also be added in angle brackets
      for i in header_indices(msg, tag) do
        msg.headers[i] = table.concat {msg.headers[i], msg.eol, '\t' , l, sfid, r}
        return
      end
      -- no header found; create one and add the sfid
      local h = {tag, ': ', l, sfid, r}
      if add_angles then --- executed only if no Message-ID, so can be expensive
        table.insert(h, 3, ' <'..sfid..'>')
      end
      table.insert(msg.headers, table.concat(h))
    end

    -- now remove the old sfids and insert the new one where called for
    remove_old_sfids(msg)
    local insert = valid_header_set(where or {'references'})
    if insert['references'] then modify('References', '<', '>')       end
    if insert['message-id'] then modify('Message-ID', '(', ')', true) end
  end
end

__doc.sfid = [[function(msgspec) returns string or calls error
Finds the sfid associated with the specified message.]]

function sfid(msgspec)
  if cache.is_sfid(msgspec) then
    return msgspec
  else
    return extract_sfid(of_any(msgspec), msgspec)
  end
end

__doc.extract_sfid = [[function(msg[, spec]) returns string or calls error
Extracts the sfid from the headers of the specified message.]]

local ref_pat, com_pat -- depend on cfg and cache; don't set until needed

local sfid_header
cfg.after_loading_do(
  function() sfid_header = cfg.header_prefix .. '-' .. cfg.header_suffixes.sfid end)

function extract_sfid(msg, spec)
  -- if the sfid was not given in the command, extract it
  -- from the appropriate header or from the references or in-reply-to field

  local sfid = header_tagged(msg, sfid_header)
  if sfid then return sfid end

  ref_pat = ref_pat or '.*<(' .. cache.loose_sfid_pat .. ')>'
  com_pat = com_pat or '.*%((' .. cache.loose_sfid_pat .. ')%)'
  

  for refs in headers_tagged(msg, 'references') do
    -- match the last sfid in the field (hence the initial .*)
    local sfid = refs:match(ref_pat)
    if sfid then return sfid end
  end

  -- if not found as a reference, try as a comment in In-Reply-To or in References
  for field in headers_tagged(msg, 'in-reply-to', 'references') do
    local sfid = field:match(com_pat)
    if sfid then return sfid end
  end
  
  error('Could not extract sfid from message ' .. (spec or tostring(msg)))
end

__doc.has_sfid = [[function(T) returns bool
Tells whether the given message contains a sfid in one
of the relevant headers.
]]

function has_sfid(msg)
  return (pcall(extract_sfid, msg)) -- just the one result
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
  msg = of_any(msg)
  local h = header_tagged(msg, 'subject')
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

__doc.rfc2822_to_localtime_or_nil = [[function(date) returns string or nil
Converts RFC2822 date to local time in the format "YYYY/MM/DD HH:MM".
]]

local tmonth = {jan=1, feb=2, mar=3, apr=4, may=5, jun=6,
                jul=7, aug=8, sep=9, oct=10, nov=11, dec=12}

function rfc2822_to_localtime_or_nil(date)
  -- remove comments (CFWS)
  date = string.gsub(date, "%b()", "")

  -- Ex: Tue, 21 Nov 2006 14:26:58 -0200
  local day, month, year, hh, mm, ss, zz =
    string.match(date,
     "%a%a%a,%s+(%d+)%s+(%a%a%a)%s+(%d%d+)%s+(%d%d):(%d%d)(%S*)%s+(%S+)")

  if not (day and month and year) then
    day, month, year, hh, mm, ss, zz =
    string.match(date,
     "(%d+)%s+(%a%a%a)%s+(%d%d+)%s+(%d%d):(%d%d)(%S*)%s+(%S+)")
    if not (day and month and year) then
      return nil
    end
  end

  local month_number = tmonth[string.lower(month)]
  if not month_number then
    return nil
  end

  year = tonumber(year)

  if year >= 0 and year < 50 then
    year = year + 2000
  elseif year >= 50 and year <= 99 then
    year = year + 1900
  end

  if not ss or ss == "" then
    ss = 0
  else
    ss = string.match(ss, "^:(%d%d)$")
  end

  if not ss then
    return nil
  end


  local tz = nil
  local s, zzh, zzm = string.match(zz, "([-+])(%d%d)(%d%d)")
  if s and zzh and zzm then
    tz = zzh * 3600 + zzm * 60
    if s == "-" then tz = -tz end
  else
    if zz == "GMT" or zz == "UT" then
      tz = 0;
    elseif zz == "EST" or zz == "CDT" then
      tz = -5 * 3600
    elseif zz == "CST" or zz == "MDT" then
      tz = -6 * 3600
    elseif zz == "MST" or zz == "PDT" then
      tz = -7 * 3600
    elseif zz == "PST" then
      tz = -8 * 3600
    elseif zz == "EDT" then
      tz = -4 * 3600
    -- todo: military zones
    end
  end

  if not tz then
    return nil
  end

  local ts = os.time{year=year, month=month_number,
                      day=day, hour=hh, min=mm, sec=ss}

  if not ts then
    util.errorf('Failed to convert [[%s]] to local time', date)
  end

  -- find out the local offset to UTC
  local uy, um, ud, uhh, umm, uss =
       string.match(os.date("!%Y%m%d %H:%M:%S", ts),
                       "(%d%d%d%d)(%d%d)(%d%d) (%d%d):(%d%d):(%d%d)")
  lts = os.time{year=uy, month=um,
                      day=ud, hour=uhh, min=umm, sec=uss}
  local off_utc = ts - lts

  return ts - (tz - off_utc)
end

__doc.valid_boundary = [[function(boundary) Returns boundary if boundary
is a valid RFC2046 MIME boundary or false otherwise.
]]

-- RFC2046
local bcharnospace = "[%d%a'()+_,-./:=?]"
local bcharspace = "[ %d%a'()+_,-./:=?]"
local bpattern = '^' .. bcharspace .. '*' .. bcharnospace .. '$'
function valid_boundary(boundary)
  return
    type(boundary) == 'string'
      and
    string.len(boundary) <= 70 and string.match(boundary, bpattern)
      and
    boundary
      or
    false
end

__doc.attach_message = [[function(sfid, boundary)
Recovers message associated with sfid from cache and returns it wrapped
in MIME boundaries. boundary is optional string. If ommited, it is
derived from sfid.
If sfid is not found in cache, an error message is returned wrapped
in MIME boundaries.
]]

function attach_message(sfid, boundary)
  boundary = assert(boundary == nil or valid_boundary(boundary),
   'Invalid boundary to attach_message')
  if boundary == true then
    boundary =
      cache.is_sfid(sfid)
        and
      string.gsub(sfid, "@.*", "=-=-=", 1)
        or
      'error-boundary=_=_='
  end
    
  local ok, msg_content = pcall (cache.recover, sfid)
  if ok then
    local m = of_string(msg_content)
    -- protect and keep the original envelope-from line
    local xooef =
      string.find(msg_content, '^From ')
        and 'X-OSBF-Original-Envelope-From: '
      or ''

    msg_content = table.concat({'--' .. boundary,
       'Content-Type: message/rfc822;',
       ' name="Recovered Message"',
       'Content-Transfer-Encoding: 8bit',
       'Content-Disposition: inline;',
       ' filename="Recovered Message"', '',
       xooef .. msg_content,
       '--' .. boundary .. '--', ''}, m.eol)
  else
    msg_content = table.concat({'--' .. boundary,
       'Content-Type: text/plain;',
       ' name="Error message"',
       'Content-Transfer-Encoding: 8bit',
       'Content-Disposition: inline;', '',
       msg_content,
       '--' .. boundary .. '--', ''}, '\r\n')
  end

  return msg_content
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

__doc.set_output_to_message = [[function(m, subject) Builds a message
header reusing some headers of m and making subject equal to arg subject.
It also adds MIME headers to prepare for a multipart/mixed body.
This permits that folowing outputs of util.write may be done in a proper
way to be interpreted as the body of a message.
The header and boundary generated are comunicated to
util.set_output_to_message so util.write uses the same boundary for
next parts.
]]

function set_output_to_message(m, subject)
  m = of_any(m)
  assert(type(subject) == 'string')
  local boundary = util.generate_hex_string(40) .. "=-=-="
  -- reuse some headers
  local headers = {}
  for i in header_indices(m, 'from ', 'date', 'from', 'to') do
    if i then
      table.insert(headers, m.headers[i])
    end
  end
  for _, h in ipairs{'Subject: ' .. subject, 'MIME-Version: 1.0',
               'Content-Type: multipart/mixed;',
               ' boundary="' .. boundary .. '"', m.eol} do 
    table.insert(headers, h)
  end
  util.set_output_to_message(boundary, table.concat(headers, m.eol), m.eol)
end

----------------------------------------------------------------
do 
  local default_synopsis_width = 60
  __doc.synopsis = [[function(T, w) returns string
  Returns a string of width w (default $w) which is a synopsis of the
  message T.  The synopsis is formed from the Subject: line and the
  first few words of the body.]]

  __doc.synopsis = __doc.synopsis:gsub('%$w', default_synopsis_width)

  local function choose_body_part(m)
    local ct = header_tagged(m, 'content-type')
    if not ct or not string.find(ct, 'multipart/') then
      return m.body
    end
  --  io.stderr:write('content-type is ', ct, '\n')
    local boundary = string.match(ct, 'boundary="(.-)"')
                  or string.match(ct, 'boundary=(%S+)')
                if not boundary then return m.body end
    local bpat = '[\n\r]%-%-' .. string.gsub(boundary, '%W', '%%%1') .. '.-[\n\r]'
    local _, next = string.find(m.body, bpat)
  --  io.stderr:write('first boundary at ', tostring(next), '\n')
    if not next then return m.body end
    local parts = { }
    repeat
      local first, last = next+1
      last, next = string.find(m.body, bpat, first)
      if last then
        table.insert(parts, (string.gsub(string.sub(m.body, first, last-1), '^%s+', '')))
      end
    until not last
    local msgs = { }
    for _, p in ipairs(parts) do
      msgs[#msgs+1] = of_string(p, true)
    end
  --  io.stderr:write(#parts, ' parts, of which ', #msgs, ' parse as messages\n')
    local good 
    if #msgs == 0 then return parts[1] or m.body end
  --  for _, m in ipairs(msgs) do io.stderr:write(header_tagged(m, 'content-type') or '??', '\n') end
    for _, m in ipairs(msgs) do
      local ty = header_tagged(m, 'content-type')
      if ty then
        if string.find(ty, 'text/plain') then
          good = m; break
        elseif string.find(ty, '[%s=]text/') then
          good = good or m
        end
      end
    end
    if good then return 'M: ' .. good.body else return m.body end
  end
        

  function synopsis(m, w)
    w = w or default_synopsis_width
    local function despace(s)
      s = string.gsub(s, '^%s+', '')
      s = string.gsub(s, '%s+', ' ')
      s = string.gsub(s, ' $', '')
      return s
    end
    local s = despace(header_tagged(m, 'subject') or '')
    s = s .. '>>'
    if string.len(s) < w then
      local body = despace(choose_body_part(m))
      return s .. string.sub(body, 1, w-string.len(s))
    else
      return string.sub(s, 1, w)
    end
  end
end

