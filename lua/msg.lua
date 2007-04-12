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
          orig_headers_block = string containing original headers,
          body      = string containing body, 
          eol       = detected eol
          lim = { header = string.sub(orig_headers_block, 1, cfg.text_limit),
                  msg = string.sub(full message in string format, 1, cfg.text_limit)
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
function demand_fields.lim(t, k)
  return { header = string.sub(t.orig_headers_block, 1, cfg.text_limit),
           msg = string.sub(to_orig_string(t), 1, cfg.text_limit)
         }
end

function demand_fields.header_index(t, k)
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
  local headers = {}
  local i, j, orig_headers_block, body, eol
  i, j, eol = string.find(s, '\r?\n(\r?\n)')
  if eol then
    orig_headers_block = string.sub(s, 1, j)
    body = string.sub(s, j+1)
  else
    orig_headers_block = s
    body = ''
    i, j, eol = string.find(s, '(\r?\n)$')
    if eol then
      s = s .. '\n'
    else
      _, _, eol = string.find(s, '(\r?\n)')
      eol = ''
      s = s .. '\n' .. '\n'
    end
  end

  function insert_header_line()
    local last_first_char = ''
    return function (h, lfc)
             table.insert(headers, last_first_char .. h)
             last_first_char = lfc or ''
             return nil
           end
  end
  local ihl = insert_header_line()
  if eol ~= '' then
    string.gsub(s, '(.-)\r?\n([^ \t])', ihl)
  end

  local msg = { headers = headers, orig_headers_block = orig_headers_block,
                body = body, eol = eol, orig = orig }
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
  return table.concat{table.concat(v.headers, v.eol), v.eol, v.eol, v.body}
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
  return v.orig_headers_block .. v.body
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
  return headers_tagged(msg, ...)()
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
