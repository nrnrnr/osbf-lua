-- registration of options and their parsing

local table, string, require, assert, ipairs =
      table, string, require, assert, ipairs

module(...)
local core = require (_PACKAGE .. 'core')

---- standard kinds of options we recognize:
-- value required, directory required, value optional , boolean

-- each is represented as a higher-order function to be used during parsing

std = { }
function std.val(key, value, args)
  if value ~= '' then
    return value
  elseif #args > 0 then
    return table.remove(args, 1)
  else
    return nil, 'missing argument for option ' .. key
  end
end
function std.dir(key, value, args)
  local v, err = std.val(key, value, args)
  if not v then
    return v, err
  elseif core.is_dir(v) then
    return v
  else
    return nil, 'Path ' .. v .. ' given for option --' .. key .. ' is not a directory'
  end
end
function std.optional(key, value, args)
  return value
end
function std.bool(key, value, args)
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

local default = std.bool -- default type if not specified at registration

local parsers = { }
usage, help = { }, { }

function register(t)
  local long = t.long
  assert(not t.short, "Short options not supported yet")
  assert(parsers[long] == nil, "Duplicate registration of a long option")
  parsers[long] = t.type or default
  assert(usage[long] == nil)
  usage[long] = t.usage
  assert(help[long] == nil)
  help[long] = t.help
end

-- simple getopt to get command line options
function parse(args, options)
  options = options or parsers
  local found = {}

  while(args[1]) do
    -- changed + to * to allow forced end of options with "--" or "-"
    local key, eq, value = string.match(args[1], '^%-%-?([^=]*)(=?)(.*)')
    if eq == '=' and value == '' then
        return nil, 'option ' .. args[1] .. ' is ambiguous'
    end
    if not key or key == '' and value == '' and table.remove(args, 1) then
      break -- no more options
    else
      table.remove(args, 1)
      local val, err = (options[key] or no_such_option)(key, value, args)
      if err then return nil, err end
      found[key] = val
    end
  end
  return found, args
end

