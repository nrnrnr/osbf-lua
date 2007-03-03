local require, print, pairs, type, assert, loadfile, setmetatable =
      require, print, pairs, type, assert, loadfile, setmetatable

local io, string, table =
      io, string, table

module(...)

local osbf = require(string.gsub(_PACKAGE, '%.$', ''))

--- Special tables.
-- Metafunction used to create a table on demand.
local function table__index(t, k) local u = { }; t[k] = u; return u end
function table_tab(t)
  setmetatable(t, { __index = table__index })
  return t
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

-- simple getopt to get command line options
function getopt(args, opt_table)
  local error = nil
  local options_found = {}

  while(args[1]) do
    local key, value = string.match(args[1], "^%-%-?([^=]+)=?(.*)")
    if not key then
      break -- no more options
    else
      table.remove(args, 1)
      options_found, error = (opt_table[key] or no_such_option)(key, value, args)
      if error then return nil, error end
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

-- give a filename in particular directory

function dirfilename(dir, basename, suffix)
  suffix = suffix or '.lua'
  local d = assert(osbf.dirs[dir], dir .. ' is not a valid directory indicator')
  return d .. basename .. suffix
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

  
