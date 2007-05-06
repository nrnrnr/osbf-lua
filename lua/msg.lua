local require, print, pairs, ipairs, type, assert, loadfile, setmetatable =
      require, print, pairs, ipairs, type, assert, loadfile, setmetatable

local function eprintf(...) return io.stderr:write(string.format(...)) end

local io, string, table, coroutine =
      io, string, table, coroutine

module(...)

local cfg = require(_PACKAGE .. 'cfg')
local util = require(_PACKAGE .. 'util')
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
  for i = 1, #hs do
    -- io.stderr:write(string.format('Header is %q\n', hs[i]))
    local h = string.match(hs[i], '^(.-):')
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

__doc.of_string = [[function(s) returns T
Takes a message in RFC 822 format and returns our internal table-based
representation of type T.  If the input string 's' is not actually
an RFC 822 message, the results are unpredictable.  (But note that this
function is intended to accept and parse spam, even when the spam
violates the RFC.)

Norman is quite unhappy with the state of this function.  He doesn't
like the code, and he thinks the function has no business messing with
the headers.
]]

function of_string(s)
  -- Detect header fields, body and eol
  local header_fields, body, sep
  local i, j, eol = string.find(s, '\r?\n(\r?\n)')
  sep = '' -- assume not EOL between headers and body
  if eol then
    -- last header field is empty - OK and necessary if body is not empty
    header_fields = string.sub(s, 1, j)
    body = string.sub(s, j+1)
    s = header_fields
    sep = eol
  else
    eol = string.match(s, '(\r?\n)$')  -- only header fileds?
    if eol then
      header_fields = s
      body = ''
      s = s .. '\n' -- for uniform headers extraction
    else
      -- if a valid EOL is not detected we add a warning Subject:
      header_fields = 'Subject: OSBF-Lua-Warning: No EOL found in this message!\n\n'
      body = s
      eol = '\n'
      sep = eol
      s = header_fields
    end
  end

  -- header fields extraction
  local headers = {}
  do
    local lfc = ''
    for h, nfc in string.gmatch(s, '(.-)\r?\n([^ \t])') do
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
function(sfid) returns T, status or returns nil, 'missing'
Looks in the cache for the file designated by sfid, which is
an original, unmodified message.  If found, returns the message
and its cache status; if not found, returns nil, 'missing'.]]

local function of_openfile(f)
  local msg = of_string(f:read '*a')
  f:close()
  return msg
end

function of_file(filename)
  return of_openfile(assert(io.open(filename, 'r')))
end

function of_sfid(sfid)
  local openfile, status = cache.file_and_status(sfid)
  if openfile then
    return of_openfile(openfile, true), status
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
    return of_sfid(v)
  else
    assert(type(v) == 'string')
    local f = io.open(v, 'r')
    if f then
      return of_openfile(f)
    else
      return of_string(v)
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

__doc.header_tagged = [[function(msg, tag, ...) returns string
Returns the value of the first header tagged with any of the
tags passed in.]]

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
--- ever header with any of the tags
function headers_tagged(msg, ...)
  msg = of_any(msg)
  local hs = msg.headers
  local f = header_indices(msg, ...)
  return function()
           local hi = f()
           if hi then
             local h = msg.headers[hi]
             return string.gsub(h, '^.-:%s*', '')
           end
         end
end

function header_tagged(msg, ...)
  return (headers_tagged(msg, ...)())
end

----------------------------------------------------------------

__doc.add_header = [[function(T, tag, contents)
Adds a new header to the message with the given tag and contents.i
]]

local function is_rfc2822_field_name(name)
  return type(name) == 'string'
         and string.len(name) > 0
         and not string.find(name, '[^\33-\57\59-\126]') -- '[^!-9;-~]'
end

function add_header(msg, tag, contents)
  assert(is_rfc2822_field_name(tag), 'Not a valid RFC2822 field name')
  assert(type(contents) == 'string', 'Header contents must be string')
  msg = of_any(msg)
  table.insert(msg.headers, tag .. ': ' .. contents)
end

__doc.tag_subject = [[function(msg, tag)
Prepends tag to all subject lines in msg headers.
If msg has no subject, adds one.
]]

function tag_subject(msg, tag)
  msg = of_any(msg)
  assert(type(tag) == 'string', 'Subject tag must be string')
  local tagged = false
  -- tag all subject lines
  for i in header_indices(msg, 'subject') do
    msg.headers[i] = string.gsub(msg.headers[i], '^(.-:)', '%1 ' .. tag)
    tagged = true
  end
  -- if msg has no subject, add one
  if not tagged then
    add_header(msg, 'Subject', '(no subject)')
  end
end

function sfid(msgspec)
  if cache.is_sfid(msgspec) then
    return msgspec
  else
    return extract_sfid(of_any(msgspec))
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
    local t = { }
    for _, h in ipairs(l) do
      h = string.lower(h)
      if valid_tag[h] then
        t[h] = true
      else
        util.die([[I don't know how to insert a sfid into a ']] .. h [[' header.]])
      end
    end
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

__doc.sfid = [[function(msgspec) returns string or nil, error-message
Finds the sfid associated with the specified message.]]

function sfid(msgspec)
  if cache.is_sfid(msgspec) then
    return msgspec
  else
    return extract_sfid(of_any(msgspec))
  end
end

__doc.extract_sfid = [[function(msgspec) returns string or nil, error-message
Extracts the sfid from the headers of the specified message.]]

function extract_sfid(msg)
  -- if the sfid was not given in the command, extract it
  -- from the references or in-reply-to field
  msg = of_any(msg)

  for refs in headers_tagged(msg, 'references') do
    -- match the last sfid in the field (hence the initial .*)
    local sfid = string.match(refs, '.*<(sfid%-.-)>')
    if sfid then return sfid end
  end

  -- if not found as a reference, try as a comment in In-Reply-To or in References
  for field in headers_tagged(msg, 'in-reply-to', 'references') do
    local sfid = string.match(field, '.*%((sfid%-.-)%)')
    if sfid then return sfid end
  end
  
  return nil, 'Could not extract sfid from message'
end

__doc.find_subject_command = [[function(msg)
Returns a table with command and args or nil, errmsg
Searches Subject: lines in msg for a filter command.
]]

function find_subject_command(msg)
  msg = of_any(msg)
  for h in headers_tagged(msg, 'subject') do
    local cmd, pwd, args = string.match(h, '^(%S+)%s+(%S+)(.*)') 
    -- FIXME: should validate cmd too (against explicit list?
    --        subject_command table with functions, in command_line?)
    if pwd and pwd == cfg.pwd and util.password_ok(pwd) then
      local cmd_table = { cmd }
      string.gsub(args, '%S+', function (a)
                                 table.insert(cmd_table, a)
                                 return nil
                               end)
      return cmd_table
    end
  end
  return nil, 'No commands found'
end

--[[

Things to come:



You can then write, e.g.,

  for subj in msg.headers_tagged(msg, 'subject') do ... end

]]
