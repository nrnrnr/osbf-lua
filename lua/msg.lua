local require, print, pairs, ipairs, type, assert, loadfile, setmetatable =
      require, print, pairs, ipairs, type, assert, loadfile, setmetatable

local function eprintf(...) return io.stderr:write(string.format(...)) end

local io, string, table, coroutine =
      io, string, table, coroutine

module(...)

local cfg = require(_PACKAGE .. 'cfg')
local util = require(_PACKAGE .. 'util')
local cache = require(_PACKAGE .. 'cache')


--[[

The system understands four different representations of an RFC 822
email message, the last of which is canonical.

  1. The string representation specified by the RFC
  2. The SFID of that message
  3. The name of a file containing the message
  4. A table with the following elements:
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
          orig = true or false, -- is this as originally received? (nil for unknown)
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

function of_string(s, orig)
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
    for h, nfc in string.gmatch(s, "(.-)\r?\n([^ \t])") do
      table.insert(headers, lfc .. h)
      lfc = nfc
    end
  end
  local msg = { headers = headers, header_fields = header_fields,
                body = body, sep = sep, orig = orig, eol = eol }
  setmetatable(msg, msg_meta)
  return msg
end
 
local function of_openfile(f, orig)
  local msg = of_string(f:read '*a', orig)
  f:close()
  return msg
end

function of_file(filename, orig)
  return of_openfile(assert(io.open(filename, 'r')), orig)
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

function to_string(v)
  v = of_any(v)
  return table.concat{table.concat(v.headers, v.eol), v.eol, v.sep, v.body}
end
--[[
function to_string(v)
  if type(v) == 'table' then
    return table.concat(table.concat(v.headers, v.eol), v.eol, v.eol, v.body)
  elseif cache.is_sfid(v) then
    local openfile, status = cache.file_and_status(sfid)
    if openfile then
      local s = openfile:read '*a'
      openfile:close()
      return s, status
    else
      assert(status == 'missing')
      return nil, status
    end
  else
    assert(type(v) == 'string')
    local f = io.open(v, 'r')
    if f then
      v = f:read '*a'
      f:close()
    end
    return v
  end
end
--]]

function to_orig_string(v)
  v = of_any(v)
  return v.header_fields .. v.body
end

----------------------------------------------------------------

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
    table.insert(msg.headers, 'Subject: ' .. tag .. ' (no subject)')
  end
end

function add_header(msg, header)
  assert(string.find(header, '^%S+[ \t]*:'), 'Invalid RFC-2822 header')
  msg = of_any(msg)
  table.insert(msg.headers, header)
end

function sfid(msgspec)
  if cache.is_sfid(msgspec) then
    return msgspec
  else
    return extract_sfid(of_any(msgspec))
  end
end

local valid_where = { references = true, ['message-id'] = true, both = true }
function insert_sfid(msg, sfid, where)
  msg = of_any(msg)
  assert(cache.is_sfid(sfid), 'bad argument #2 to insert_sfid: sfid expected')
  where = where or 'references'
  assert(valid_where[where],
    'bad argument #3 to insert_sfid: "references", "message-id" or "both" expected')
  -- remove old, dangling sfids
  -- better move this to a function and rethink the proper moment to
  -- call it.
  local sfid_pat =
    '%s-[<%(]sfid%-.%d%+%-%d+%-%S-@' .. cfg.rightid .. '[>%)]'
  for i in header_indices(msg, 'references', 'in-reply-to') do
    msg.headers[i] = string.gsub(msg.headers[i], sfid_pat, '')
  end

  -- insert in references?
  if where == 'references' or where == 'both' then
    local tagged = false
    for i in header_indices(msg, 'references') do
      msg.headers[i] = msg.headers[i] .. msg.eol .. '\t<' .. sfid .. '>'
      tagged = true
    end
    if not tagged then
      -- no references found; create one and add the sfid
      table.insert(msg.headers, 'References: <' .. sfid .. '>')
    end
  end
  -- repeated code pattern, probably faster than factored
  -- insert in message-id?
  if where == 'message-id' or where == 'both' then
    local tagged = false
    for i in header_indices(msg, 'message-id') do
      msg.headers[i] = table.concat{msg.headers[i], msg.eol, '\t(', sfid, ')'}
      tagged = true
    end
    if not tagged then
      -- no message-id found; create one and add the sfid
      table.insert(msg.headers,
                   table.concat{'Message-ID: <', sfid, '> (', sfid, ')'})
    end
  end
end


function sfid(msgspec)
  if cache.is_sfid(msgspec) then
    return msgspec
  else
    return extract_sfid(of_any(msgspec))
  end
end

function extract_sfid(msg)
  -- if the sfid was not given in the command, extract it
  -- from the references or in-reply-to field
  local sfid
  msg = of_any(msg)

  for refs in headers_tagged(msg, 'references') do
    -- match the last sfid in the field (hence the initial .*)
    sfid = string.match(refs, ".*<(sfid%-.-)>")
    if sfid then return sfid end
  end

  -- if not found as a reference, try as a comment in In-Reply-To or in References
  for field in headers_tagged(msg, 'in-reply-to', 'references') do
    sfid = string.match(field, ".*%((sfid%-.-)%)")
    if sfid then return sfid end
  end
  
  return nil, "Could not extract sfid from message"
end


--[[

Things to come:



You can then write, e.g.,

  for subj in msg.headers_tagged(msg, 'subject') do ... end

]]
