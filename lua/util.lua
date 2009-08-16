-- See Copyright Notice in osbf.lua

local require, print, pairs, type, assert, loadfile, setmetatable, tonumber, error =
      require, print, pairs, type, assert, loadfile, setmetatable, tonumber, error

local pcall, next
    = pcall, next

local io, string, table, os, package, select, tostring, math, coroutine =
      io, string, table, os, package, select, tostring, math, coroutine

local modname = ...
module(...)

local core   = require(_PACKAGE .. 'core')
local output = require(_PACKAGE .. 'output')

local debug = os.getenv 'OSBF_MEMO'

__doc = { }



----------------------------------------------------------------
--- Special tables.

__doc.table_tab = [[function(t) returns t with new metatable
Each reference to a missing key in t now returns a fresh table.]]

local function table__index(t, k) local u = { }; t[k] = u; return u end
function table_tab(t)
  return setmetatable(t, { __index = table__index })
end
----------------------------------------------------------------
__doc.isdir = [[function(pathname) returns boolean
Tells whether pathname is a directory.]]
isdir = core.isdir

----------------------------------------------------------------
__doc.tablerep = [[function(v, n) returns array
Returns a list containing n copies of v in slots
1 through n.]]

function tablerep(v, n)
  local data = { }
  for i = 1, n do data[i] = v end
  return data
end
----------------------------------------------------------------
__doc.tablemap = [[function(f, t, ...) returns table
Takes the table t and applies f to every value.
More exactly, returns a fresh table t2 in which 
every key k is associated with f(t[k], ...).]]

function tablemap(f, t, ...)
  local data = { }
  for k, v in pairs(t) do data[k] = f(v, ...) end
  return data
end
----------------------------------------------------------------
__doc.tablemapk = [[function(f, t, ...) returns table
Takes the table t and applies f to every key-value pair.
More exactly, returns a fresh table t2 in which 
every key k is associated with f(k, t[k], ...).]]

function tablemapk(f, t, ...)
  local data = { }
  for k, v in pairs(t) do data[k] = f(k, v, ...) end
  return data
end
----------------------------------------------------------------
__doc.tablefilter = [[function(f, l, ...) returns array
Takes the array l and applies f to every element to
get a Boolean result. More exactly, the Boolean is f(l[i], ...).
Returns a new array containing only those elements l[i]
for which f(l[i], ...) is true.
]]

function tablefilter(f, l, ...)
  local data = { }
  for i = 1, #l do if f(l[i], ...) then data[#data+1] = l[i] end end
  return data
end
----------------------------------------------------------------
__doc.tablecount = [[function(f, l, ...) returns number
Takes the array l and returns the number of elements l[i]
such that f(l[i], ...) holds.
]]

function tablecount(f, l, ...)
  local n = 0
  for i = 1, #l do if f(l[i], ...) then n = n + 1 end end
  return n
end
----------------------------------------------------------------
__doc.same_keys = [[function(t1, t2) returns boolean
Returns true if and only if tables t1 and t2 have the same keys.
Crashes if t1 or t2 is not a table.
]]

function same_keys(t1, t2)
  local function subkeys(t1, t2)
    for k in pairs(t1) do if t2[k] == nil then return false end end
    return true
  end
  return subkeys(t1, t2) and subkeys(t2, t1)
end
----------------------------------------------------------------
__doc.key_max = [[function(t, [, f, ...]) returns non-nil or calls error
Takes table t, in which every value must be a number, and
returns key k such that f(t[k], ...) is as large as possible;
if f is nil then it uses tonumber. Ties are broken arbitrarily.  

Calls error() if value cannot be converted to a number or if table is
empty.
]]

function key_max(t, f, ...)
  local key, max = next(t)
  f = f or tonumber
  for k, v in pairs(t) do
    local x = f(v, ...)
    if type(x) ~= 'number' then error('Comparing non-number ' .. tostring(x), 2) end
    if x > max then
      key, max = k, x
    end
  end
  if not key then error('Passing empty table to util.key_max', 2) end
  return key
end
----------------------------------------------------------------
__doc.tablecopy = [[function(t) returns table
Returns a fresh table that contains the keys and
values obtained from pairs(t).]]
function tablecopy(t)
  local data = { }
  for k, v in pairs(t) do data[k] = v end
  return data
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
__doc.memoize = [[function(f) returns f
returns a memoized version of function f.
f must always take exactly one non-nil argument
and may return at most one result.]]

local function pop(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function memoize (f)
  local n = 0
  local function index(t, k)
    -- metamethod called when k is not in the cache; f(k) is passed to update()
    local function update(v, ...)
      assert(select('#', ...) == 0)
      t[k] = v
      return v
    end
    if debug then
      n = n + 1
      if n == 100 then
        io.stderr:write('Memoization table has ', pop(t), ' entries\n')
        n = 1
      end
    end
    return update(f(k))
  end
  local cache = setmetatable({ }, { __mode = 'k', __index = index })
  return function (x, ...)
           assert(select('#', ...) == 0)
           return cache[x]
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
__doc.submodule_path = [[function(name) returns pathname or calls lua_error
Given the name of a submodule of the osbf module, returns the
location in the filesystem from which that module would be loaded.
This is used to find the default_cfg.lua file used to create the 
user's config.lua file by the init command.]]

function submodule_path(subname)
  local basename = append_slash((_PACKAGE:gsub('%.$', ''))) .. subname
  for p in string.gmatch (package.path, '[^;]+') do
    local path = p:gsub('%?', basename)
    if file_is_readable(path) then
      return path
    end
  end
  error('Submodule ' .. subname .. ' not found')
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
__doc.reserved = [[set of reserved words in Lua
Represented as table with reserved word as key and true as value.
]]
reserved = { }
do local list = { "and", "break", "do", "else", "elseif",
                  "end", "false", "for", "function", "if",
                  "in", "local", "nil", "not", "or", "repeat",
                  "return", "then", "true", "until", "while",
                }
  for _, w in pairs(list) do reserved[w] = true end
end

----------------------------------------------------------------

__doc.image = [[function(v) returns string or calls error()
Returns a string which, if evaluated by a Lua interpreter,
re-creates a value isomorphic to v.  There are restrictions:

  - v may be composed only of tables, numbers, 
    booleans, strings, and nil

  - the reconstruction does not preserve sharing or metatables

  - there must be no cycles in v

Calls violating these restrictions will fail by calling error() 
or (in the case of cycles).
]]

function image(v, n, visited)
  visited = visited or { }
  local parts = { }
  local function add(...)
    for i = 1, select('#', ...) do
      parts[#parts+1] = select(i, ...)
    end
  end

  local images = { 
    ['nil'] = function(x) add 'nil'                     end,
    number  = function(x) add (tostring(x))             end,
    boolean = function(x) add (tostring(x))             end,
    string  = function(x) add (string.format('%q', x))  end,
  }
  local function add_keyimage(k)
    if type(k) == 'string' and string.find(k, '^%a[%w_]*$') and not reserved[k] then
      add(k)
    else
      add('[ ', image(k, ''), ' ]')
    end
  end

  function images.table(x, n, visited)
    if visited[x] then error('Tried to image a cyclic table') end
    visited[x] = true
    add '{ '
    local pfx = ''
    local listed = { }
    for i = 1, #x do
      add(pfx)
      pfx = ', '
      add(image(x[i], n, visited))
      listed[i] = true
    end
    local pfx = '\n' .. n .. '  '
    for k, v in pairs(x) do
      if not listed[i] then
        add(pfx)
        add_keyimage(k)
        add(' = ', image(v, n .. '  '), ', ')
      end
    end
    add('\n' .. n .. '}')
  end

  local f = images[type(v)]
  if not f then error('Cannot write image of value of type ' .. type(v)) end
  f(v, n or '', visited)
  return table.concat(parts)
end



----------------------------------------------------------------
__doc.sum = [[function(list) returns number
Takes a (possibly empty) list of numbers and returns their sum.
Crashes if an element of the list cannot be added to the sum.
]]

function sum(l)
  local sum = 0
  for i = 1, #l do sum = sum + l[i] end
  return sum
end
----------------------------------------------------------------
__doc.die = [[function(...) Writes(..., '\n') to output.error and calls output.exit.]]

--- Die with a fatal error message
function die(...)
  local ok, log = pcall(require, _PACKAGE .. 'log')
     -- cannot require log until util is fully loaded
  if ok then
    pcall(log.lua, 'die', log.dt { err = table.concat { ... } })
  end
  local pfx = progname and progname:gsub([=[^.*[\/]]=], '') .. ': ' or ''
  output.error:writeln(pfx, ...)
  output.exit()
end

__doc.progname = [[String containing the name of the current program.
Used in error messages from util.die.]]

__doc.dief = [[function(...) return util.die(string.format(...)) end]]
      dief =   function(...) return      die(string.format(...)) end

__doc.checkf = [[function(v, ...) may print error message and exit
If v is nil or false, calls util.die(string.format(...)); otherwise returns v.]]

function checkf(v, ...)
  if not v then die(string.format(...)) else return v end
end

__doc.errorf = [[function(...) applies string.format and then error]]
function errorf(...)
  local log = require (_PACKAGE .. 'log') -- cannot require until util is fully loaded
  local s = string.format(...)
  pcall(log.lua, 'error', log.dt { err = s })
  error(s, 2)
end

__doc.insist = [[function(v, msg) if v == nil calls error(msg) otherwise returns v]]
function insist(v, msg)
  if v == nil then error(msg, 2) else return v end
end

__doc.insistf = [[function(v, ...) returns arguments
if v is false or nil, calls util.errorf(...);
otherwise returns v, ... (acting as identity function)]]
function insistf(p, ...)
  if not p then return errorf(...) else return p, ... end
end

__doc.validate = [[function(...) returns ... or kills process
Used in place of 'assert' where a function might return nil, error
but we expect this never to happen.  If first arg is nil, calls
util.die() with the remaining arguments.  Otherwise, just acts like
the identity function, passing all arguments through as results.

Normally should be used only to call builtin Lua functions, as our
own functions call error or lua_error in case of errors.]]

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

__doc.table_sorted_keys   = [[Return sorted list of keys in a table.]]
__doc.table_sorted_values = [[Return sorted list of values in a table.]]

function table.sorted_keys(t, lt)
  local l = { }
  for k in pairs(t) do
    table.insert(l, k)
  end
  table.sort(l, lt)
  return l
end
table_sorted_keys = table.sorted_keys

function table.sorted_values(t, lt)
  local l = { }
  for _, v in pairs(t) do
    table.insert(l, v)
  end
  table.sort(l, lt)
  return l
end
table_sorted_values = table.sorted_values

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
  s = s:gsub('(%A)(%a)', function(nl, let) return nl .. string.upper(let) end)
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
    error(s .. ' does not represent a number of bytes')
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
  s = s:gsub("([\128-\255=])", qpsubst)
  local lines = { } -- accumulate lines of output
  for l in string.gmatch(string.find(s, '\n$') and s or s .. '\n', '(.-)\n') do
    l = l:gsub('(%s)$', qpsubst) -- quote space at end of line
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
__doc.string_splits = ([[function(s, pat) returns iterator
Splits string 's' into pieces separated by strings matching 'pat'.
Iterates over the pieces and the separators (or captures if
'pat' contains captures).  Usage:

  for between, cap1, ... in %s.string_splits(s, pat) do
    ...
  end

]]):format(modname)

function string_splits(self, pat)
  local st, g = 1, self:gmatch("()("..pat..")")
  local function getter(seg_start, seps, sep, cap1, ...)
    st = sep and seps + #sep
    return self:sub(seg_start, (seps or 0) - 1), cap1 or sep, ...
  end
  return function() if st then return getter(st, g()) end end
end
----------------------------------------------------------------
--- html support
__doc.html = [[html support functions.]]

html = { }
do
  local quote = { ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;', ['"'] = '&quot;' }

  __doc['html.of_ascii'] = [[function(s) quotes special html chars.]]
  function html.of_ascii(s)
    return (string.gsub(s, '[%&%<%>%"]', quote))
  end

  __doc['html.qp_to_html'] = [[function(qp) converts qp char to html numeric
representation: '=%x%x' => '&#%d%d%d;'.]]
  function html.qp_to_html(qp)
    return
     qp and ((qp == '20' and ' ') -- allow spliting on spaces
              or
            string.format('&#%d;', tonumber('0x' .. qp)))
       or
     nil
  end

  __doc['html.of_quoted_printable'] = [[function(s) encodes quoted printable strings into html.]]
  function html.of_quoted_printable(s)
    return (s:gsub('=(%x%x)', html.qp_to_html):gsub('_', ' '))
  end

  __doc['html.of_iso_8859_1_or_utf8'] = [[function(s) converts iso-8859-1 or UTF-8 encoded strings to html.]]
  function html.of_iso_8859_1_or_utf8(charset, enc, s)
    enc = string.upper(enc)
    charset = string.upper(charset)
    local r
    if string.find(charset, '^ISO%-8859%-') then
      if enc == 'B' then -- base64
        r, s = pcall(core.b64decode, s)
        s = r and html.of_ascii(s) or nil
      elseif enc == 'Q' then   -- quoted-printable
        s = html.of_ascii(s)
        s = html.of_quoted_printable(s)
      end
    elseif charset == 'UTF-8' then
      if enc == 'B' then -- base64
        r, s = pcall(core.b64decode, s)
        if r then
          r, s = pcall(core.utf8tohtml, s)
          if not r then
            log(s)
            s = nil
          end
        else
          log(s)
          s = nil
        end
      elseif enc == 'Q' then   -- quoted-printable
        s = string.gsub(s, '=(%x%x)',
          function (x) return string.char(tonumber('0x' .. x)) end)
        r, s = pcall(core.utf8tohtml, s)
        s = r and s or nil
      end
    else
      return nil
    end
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
do

  local seconds = { s = 1, sec = 1, second = 1,
                    min = 60, minute = 60,
                    hour = 60 * 60, hr = 60 * 60 }
  seconds.day   =  24 * seconds.hour
  seconds.week  =   7 * seconds.day
  seconds.month =  30 * seconds.day
  seconds.year  = 365 * seconds.day

  local base_units = table_sorted_keys(seconds)
  local understood = table.concat(base_units, ", ")

__doc.to_seconds = [[function(number, units)
Converts the number of units of time to seconds.
Understands these units and their plurals:
  ]] .. understood

  for _, k in pairs(base_units) do
    if k ~= 's' then
      seconds[k .. 's'] = seconds[k]
    end
  end

  function to_seconds(number, units)
    if not seconds[units] then
      for k, v in pairs(seconds) do print(k, v) end
      error('Unknown unit of time ' .. units)
    else
      return number * seconds[units]
    end
  end
end

----------------------------------------------------------------

__doc.localtime_minus_UTC = [[function(timestamp) returns the difference
in seconds between local time and UTC at a given time or, if not given,
at current time.

timestamp is the time in seconds since Unix epoch, for which the difference
is calculated. If timestamp is not given, current time is used.]]

function localtime_minus_UTC(timestamp)
  timestamp = timestamp or os.time()
  assert(type(timestamp) == 'number')
  local t = os.date('*t', timestamp)
  t.isdst = false -- don't cancel DST difference when converting back
                  -- to Unix time
  return os.difftime(os.time(t), os.time(os.date('!*t', timestamp)))
end

----------------------------------------------------------------

__doc.whereis = [[function(cmd) returns string or nil.
Looks command cmd up in the program search path and returns the command's
full path or nil if not found.i
]]

local PATH = os.getenv 'PATH' or ''
function whereis(cmd)
  if type(cmd) ~= 'string' then return nil end
  for p in string.gmatch(PATH, '[^:]+') do
    if file_is_readable(p .. slash .. cmd) then
      return p .. slash .. cmd
    end
  end
  return nil
end

-- adapted from code posted on the Lua list:
--  * Subject: Re: Lua / shell - How to "pipe" commands in os.execute() ?
--  * From: Asko Kauppi <askok@...>
--  * Date: Wed, 4 Apr 2007 15:22:45 +0300

__doc.get_popen = [[function(cmd) returns string, 0 or nil, status code.
Returns the output of the execution of cmd and the status of the execution.
Trailing spaces are removed from the returned string.
]]

function get_popen(cmd)
  if type(cmd) ~= 'string' then return nil, -255 end
  local str, rc = nil, -255
  local f = io.popen(cmd .. " ; echo RC=$?")
  if f then
    str = f:read('*a')
    f:close()
    str, rc = string.match(str, '(.*)RC=(%d+)%s*$')
    -- remove trailing spaces
    str = string.gsub(str, '%s*$', '')
    rc = tonumber(rc) or -99
    if rc ~= 0 then str = nil end
  end
  return str, rc
end

__doc.local_rightid = [[function() returns string.
Returns the fully qualified host name. If the domain name is not found
appends '.osbf.lua' to the host name. If neither the host name nor
the domain name is found, returns 'spamfilter.osbf.lua'.
]]

do
  local cache -- fork all these processes at most once

  function local_rightid()
    if not cache then
      local domain_cmd = whereis('dnsdomainname') or whereis('domainname')
      local host_cmd  = whereis('hostname')
      local hostname =
        host_cmd and get_popen(host_cmd) or 'spamfilter'
      local domainname =
        domain_cmd and get_popen(domain_cmd) or _PACKAGE .. 'lua'
      cache = hostname .. '.' ..  domainname
    end
    return cache
  end
end

__doc.generate_pwd = [[function() returns a random password with 32 hex
chars. The password is generated using output.generate_hex_string.]]

function generate_pwd()
  return output.generate_hex_string(32)
end


__doc.tmpname = [[function(prefix) returns a unique file name.
prefix = optional string. If not given, returns os.tmpname() else
returns prefix appended with a random string with 32 hex chars.
]]

function tmpname(prefix)
  if not prefix then
    return os.tmpname()
  end
  if type(prefix) ~= 'string' then
    error('Invalid arg to tmpname - expecting string')
  end
  local name
  for i= 1, 1000 do
    name = prefix .. output.generate_hex_string(32)
    local h = io.open(name, 'r')
    if not h then
      h = io.open(name, 'w')
      if h then
        io.close(h)
        return name
      else
        return nil, 'cannot create tmpfile: ' .. name
      end
    end
    close(h)
  end
  return nil, 'max attempts to create tmpfile exceeded'
end

--------------------------------------------------------------------------
__doc.file_contents = [[function(filename) returns string or calls error
Returns the contents of the specified file or calls error().]]

function file_contents(filename)
  local f, msg = io.open(filename)
  if not f then
    error(filename .. ': ' .. msg)
  else
    local contents = assert(f:read '*a')
    f:close()
    return contents
  end
end
