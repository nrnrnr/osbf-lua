local require, print, pairs, type, assert, loadfile, setmetatable, tonumber =
      require, print, pairs, type, assert, loadfile, setmetatable, tonumber

local io, string, table, os, package =
      io, string, table, os, package

module(...)

local core = require(_PACKAGE .. 'core')

__doc = { }

----------------------------------------------------------------
--- Special tables.
-- Metafunction used to create a table on demand.
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
__doc.die = [[function(...) kills process
Writes all arguments to io.stderr, then newline,
then calls os.exit with nonzero exit status.]]

--- Die with a fatal error message
function die(...)
  io.stderr:write(...)
  io.stderr:write('\n')
  os.exit(2)
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

--- Return sorted list of keys in a table.
function table.sorted_keys(t, lt)
  local l = { }
  for k in pairs(t) do
    table.insert(l, k)
  end
  table.sort(l, lt)
  return l
end

function case_lt(s1, s2)
  local l1, l2 = string.lower(s1), string.lower(s2)
  return l1 == l2 and s1 < s2 or l1 < l2
end

  
--- Put string into typical form for RFC 822 header.
function capitalize(s)
  s = '_' .. string.lower(s)
  s = string.gsub(s, '(%A)(%a)', function(nl, let) return nl .. string.upper(let) end)
  return string.sub(s, 2)
end


----------------------------------------------------------------

--- return a string as number of bytes


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

-- splits a line that's too long, quoting the newline with =
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

html = { }
do
  local quote = { ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;', ['"'] = '&quot;' }

  function html.of_ascii(s)
    return string.gsub(s, '[%&%<%>%"]', quote)
  end

  -- '=%x%x' => '&#%d%d%d;'
  function qp_to_html(qp)
    return
     qp and string.format('&#%d;', tonumber('0x' .. qp))
       or
     nil
  end

  function html.of_iso_8859_1(s)
    s = string.gsub(s, '=(%x%x)', qp_to_html)
    s = string.gsub(s, '_', '&nbsp;')
    return s
  end

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
