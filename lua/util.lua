local require, print, pairs, type, assert, loadfile, setmetatable, package =
      require, print, pairs, type, assert, loadfile, setmetatable, package

local io, string, table, os =
      io, string, table, os

module(...)

local packagename = string.gsub(_PACKAGE, '%.$', '')
local osbf = require(packagename)
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
		      assert(false, "attempt to change a constant value")
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
  local basename = append_slash(packagename) .. subname
  for p in string.gmatch (package.path, '[^;]+') do
    local path = string.gsub(p, '%?', basename)
    if file_is_readable(path) then
      return path
    end
  end
  return nil, "Submodule " .. subname .. " not found"
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


options = { }
function options.val(key, value, args)
  if value ~= '' then
    return value
  elseif #args > 0 then
    return table.remove(args, 1)
  else
    return nil, "missing argument for option " .. key
  end
end
function options.dir(key, value, args)
  local v, err = options.val(key, value, args)
  if not v then
    return v, err
  elseif osbf.core.is_dir(v) then
    return v
  else
    return nil, v .. ' is not a directory'
  end
end
function options.optional(key, value, args)
  return value
end
function options.bool(key, value, args)
  if value ~= '' then
    return nil, 'Option ' .. key .. ' takes no argument'
  else
    return true
  end
end
local function no_such_option(key, value, args)
    if key == '' and value then
      return nil, 'Missing option name before "="'
    end
    return nil, 'Unknown option: ' .. key
end

-- simple getopt to get command line options
function getopt(args, opt_table)
  local options_found = {}

  while(args[1]) do
    -- changed + to * to allow forced end of options with "--" or "-"
    local key, eq, value = string.match(args[1], "^%-%-?([^=]*)(=?)(.*)")
    if value == '' then value = eq end
    if not key or key == '' and value == '' and table.remove(args, 1) then
      break -- no more options
    else
      table.remove(args, 1)
      local val, err = (opt_table[key] or no_such_option)(key, value, args)
      if err then return nil, err end
      options_found[key] = val
    end
  end
  return options_found, args
end

-- append slash if missing
function append_slash(path)
  if path then
    if string.sub(path, -1) ~= "/" then
      return path .. "/"
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

-- give a filename in particular directory
-- suffix is used primarily to deal with sfid suffixes
function dirfilename(dir, basename, suffix)
  suffix = suffix or ''
  local d = assert(osbf.dirs[dir], dir .. ' is not a valid directory indicator')
  return d .. basename .. suffix
end

----------------------------------------------------------------
function password_ok()
  if osbf.cfg.pwd == osbf.cfg.default.pwd then
    return nil, "Default password still used in " .. dirfilename('config', 'config.lua')
  elseif string.find(osbf.cfg.pwd, '%s') then
    return nil, "password in " .. dirfilename('config', 'config.lua') .. ' contains whitespace'
  else
    return true
  end
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

  
