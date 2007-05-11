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
function encode_quoted_printable(s) return s end -- totally bogus
--[====[
do
  local quoted_printable_table = { ['='] = '3D', [' '] = '20', }

  function encode_quoted_printable(text, len)
    local limited_text = ""
    if len < 5 then len = 5 end
    if not string.find(text, '\n$') then
      text = text .. "\n"
    end
    local ilen = len - 3 -- reserve space for final =20 or final "=\n"
    for l in string.gmatch(text, "(.-\n)") do
      local lines = split_lines(stl, ilen)
      local ll = string.len(l)
      if ll > ilen then
        local first = string.sub(l, 1, ilen)
        local first = string.match(string.sub(l, 1, ilen), "^(.+[^=][^=])")
        ilen = string.len(first)
        if string.sub(first, -1) == " " then
          limited_text = limited_text ..
            string.sub(first, 1, ilen-1) .. "=20\n" ..
            limit_lines(string.sub(l, ilen+1), len)
        else
          limited_text = limited_text ..
            first .. "=\n" ..
            limit_lines(string.sub(l, ilen+1), len)
        end
      else
        l = string.gsub(l, " \n", "=20\n")
        l = string.gsub(l, "\t\n", "=09\n")
        limited_text =  limited_text .. l
      end
    end
    return limited_text
  end
end
]====]
