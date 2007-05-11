local require, print, pairs, type, assert, loadfile, setmetatable, tonumber =
      require, print, pairs, type, assert, loadfile, setmetatable, tonumber

local io, string, table, os, package =
      io, string, table, os, package

module(...)

local core = require(_PACKAGE .. 'core')

----------------------------------------------------------------
--- Special tables.
-- Metafunction used to create a table on demand.
local function table__index(t, k) local u = { }; t[k] = u; return u end
function table_tab(t)
  setmetatable(t, { __index = table__index })
  return t
end

-- Function to make a table read-only
function table_read_only(t)
  local proxy = {}
  setmetatable(proxy, { __index = t,
		    __newindex = function(t, k, v)
		      assert(false, 'attempt to change a constant value')
		    end
		  })
  return proxy
end
----------------------------------------------------------------
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
-- check if file exists before "doing" it
function protected_dofile(file)
  local f, err_msg = loadfile(file)
  if f then
    return f() --- had better return non-false, non-nil
  else
    return f, err_msg
  end
end
----------------------------------------------------------------
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

function mkdir(path)
  if not core.is_dir(path) then
    local rc = os.execute('mkdir ' .. path)
    if rc ~= 0 then
      die('Could not create directory ', path)
    end
  end
end

----------------------------------------------------------------

--- Die with a fatal error message
function die(...)
  io.stderr:write(...)
  io.stderr:write('\n')
  os.exit(2)
end

--- Validate arguments.
-- If the first argument is nil, the second is a fatal error message.
-- Otherwise this function passes all its args through as results,
-- so it can be used as an identity function.  (Provided it gets at
-- list one arg.)
function validate(first, ...)
  if first == nil then
    die((...)) -- only second arg goes to die()
  else
    return first, ...
  end
end


----------------------------------------------------------------

function contents_of_file(path)  --- returns contents as string or nil, error
  local f, err = io.open(path, 'r')
  if f then
    local s = f:read '*a'
    return s
  else
    return nil, err
  end
end

----------------------------------------------------------------



-- local definition requires because util must load before cfg

local slash = assert(string.match(package.path, [=[[\/]]=]))

-- append slash if missing
function append_slash(path)
  if path then
    if string.sub(path, -1) ~= slash then
      return path .. slash
    else
      return path
    end
  else
    return nil
  end
end

function append_to_path(path, file)
  return append_slash(path) .. file
end

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
local split_qp_at

function encode_quoted_printable(s, max_width)
  s = string.gsub(s, "([\128-\255=])", function (c)
          return string.format("=%02X", string.byte(c))
        end)
  local lines = { }
  if not string.find(s, '\n$') then s = s .. '\n' end
  for l in string.gmatch(s, '(.-)\n') do
    repeat
      first, rest = split_qp_at(l, max_width)
      table.insert(lines, first)
      l = rest
    until l == nil
  end
  table.insert(lines, '')
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
