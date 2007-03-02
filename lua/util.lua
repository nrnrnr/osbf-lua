local require, print, pairs, type, io, string, table =
      require, print, pairs, type, io, string, table

module(...)

--- Special tables.
-- Metafunction used to create a table on demand.
local function table__index(t, k) local u = { }; t[k] = u; return u end
function table_tab(t)
  setmetatable(t, { __index = table__index })
  return t
end



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
      if error then return error end
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
