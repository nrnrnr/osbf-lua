-- Infrastructure for delivering output to multiple destinations
--
-- See Copyright Notice in osbf.lua


local require, print, pairs, ipairs, type, assert, setmetatable =
      require, print, pairs, ipairs, type, assert, setmetatable

local os, string, table, math, io, tostring =
      os, string, table, math, io, tostring

local modname = ...
module(modname)
local basename = modname:gsub('^.*%.', '')

__doc = __doc or { }
__private = __private or { }

local reset = function() end
  -- will keep rebinding this function to re-initialize the 
  -- private mutable state of this module

local eol, mime_boundary
local reset =
  function() reset(); eol, mime_boundary = '\n' end


__doc.__order = { 'stdout', 'error', 'write', 'writeln', 'write_message',
                  'set', 'type', 'flush', 'exit' }

__doc.__overview = ([[
The purpose of this module is to accumulate output without knowing
whether the output will go to files (likely io.stdout and io.stderr)
or to a message.  The module provides the ability to write strings
or messages and to set the destination of the output.  There are
two objects 'stdout' and 'error' which support the 'write' and 'writeln'
methods; there is also a write_message function.  If output is set to
a file, then 'stdout' goes to that file and 'error' goes to io.stderr.
If output is set to a message, everything written is accumulated as
text and eventually can be flushed as a multipart message in MIME format.

Output to files is written eagerly; output to a message is not written
until %s.flush or %s.exit is called.]]):format(basename, basename)

__doc.T = [[an internal table representing accumulated output:

  { boundary = MIME multipart boundary,
    contents = list in which each element is a string or a message,
               where a message is represented by a table with two fields:
                  body      -- a string
                  envelope  -- a string either empty or containing the original
                               envelope header followed by eol,
  }

The table has a metatable supporting 'write' and 'writeln' methods.
]]


__doc.stdout = [[file or object of type T
For normal output; supports 'write' and 'writeln' methods.
May be of type T or may be a table containing a 'file' field.
]]

__doc.error = [[file or object of type T
For error output; supports 'write' and 'writeln' methods.
]]

-- default output and default error output
local stdout

local reset = function() reset(); stdout = io.stdout end

local file_meta = {
  writeln = function(self, ...) self.file:write(...); self.file:write(eol) end,
}

local table_meta = {
  __index = {
    write   = function(self, ...) table.insert(self.contents, table.concat {...}) end,
    writeln = function(self, ...) self:write(...); self:write(eol) end,
  }
}

local function err_index(t, k)
  local v = file_meta[k]
  if v then return v end
  if type(t) == 'userdata' then return io[k]
  elseif t.file and t.file[k] then
    return function(self, ...) return self.file[k](self.file, ...) end
  end
end

local error_has_occurred
local reset = function()
                reset()
                error_has_occurred = false
                error = setmetatable({ file = io.stderr }, {__index = err_index})
              end

__doc.write = ([[function(...) 
Writes the arguments, which must be strings or numbers,
to %s.stdout; equivalent to %s.stdout:write(...).]]):format(basename, basename)

__doc.writeln = ([[function(...) 
Equivalent to %s.write(...) followed by %s.write(eol),
where eol is locally acceptable end-of-line marker.
]]):format(basename, basename)

function write(...) return stdout:write(...) end
function writeln(...) return (stdout.writeln or table_meta.writeln)(stdout, ...) end

__doc.type = [[function() returns 'message' or 'file']]

function _M.type()
  return mime_boundary and 'message' or 'file'
end

local envelope_field_name =  'X-OSBF-Original-Envelope-From: ' 

__doc.write_message = ([[function(string) returns nothing
Takes its string argument and 
  * writes to %s.stdout, if output is set to 'file'
  * accumulates the argument as an embedded message/rfc822 part, 
    if output is set to 'message'
If the string begins with a Unix mbox 'From ' line, that line
is added to the part's headers with field name
  %s
]]):format(basename, envelope_field_name)
 

function write_message(message)
  assert(type(message) == 'string')
  if mime_boundary then
    -- protect and keep the original envelope-from line
    local envelope = message:match '^From (.-)[\n\r]'
    table.insert(assert(stdout.contents), { body = message, envelope = envelope })
  else
    write(message)
  end
end

__doc.flush = ([[function([file]) returns nothing
Flushes all accumulated output to 'file', and resets
the %s module to write to standard output.  Argument
'file' defaults to io.stdout.]]):format(basename)

function flush(outfile)
  outfile = outfile or io.stdout
  if mime_boundary then
    outfile:write(eol, 'This is a message in MIME format.', eol)
    local contents = stdout.contents
    while #contents > 0 do
      local next = table.remove(contents, 1)
      if type(next) == 'table' then
        outfile:write((([[
--%s
Content-Type: message/rfc822; name="Attached Message"
Content-Transfer-Encoding: 8bit
Content-Disposition: inline; filename="Attached Message"
%s
%s
]]):format(mime_boundary,
          contents.envelope
            and table.concat { envelope_field_name, ': ', contents.envelope, eol }
            or '',
             message):gsub('\n', eol)))
      else         
        outfile:write((([[
--%s
Content-Type: text/plain
Content-Transfer-Encoding: 8bit

]]):format(mime_boundary):gsub('\n', eol)))
        outfile:write(next)
        while type(contents[1]) == 'string' do
          outfile:write(table.remove(contents, 1))
        end
      end
    end
    outfile:write(eol, '--', mime_boundary, '--', eol)
    outfile:flush()
    reset()
  else
    stdout:flush()
    error:flush()
  end
end


__doc.exit = [[function(n) terminates execution 
Flushes all accumulated output and
  * calls os.exit(n), if the output is set to 'file'
  * calls os.exit(0), if the output is set to 'message'
Used to stop procmail, or similar, from ignoring filter result messages
which will show up in the body of the command result, in case of error.
]]

function exit(n)
  if mime_boundary then n = 0 end
  flush()
  os.exit(n)
end

__doc.set = ([[

function(m, subject, [eol])  set output to message starting from m
function()                   set output to io.stdout
function(file)               set output to file

This function determines the destination of text written by %s.write()
and %s.writeln().  Destination may be a message, in which case the message
borrows headers and takes its subject from the given message and subject,
or destination may be a file, in which case writes are directly to the file.
]]):format(basename, basename)

function set(m, subject, new_eol)
  if m == nil then m = io.stdout end
  if type(m) == 'userdata' and m.write and m.close then
    mime_boundary = nil
    eol = '\n'
    stdout = m
    error = io.stderr
  else
    assert(m.__headers) -- proxy for stronger test
    mime_boundary = generate_hex_string(40) .. "=-=-="
    stdout = setmetatable({ boundary = mime_boundary, contents = { } }, table_meta)
    error  = stdout
    eol = new_eol or '\n'
    for i in m:_header_indices('from ', 'date', 'from', 'to') do
      if i then
        writeln(m.__headers[i])
      end
    end
  end
  subject = subject or '(Reply from OSBF-Lua)'
  writeln((([[
Subject: %s
MIME-Version: 1.0
Content-Type: multipart/mixed;
  boundary="%s"
]]):format(subject, mime_boundary):gsub('\n', m.__eol)))
end

__doc.generate_hex_string = [[function(len) returns string
Returns a string of length 'len' containing random hex chars.
The string is generated from random bytes read from /dev/urandom. 
If /dev/urandom is not readable, random bytes are produced with
math.random, after seeding math.randomseed with current time.]]

function generate_hex_string(len)
  assert (type(len) == 'number')
  local bytes = math.floor(len / 2) + 1
  local fh = io.open('/dev/urandom', 'r')
  local s
  if fh then
    s = fh:read(bytes)
    fh:close()
  end
  if not s then
    math.randomseed(os.time())
    s = string.gsub(string.rep(' ', bytes), '.',
                      function(c)
                        return string.char(math.random(0, 255))
                      end)
  end
  s = s:gsub('.', function(c) return string.format('%02x', string.byte(c)) end)
  return string.sub(s,1, len)
end

reset() --- do all the initialization
