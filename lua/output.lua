-- Infrastructure for delivering output to multiple destinations
--
-- See Copyright Notice in osbf.lua


local require, print, pairs, ipairs, type, assert, setmetatable =
      require, print, pairs, ipairs, type, assert, setmetatable

local os, string, table, math, io, tostring =
      os, string, table, math, io, tostring

local modname = ...
module(modname)

__doc = __doc or { }

local reset = function() end
  -- will keep rebinding this function to re-initialize the 
  -- private mutable state of this module

local eol, header, mime_boundary
local reset =
  function() reset(); eol, header, mime_boundary = '\n' end


__doc.order = { 'stdout', 'write', 'writeln', 'writemsg', 'set' }

__doc.stdout = ([[file or table of (message parts or strings)

The purpose of this module is to accumulate output without knowing
whether the output will go to file (likely io.stdout and io.stderr)
or to a message.  The module provides the ability to write strings
or messages and to set the destination of the output.  If the
destination is a message, then stdout is a table with these fields:

  { boundary = MIME multipart boundary,
    header   = string header of the whole message,
    contents = list in which each element is a string or a message,
               where a message is represented by a table with two fields:
                  body      -- a string
                  envelope  -- a string either empty or containing the original
                               envelope header followed by eol,
  }

Output to files is written eagerly; output to a message is not written
until %s.exit is called.]]):format(modname)

-- default output and default error output
local stdout

local reset = function() reset(); stdout = io.stdout end

local file_meta = {
  writeln = function(self, ...) self:write(...); self:write(eol) end,
}

local table_meta = {
  write   = function(self, ...) table.insert(self.contents, table.concat {...}) end,
  writeln = file_meta.writeln,
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

function write(...) return stdout:write(...) end
function writeln(...) return (stdout.writeln or file_meta.writeln)(stdout, ...) end

__doc.type = [[function() returns 'message' or 'file']]

function _M.type()
  return mime_boundary and 'message' or 'file'
end

local envelope_field_name =  'X-OSBF-Original-Envelope-From: ' 

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

local function flush()
  if mime_boundary then
    io.stdout:write(header, eol, 'This is a message in MIME format.', eol)
    local contents = stdout.contents
    while #contents > 0 do
      local next = table.remove(contents, 1)
      if type(next) == 'table' then
        io.stdout:write((([[
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
        io.stdout:write((([[
--%s
Content-Type: text/plain
Content-Transfer-Encoding: 8bit

]]):format(mime_boundary):gsub('\n', eol)))
        io.stdout:write(next)
        while type(contents[1]) == 'string' do
          io.stdout:write(table.remove(contents, 1))
        end
      end
    end
    io.stdout:write(eol, '--', mime_boundary, '--', eol)
    reset()
  else
    stdout:flush()
    error:flush()
  end
end


__doc.exit = [[function(n) terminates execution with os.exit(n), but
replaces n with 0 if output is set to message.
Used to stop procmail, or similar, from ignoring filter result messages
which will show up in the body of the command result, in case of error.
]]

function exit(n)
  if mime_boundary then n = 0 end
  flush()
  os.exit(n)
end

__doc.set = [[
function(m, subject, [eol])  set output to message starting from m
function()                   set output to io.stdout
function(file)               set output to file

This function determines the destination of text written by %s.write()
and %s.writeln().  Destination may be a message, in which case the message
borrows headers and takes its subject from the given message and subject,
or destination may be a file, in which case writes are directly to the file.
]]

function set(m, subject, new_eol)
  if m == nil then m = io.stdout end
  if type(m) == 'userdata' and m.write and m.close then
    mime_boundary = nil
    eol = '\n'
    stdout = m
    error = io.stderr
  else
    assert(m.__headers) -- proxy for stronger test
    mime_boundary = util.generate_hex_string(40) .. "=-=-="
    stdout = setmetatable({ }, table_meta)
    error  = stdout
    eol = new_eol or '\n'
    for i in header_indices(m, 'from ', 'date', 'from', 'to') do
      if i then
        writeln(m.__headers[i])
      end
    end
  end
  subject = subject or '(No subject)' --- probably bad
  writeln((([[
Subject: %s
MIME-Version: 1.0
Content-Type: multipart/mixed;
  boundary="%s"
]]):format(subject, boundary):gsub('\n', m.eol)))
end

__doc.generate_hex_string = [[function(len) returns a string of random hex
chars, with size len. The string is generated from random bytes read from
/dev/urandom. If /dev/urandom is not readable, random bytes are produced
with math.random, after seeding math.randomseed with current time.]] 

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
  s = string.gsub(s, '.', function(c)
                            return string.format('%02x', string.byte(c))
                          end)
  return string.sub(s,1, len)
end

reset() --- do all the initialization
