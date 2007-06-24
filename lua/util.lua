local require, print, pairs, type, assert, loadfile, setmetatable, tonumber =
      require, print, pairs, type, assert, loadfile, setmetatable, tonumber

local io, string, table, os, package, select, tostring, math =
      io, string, table, os, package, select, tostring, math

module(...)

local core = require(_PACKAGE .. 'core')

__doc = { }

----------------------------------------------------------------
--- Special tables.

__doc.table_tab = [[function(t) Metafunction used to create a table
on demand.]]

local function table__index(t, k) local u = { }; t[k] = u; return u end
function table_tab(t)
  setmetatable(t, { __index = table__index })
  return t
end
----------------------------------------------------------------
__doc.file_is_readable = [[function(filename) returns bool]]
function file_is_readable(file)
  local f = io.open(file, 'r')
  if f then
    f:close()
    return true
  else
    return false
  end
end
----------------------------------------------------------------
__doc.protected_dofile = [[function(filename) returns non-nil or nil, error
Attempts 'dofile(filename)', but if filename can't be loaded
(e.g., because it is missing or has a syntax error), instead of
calling lua_error(), return nil, error-message.]]

function protected_dofile(file)
  local f, err_msg = loadfile(file)
  if f then
    return f() --- had better return non-false, non-nil
  else
    return f, err_msg
  end
end
----------------------------------------------------------------
__doc.submodule_path = [[function(name) returns pathname or nil, error
Given the name of a submodule of the osbf module, returns the
location in the filesystem from which that module would be loaded.
This is used to find the default_cfg.lua file used to create the 
user's config.lua file by the init command.]]

function submodule_path(subname)
  local basename = append_slash(string.gsub(_PACKAGE, '%.$', '')) .. subname
  for p in string.gmatch (package.path, '[^;]+') do
    local path = string.gsub(p, '%?', basename)
    if file_is_readable(path) then
      return path
    end
  end
  return nil, 'Submodule ' .. subname .. ' not found'
end

----------------------------------------------------------------
__doc.os_quote = [[function(s) returns string
Takes a string s and returns s with shell metacharacters quoted,
such that if the shell reads os_quote(s), what the shell sees
is the original s.  Useful for forming commands to use with
os.execute and io.popen.]]

--- Quote a string for use in a Unix shell command.
do
  local quote_me = '[^%w%+%-%=%@%_%/]' -- easier to complement what doesn't need quotes
  local strfind = string.find

  function os_quote(s)
    if strfind(s, quote_me) or s == '' then
      return "'" .. string.gsub(s, "'", [['"'"']]) .. "'"
    else
      return s
    end
  end
end

----------------------------------------------------------------
__doc.mkdir = [[function(pathname)
If pathname is not already a directory, execute 'mkdir pathname'.
Will die with a fatal error if parent directory is missing or has
wrong permissions (i.e., if os.execute('mkdir <pathname>') fails).]]

function mkdir(path)
  if not core.isdir(path) then
    local rc = os.execute('mkdir ' .. path)
    if rc ~= 0 then
      die('Could not create directory ', path)
    end
  end
end
----------------------------------------------------------------

__doc.set_log_file = [[function(logfile) sets log file to logfile.]]

__doc.log = [[function(...) log args to logfile, prepending date and time.]]

do
  -- holds default log filename
  local logfile
  local fh

  function set_log_file(file)
    assert(type(file) == 'string')
    logfile = file
  end

  local function print_table(t)
    fh:write('{')
    for k, v in pairs(t) do
      fh:write(' ', tostring(k), ' = ')
      if type(v) == 'table' then
        print_table(v)
      else
        fh:write(tostring(v))
      end
      fh:write( ', ')
    end
    fh:write('}')
  end

  local function log_aux(first, ...)
    if type(first) == 'table' then
      print_table(first)
    else
      fh:write(tostring(first))
    end
    if select('#', ...) > 0 then
      fh:write(', ')
      log_aux(...)
    else
      fh:write('\n')
    end
  end

  function log(...)
    local err
    fh, err = io.open(logfile, 'a+')
    if fh then
      fh:write(os.date("%c - "))
      log_aux(...)
      fh:close()
      return true
    else
      return nil, err
    end
  end

end

__doc.die = [[function(...) If output is not set to message, kills process
Writes all arguments to io.stderr, then newline, then calls os.exit with
nonzero exit status.
If output is set to message, uses util.write_error to write all arguments,
doesn't kill proccess and returns normally so that procmail, or similar,
doesn't ignore filter result messages.
]]

--- Die with a fatal error message
function die(...)
  if is_output_set_to_message() then
    writenl_error(...)
    log(...)
    exit(0)
  else
    io.stderr:write(...)
    io.stderr:write('\n')
    os.exit(2)
  end
end

__doc.validate = [[function(...) returns ... or kills process
Used in place of 'assert' where a function might return nil, error
but we expect this never to happen.  If first arg is nil, calls
util.die() with the remaining arguments.  Otherwise, just acts like
the identity function, passing all arguments through as results.]]

function validate(first, ...)
  if first == nil then
    die((...)) -- only second arg goes to die()
  else
    return first, ...
  end
end
----------------------------------------------------------------
-- local definition requires because util must load before cfg

local slash = assert(string.match(package.path, [=[[\/]]=]))

__doc.append_slash = [[function(pathname) returns pathname
If the pathname does not already end with a slash, add a slash
to the end and return the result.  A slash is considered to be either 
/ or \, whichever occurs first in package.path.]]

-- append slash if missing
function append_slash(path)
  assert(type(path) == 'string')
  return string.sub(path, -1) ~= slash and path .. slash or path
end

--[===[   not used!
__doc.append_to_path = [[function(pathname, name)
Return pathname formed by pathame/name, only using whatever
the local slash convention is.]]

function append_to_path(path, file)
  return append_slash(path) .. file
end
]===]

----------------------------------------------------------------

__doc.table_sorted_keys = [[Return sorted list of keys in a table.]]

function table.sorted_keys(t, lt)
  local l = { }
  for k in pairs(t) do
    table.insert(l, k)
  end
  table.sort(l, lt)
  return l
end

__doc.case_lt = [[function(s1, s2) returns boolean.
Performs a caseless comparison between s1 and s2. If they are equal,
compares again, now taking case into account.
The last result is returned: true if s1 < s2 or false otherwise.
]]
function case_lt(s1, s2)
  local l1, l2 = string.lower(s1), string.lower(s2)
  return l1 == l2 and s1 < s2 or l1 < l2
end

  
__doc.capitalize = [[function(s) puts string into typical form for RFC 822 header.]]

-- XXX changes some usual forms: Message-ID, MIME-Version, X-UIDL, ...

function capitalize(s)
  s = '_' .. string.lower(s)
  s = string.gsub(s, '(%A)(%a)', function(nl, let) return nl .. string.upper(let) end)
  return string.sub(s, 2)
end


----------------------------------------------------------------

__doc.bytes_of_human = [[function(s) returns a string as number of bytes.]]

local mult = { [''] = 1, K = 1024, M = 1024 * 1024, G = 1024 * 1024 * 1024 }

function bytes_of_human(s)
  local n, suff = string.match(string.upper(s), '^(%d+%.?%d*)([KMG]?)B?$')
  if n and mult[suff] then
    return assert(tonumber(n)) * mult[suff]
  else
    return nil, s .. ' does not represent a number of bytes'
  end
end

local smallest_mantissa = .9999 -- I hate roundoff error
--- we choose to show, e.g. 1.1MB instead of 1109KB.


__doc.human_of_bytes = [[function(n) returns the number of bytes as a
 string readable by humans, using the proper prefix: K, M or G.]]

function human_of_bytes(n)
  assert(tonumber(n))
  local suff = ''
  for k, v in pairs(mult) do
    if v > mult[suff] and n / v >= smallest_mantissa then
      suff = k
    end
  end
  local digits = n / mult[suff]
  local fmt = digits < 100 and '%3.1f%s%s' or '%d%s%s'
  return string.format(fmt, digits, suff, 'B')
end
----------------------------------------------------------------

__doc.encode_quoted_printable = [[function(s, max_width) returns s in
quoted-printable format. Limits lines to max_width chars.]]

-- PIL, section 21.1
local split_qp_at -- returns prefix, suffix; defined below

function encode_quoted_printable(s, max_width)
  local function qpsubst(c) return string.format("=%02X", string.byte(c)) end
  s = string.gsub(s, "([\128-\255=])", qpsubst)
  local lines = { } -- accumulate lines of output
  for l in string.gmatch(string.find(s, '\n$') and s or s .. '\n', '(.-)\n') do
    l = string.gsub(l, '(%s)$', qpsubst) -- quote space at end of line
    repeat
      first, rest = split_qp_at(l, max_width)
      table.insert(lines, first)
      l = rest
    until l == nil
  end
  table.insert(lines, '') -- arrange for terminating newline
  return table.concat(lines, '\n')
end

__doc.split_qp_at = [[function(l, width) splits a line that's too long,
 quoting the newline with '='.]]

split_qp_at = function(l, width)    
  width = width or 65
  if width < 5 then width = 5 end
  if string.len(l) <= width then
    return l
  else
    -- cut off, but cannot cut off at = or =X (but =XX is OK)
    local i = width - 1
    local s = string.sub(l, 1, i)
    while string.find(s, '=.?$') do
      i = i - 1
      s = string.sub(l, 1, i)
    end
    return s .. '=', string.sub(l, i+1)
  end
end

----------------------------------------------------------------
--- html support
__doc.html = [[html support functions.]]

html = { }
do
  local quote = { ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;', ['"'] = '&quot;' }

  __doc['html.of_ascii'] = [[function(s) quotes special html chars.]]
  function html.of_ascii(s)
    return string.gsub(s, '[%&%<%>%"]', quote)
  end

  __doc['html.qp_to_html'] = [[function(qp) converts qp char to html numeric
representation: '=%x%x' => '&#%d%d%d;'.]]

  function html.qp_to_html(qp)
    return
     qp and string.format('&#%d;', tonumber('0x' .. qp))
       or
     nil
  end

  __doc['html.of_iso_8859_1'] = [[function(s) encodes ISO 8859-1 strings into
html.]]
  function html.of_iso_8859_1(s)
    s = string.gsub(s, '=(%x%x)', html.qp_to_html)
    s = string.gsub(s, '_', '&nbsp;')
    return s
  end

  __doc.html_atts = [[function(t) concatenates keys and values in table t
as a series of html attributes: " att1=v1 att2=v2 ...".
If t is nil or false, returns the empty string.]]

  local function html_atts(t)
    if t then
      local s = { }
      for k, v in pairs(t) do
        table.insert(s, table.concat { k, '="', v, '"' })
      end
      return ' ' .. table.concat(s, ' ')
    else
      return ''
    end
  end

  __doc.tag = [[function(t) meta function to apply attributes in table t to
an html tag.]]

  local function tag(t)
    return function(atts, s)
             if not s and type(atts) ~= 'table' then
               atts, s = nil, atts
             end
             if s then
               return table.concat { '<', t, html_atts(atts), '>', s, '</', t, '>' }
             else
               return table.concat { '<', t, html_atts(atts), '>' }
             end
           end
  end

  local meta = { __index = function(t, k) local u = tag(k); t[k] = u; return u end }
  setmetatable(html, meta)
end
----------------------------------------------------------------

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
                        return string.char(math.random(256)-1)
                      end)
  end
  s = string.gsub(s, '.', function(c)
                            return string.format('%02x', string.byte(c))
                          end)
  return string.sub(s,1, len)
end

__doc.generate_pwd = [[function() returns a random password with 32 hex
chars. The password is generated using util.generate_hex_string.]]

function generate_pwd()
  return generate_hex_string(32)
end


-- Support to output to message or normal stdout.
__doc.set_output_to_message = [[function(boundary, header, eol) Changes
output so that all util.write calls output its args as the body of a
properly formated message, with headers and necessary MIME part headers.
]]

__doc.unset_output_to_message = [[function() Undoes set_output_to_message.
]]

__doc.is_output_set_to_message = [[function() Returns not nil if output
is set to message or nil otherwise.
]]

__doc.write_header = [[function() Writes the header of the command-result
message header, if not outputed yet.
]]

__doc.write = [[function(...) Writes its args to standard output, like
normal io.stdout:write, but prepends a MIME header of type text/plain
for the first write in a MIME part, if output is set to message.
]]

__doc.writenl = [[function(...) Same as util.write, but appends the EOL
detected in the filter-command message.
]]

__doc.write_message = [[function(message) Writes message to standard
output, like normal io.stdout:write, but wraps it in a MIME part of
type message/rfc822, if output is set to message.
]]

__doc.write_error = [[function(...) Calls util.write if output is set to
message, or writes its args to standard error.
]]

__doc.writenl_error = [[function(...) Same as util.writenl, but appends
the EOL detected in the filter-command message.
]]

__doc.close_mime_part = [[function() Closes a MIME part writing the
proper boundary to standard output.
]]

__doc.close_mime_multipart = [[function() Closes a MIME multipart writing
the proper boundary to standard output.
]]

__doc.exit = [[function(n) terminates execution with os.exit(n), but
replaces n with 0 if output is set to message.
Used to stop procmail, or similar, from ignoring filter result messages
which will show up in the body of the command result, in case of error.
]]

do
  local header
  local mime_boundary
  local in_part = false
  local msg_eol = '\n'

  function set_output_to_message(boundary, h, eol)
    header = h
    mime_boundary = '--' .. boundary
    -- use eol of the message (should be of the system instead?)
    msg_eol = eol or '\n'
    in_part = false
  end

  function unset_output_to_message()
    mime_boundary = nil
    header = nil
    in_part = false
  end

  function is_output_set_to_message()
    return mime_boundary
  end

  function write_header()
    if header then
      io.stdout:write(header)
      header = nil
    end
  end

  function write(...)
    if mime_boundary and not in_part then
      -- output header only once
      write_header()
      io.stdout:write(table.concat({msg_eol, mime_boundary,
        'Content-Type: text/plain;',
        'Content-Transfer-Encoding: 8bit', '',''}, msg_eol))
      in_part = true
    end
    io.stdout:write(...)
  end


  function write_message(message)
    assert(type(message) == 'string')
    if mime_boundary then
      -- protect and keep the original envelope-from line
      local xooef =
        string.find(message, '^From ')
          and 'X-OSBF-Original-Envelope-From: '
        or ''
      write_header()
      io.stdout:write(table.concat({msg_eol, mime_boundary,
       'Content-Type: message/rfc822;',
       ' name="Attached Message"',
       'Content-Transfer-Encoding: 8bit',
       'Content-Disposition: inline;',
       ' filename="Attached Message"', '',
       --xooef .. message, mime_boundary, ''}, msg_eol))
       xooef .. message, ''}, msg_eol))
       in_part = false
    else
      io.stdout:write(message)
    end
  end

  function writenl(...)
    if mime_boundary then
      write(...)
      io.stdout:write(msg_eol)
    else
      io.stdout:write(...)
      io.stdout:write('\n')
    end
  end

  function write_error(...)
    if mime_boundary then
      write(...)
    else
      io.stderr:write(...)
    end
  end

  function writenl_error(...)
    if mime_boundary then
      writenl(...)
    else
      io.stderr:write(...)
      io.stderr:write('\n')
    end
  end

  function close_mime_part()
    if in_part then
      io.stdout:write(msg_eol, mime_boundary, msg_eol)
      in_part = false
    end
  end

  function close_mime_multipart()
    if mime_boundary then
      write_header()
      io.stdout:write(msg_eol, mime_boundary, '--', msg_eol)
      in_part = false
      mime_boundary = nil
    end
  end

  function exit(n)
    if not mime_boundary then
      os.exit(n)
    else
      close_mime_multipart()
      os.exit(0)
    end
  end

end

