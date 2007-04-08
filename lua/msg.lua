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
          body      = string containing body, 
          lim = { header = string.sub(table.concat(headers), 1, cfg.text_limit),
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
  return { header = string.sub(table.concat(t.headers, '\n'), 1, cfg.text_limit),
           msg = string.sub(to_string(t), 1, cfg.text_limit)
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
  local headers = { }
  local i = 1
  repeat
    local start, fin, hdr, eol = string.find(s, '(.-)(\r?\n)[^ \t]', i)
    if start then
      assert(start == i)
      table.insert(headers, hdr)
      assert(fin > i)
      i = fin
    end
  until not start or string.find(s, '^\r?\n', i)
  local j, _, bstart = string.find(s, '\n\r?\n()', i-1)
  local body 
  if not j then
    body = ''     -- empty message
  else
    assert(j == i-1, 'Trouble at ' .. string.format('%q', string.sub(s, i-1, i+100)))
    body = string.sub(s, bstart)
  end
  local msg = { headers = headers, body = body, orig = orig }
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
  if type(v) == 'table' then
    return table.concat(v.headers, '\n') .. '\n\n' .. v.body
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
