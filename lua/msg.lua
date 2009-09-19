-- See Copyright Notice in osbf.lua

local require, print, pairs, ipairs, type, error, assert, loadfile =
      require, print, pairs, ipairs, type, error, assert, loadfile

local tostring, pcall, rawget, rawset, setmetatable, getmetatable =
      tostring, pcall, rawget, rawset, setmetatable, getmetatable

local select
    = select

local function eprintf(...) return io.stderr:write(string.format(...)) end

local io, os, string, table, coroutine, tonumber, unpack =
      io, os, string, table, coroutine, tonumber, unpack

local modname = ...
module(...)

local util      = require(_PACKAGE .. 'util')
local mime      = require(_PACKAGE .. 'mime')
local core      = require(_PACKAGE .. 'core')
local fastmime  = require 'fastmime'

__doc = { __private = { } }

local debug = os.getenv 'OSBF_DEBUG'

__doc.__oneline = 'parse MIME message and manipulate headers'

__doc.__overview = ([[
A representation for parsing and modifying RFC 822 mail messages,
documented as type %s.T
]]):format(_PACKAGE)


__doc.__private.T = true
__doc.T = ([===[
The representation of a message, 
which is private to the %s module, is a table containing these fields:
    { __from          = nil or mbox format 'From ' line (without eol, if this
                        was the first line of the message),
      __headers       = list of headers, each a 'field' or 'obs-field' as 
                        defined by RFC 2822 (does not includes __from),
      __header        = string containing the original header of the
                        message plus possible separator (see Note Header below),
      __body          = string containing the original body (possibly empty),
                        or nil if the message was header-only,
      __eol           = the sequence used to designate end of line:
                        CRLF for a MIME-compliant system and for DOS files,
                        LF alone for most Unix files,
      __noncompliant  = non-nil if the message is not compliant to the RFC;
                        field contains a string explaining the noncompliance,
      __header_index  = a table giving index in list of every
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

Note Header: If the message has no body, the __header value is
(fields / obs-fields) as defined by RFC 2822.   If the message has a body,
the __header value is (fields / obs-fields) CRLF as defined by RFC2822.
CRLF will be represented using the local EOL convention as defined by the
__eol field of the message.  If the message has an mbox 'From ' line,
that is the first line of the __header value.

A message m satisfies these invariants:

  * The original message is m.__header .. (m.__body or '')

  * If m.__header_index[field_name] and m.__header_index[field_name][i],
    then
      m.__headers[m.__header_index[field_name][i]]:lower():sub(1, field_name:len()+1)
        ==
      field_name .. ':'

A message contains a metatable such that indexing the message with a
string value beginning with a non-underscore is a reference to the
field *body* of the first header that case-matches with the value.

       Examples: m.date    == "Tue, 06 May 2008 15:11:26 -0400"
                 m.subject == "Article titled: The Witcher: A (Book) Review"

In order to mutate a such a value or add a new header, such a
reference can be assigned to.  Unrealistically simple example:
                 m.references = m.references .. " <" .. sfid .. ">" 
More realistic example:
                 m['X-OSBF-Lua-Train'] = 'yes'

It is intended that a client may mutate the message headers or body
and then return a new message in string form.  Mutated headers are
returned by the %s.to_string function.

Functions in the %s and %s.mime modules may be used as message by
putting an underscore before the name, e.g., m._to_string == %s.to_string.
]===]):format(modname, modname, modname, _PACKAGE, modname)

local msg_meta = {
  __index = function(t, k)
              if type(k) == 'string' then
                if k:find '^_' then
                  return _M[k:match('^_(.*)$')]
                else
                  assert(not k:find '%s', 'space not permitted in header field name')
                  return (headers_tagged(t, k)())
                end
              end
            end,
  __newindex = function(t, k, v)
                 if type(k) ~= 'string' or k:find '^_' then
                   error('Internal fault: stored extra field ' ..
                         tostring(k) .. ' in message')
                 else
                   assert(not k:find '%s', 'space not permitted in header field name')
                   local indices = t.__header_index[k:lower()]
                   if indices then
                     local i = indices[1]
                     if i then
                       local prefix = t.__headers[i]:match '^.-:%S+'
                       t.__headers[i] = prefix .. v
                     end
                   end
                 end
               end,
  __tostring = function(msg)
                 local s = to_orig_string(msg)
                 local subject = msg.subject or '<no subject>'
                 subject = subject:gsub('%s+', ' ')
                 local fp = fingerprint(s)
                 local date = msg.date
                 date = date and mime.rfc2822_to_localtime_or_nil(date) or os.time()
                 date = os.date('(%b%y):', date)
                 local str = table.concat({ _PACKAGE .. 'msg.T', fp, date, subject }, ' ')
                 return str:sub(1, 72)
               end,
}

local function is_T(v)
  return type(v) == 'table' and getmetatable(v) == msg_meta
end

---------------------------------------------------------------------
---- Conversions

local function show(v)
  local function escape(s)
    return (s:gsub('\n', [[\n]]):gsub('\r', [[\r]]):gsub('\t', [[\t]]))
  end
  if type(v) == 'string' then
    if v:len() < 20 then return escape(string.format('%q', v))
    else return escape(string.format('%q... (%d chars)', v:sub(1, 20), v:len()))
    end
  elseif type(v) == 'table' then
    return string.format('%s (#t == %d)', tostring(v), #v)
  else
    return tostring(v)
  end
end

local function show_msg(what, m)
  eprintf('%s is:\n', what)
  for k, v in pairs(m) do
    eprintf('  %-15s %s\n', tostring(k), show(v))
  end
  eprintf('  Header index:\n')
  local keys = { }
  for k in pairs(m.__header_index) do table.insert(keys, k) end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = m.__header_index[k]
    eprintf('    %s = { %s }\n', k, table.concat(v, ', '))
  end
end

__doc.of_string = [[function(s, uncertain) returns T or nil
Takes a message in RFC 822 format and returns our internal table-based
representation of type T.  If the input string 's' is not actually an
RFC 822 message, the results are unpredictable, but if the function
can't find an EOL sequence or two colons and if uncertain is true, the
function returns nil.  Otherwise the function does its best to turn
garbage into a message.  (N.B. this function is intended to accept and
parse spam, even when the spam violates the RFC.)

Norman is less unhappy with the state of this function than he used to be.
]]

local function header_index(tags)
  local hi = setmetatable({ },
              { __index = function(t, k) rawset(t, k, {}); return rawget(t, k) end })
  for i = 1, #tags do
    table.insert(hi[tags[i]:lower()], i)
  end
  return hi
end

local eols = { CRLF = '\r\n', LF = '\n', MIXED = '\n' }

function of_string(s, uncertain)
  local parsed = fastmime.parse(s)
--[[  eprintf('Output from parser is:\n')
  for k, v in pairs(parsed) do
    eprintf('  %-15s %s\n', tostring(k), show(v))
  end
]]

  if uncertain and parsed.noncompliant and not string.find(s, '%:.*%:') then
    return nil
  end
  
  local headers = parsed.headers
  local eol = assert(eols[parsed.eol])
  local hi = header_index(parsed.tags)
  local msg = { __headers = headers, __header = parsed.headerstring,
                __noncompliant = parsed.noncompliant,
                __from = parsed.mbox_from, 
                __body = parsed.body, __eol = eol, __header_index = hi,
              }
  setmetatable(msg, msg_meta)
  if debug and parsed.noncompliant then
    show_msg(string.format('Noncompliant message (%s):', parsed.noncompliant), msg)
  end
  return msg
end

do
  local old = of_string
  local n = 0
  of_string = function(...)
                local msg = old(...)
                if msg and not (msg:_to_string() == msg:_to_orig_string()) then
                  n = n + 1
                  local f = io.open('/tmp/A' .. n, 'w')
                  if f then f:write(msg:_to_orig_string()); f:close() end
                  local f = io.open('/tmp/B' .. n, 'w')
                  if f then f:write(msg:_to_string()); f:close() end
                  local f = io.open('/tmp/msg' .. n, 'w')
                  if f then
                    local stderr = io.stderr
                    io.stderr = f
                    show_msg('Message ' .. n, msg)
                    io.stderr = stderr
                    f:close()
                  end
                  local f = io.open('/tmp/show-bad-msgs', 'a+')
                  if f then
                    f:write(string.format('cat /tmp/msg%d\n', n))
                    f:write(string.format('diff -u /tmp/A%d /tmp/B%d\n', n, n))
                    f:close()
                  end
                end
                return msg
              end
end

-------
__doc.to_string = [[function(T) returns string
Converts a message to a string in RFC 2822 format.]]

__doc.to_orig_string = [[function(T) returns string
Returns the string originally used to create the message,
which may or may comply with RFC 2822.]]

function to_string(v)
  assert(is_T(v))
  local elements
  if v.__from then
    elements = { v.__from, v.__eol }
  else
    elements = { }
  end
  table.insert(elements, table.concat(v.__headers, v.__eol))
  table.insert(elements, v.__eol)
  if v.__body then
    table.insert(elements, v.__eol)
    table.insert(elements, v.__body)
  end
  return table.concat(elements)
end

function to_orig_string(v)
  assert(is_T(v))
  if v.__body then
    return table.concat {v.__header, v.__body}
  else
    return v.__header
  end
end

----------------------------------------------------------------

__doc.headers_tagged = [[function(msg, tag, ...) returns iterator
Iterator successively yields the (untagged) value of each header
tagged with any of the tags passed in.  Values are *not* 'unfolded'.]]

__doc.header_indices = [[function(msg, tag, ...) returns iterator
Iterator successively yields *index* of each header tagged with any of
the tags passed in.]]


--- return indices of headers with each tag in turn
local yield = coroutine.yield
function header_indices(msg, ...)
  local tags = { ... }
  return coroutine.wrap(function()
                          for _, tag in ipairs(tags) do
                            local t = msg.__header_index[string.lower(tag)]
                            for i = 1, #t do
                              yield(t[i])
                            end
                          end
                        end)
end

--- pass in list of tags and return iterator that will pass through 
--- every header with any of the tags
function headers_tagged(msg, ...)
  assert(is_T(msg))
  local hs = msg.__headers
  local f = header_indices(msg, ...)
  return function()
           local hi = f()
           if hi then
             return (string.gsub(hs[hi], '^.-:%s*', ''))
           end
         end
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
  assert(is_T(msg), 'Tried to add a header to a non-message')
  table.insert(msg.__headers, tag .. ': ' .. contents)
  table.insert(msg.__header_index[tag:lower()], #msg.__headers)
end

__doc.del_header = [[function(T, tag, ...)
Deletes all headers with any of the tags passed in.
]]

function del_header(msg, ...)
  assert(is_T(msg))
  tags = { ... }
  for _, tag in ipairs(tags) do
    if is_rfc2822_field_name(tag) then
      local indices = {}
      -- collect header indices
      for i in header_indices(msg, tag:lower()) do
        table.insert(indices, i)
      end
      -- remove from last to first
      for i=#indices, 1, -1 do
        table.remove(msg.__headers, indices[i])
      end
      msg.__header_index[tag:lower()] = nil
    else
      log.logf('del_header tried to delete header with invalid tag name %s',
               tostring(tag))
    end
  end
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
    local ct = m['content-type']
    if not ct or not string.find(ct, 'multipart/') then
      return m.__body
    end
  --  io.stderr:write('content-type is ', ct, '\n')
    local boundary = string.match(ct, 'boundary="(.-)"')
                  or string.match(ct, 'boundary=(%S+)')
                if not boundary then return m.__body end
    local bpat = '[\n\r]%-%-' .. string.gsub(boundary, '%W', '%%%1') .. '.-[\n\r]'
    local _, next = string.find(m.__body, bpat)
  --  io.stderr:write('first boundary at ', tostring(next), '\n')
    if not next then return m.__body end
    local parts = { }
    for part, boundary in util.string_splits(m.__body, bpat) do
      table.insert(parts, (part:gsub('^%s+', '')))
    end
    local msgs = { }
    for _, p in ipairs(parts) do
      msgs[#msgs+1] = of_string(p, true)
    end
  --  io.stderr:write(#parts, ' parts, of which ', #msgs, ' parse as messages\n')
    local good 
    if #msgs == 0 then return parts[1] or m.__body end
--  for _, m in ipairs(msgs) do io.stderr:write(m['content-type']) or '??', '\n') end
    for _, m in ipairs(msgs) do
      local ty = m['content-type']
      if ty then
        if string.find(ty, 'text/plain') then
          good = m; break
        elseif string.find(ty, '[%s=]text/') then
          good = good or m
        end
      end
    end
    if good then return 'M: ' .. good.__body or '' else return m.__body end
  end
        

  function synopsis(m, w)
    w = w or default_synopsis_width
    local function despace(s)
      return (s:gsub('^%s+', ''):gsub('%s+', ' '):gsub(' $', ''))
    end
    local s = despace(m.subject or '')
    s = s .. '>>'
    if string.len(s) < w then
      local body = despace(choose_body_part(m) or '')
      return s .. string.sub(body, 1, w-string.len(s))
    else
      return string.sub(s, 1, w)
    end
  end
end

--[==[
__doc.fingerprint = [[function(string) returns string
Returns a short, printable string which one hopes is a unique
function of the argument.
]]
]==]

local function badfingerprint(s)
  local sums = setmetatable({ }, { __index = function() return 0 end })
  for i = 1, s:len() do
    local j = i % 8 + 1
    sums[j] = sums[j] + s:byte(i) + i
  end
  for i = 1, #sums do
    sums[i] = string.byte('a' + sums[i] % 26)
  end
  return string.char(unpack(sums))
end

-- this is overwritten by a better version in the util module


-------------------------


__doc.fingerprint = [[function(string) returns string
Uses CRC-32 and base64 encoding to returns a short, printable string
which one hopes is a unique function of the argument.
]]

function fingerprint(s)
  return core.b64encode(core.unsigned2string(core.crc32(s))):match('^(.-)=*$')
          -- trailing = signs are always redundant
end

local check = { T = is_T, string = function(s) return type(s) == 'string' end }

do
  local orig_to_string = to_string
  to_string =
    function(x, ...)
      if select('#', ...) > 0 then
        violation('Too many arguments to to_string')
      elseif not check.T(x) then
        violation('First argument to to_string is not of type T')
      else
        local function check_result(ok, s, ...)
          if not ok then
            violation('to_string called error()')
          elseif select('#', ...) > 0 then
            violation('Too many results from to_string')
          elseif not check.string(s) then
            violation('Result of to_string is not a string')
          else
            return s
          end
        end
        return check_result(pcall(orig_to_string, x))
      end
    end
end
