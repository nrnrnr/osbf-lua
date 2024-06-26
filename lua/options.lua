-- registration of options and their parsing
--
-- See Copyright Notice in osbf.lua

local io = io -- debugging

local table, string, os, require, assert, ipairs, pairs, tonumber, error =
      table, string, os, require, assert, ipairs, pairs, tonumber, error

module(...)
local core = require (_PACKAGE .. 'core')
local util = require (_PACKAGE .. 'util')

---- standard kinds of options we recognize:
-- value required, directory required, value optional , boolean

-- each is represented as a higher-order function to be used during parsing

__doc = {
  std = [[table of option types:
val   - an option that must take an argument
num   - an option that must take a number as an argument
dir   - an option that must take an existing directory as argument
bool  - an option that is either present or not; it takes no argument
]],

  register = [[function {long = string, type = type, usage = string, help = string}
Registers a command-line option used by the main program.
  long  - The long name of the option (short options aren't supported)
  type  - The type of the option, from the option.std table (defaults to bool)
  usage - A usage line for the option (optional)
  help  - A long help text for the option (optional)
  env   - Environment variable used as the value of the option if not given (optional)
]],

  help  = [[a table of long help texts indexed by option]],
  usage = [[a table of usage lines indexed by option]],

}
__doc.__order = { 'std', 'parse', 'register' }

std = { }
function std.val(key, value, args)
  if value ~= '' then
    return value
  elseif #args > 0 then
    return table.remove(args, 1)
  else
    util.die('missing argument for option ' .. key)
  end
end
function std.num(key, value, args)
  return util.checkf(tonumber(std.val(key, value, args)),
                     'argument for option -%s must be a number', key)
end
function std.dir(key, value, args)
  local v, err = std.val(key, value, args)
  if not v then
    return v, err
  elseif core.isdir(v) then
    return v
  else
    util.die('Path ' .. v .. ' given for option --' .. key .. ' is not a directory')
  end
end
function std.bool(key, value, args)
  if value ~= '' then
    util.die('Option ' .. key .. ' takes no argument')
  else
    return true
  end
end
local function no_such_option(key, value, args)
    if key == '' and value then
      util.die('Missing option name before "="')
    end
    util.die('Unknown option: ' .. key)
end

local default = std.bool -- default type if not specified at registration

local parsers = { }
usage, help, env_default = { }, { }, { }

function register(t)
  local long = t.long
  assert(not t.short, "Short options not supported yet")
  assert(parsers[long] == nil, "Duplicate registration of a long option")
  parsers[long] = t.type or default
  assert(usage[long] == nil)
  usage[long] = t.usage
  assert(help[long] == nil)
  help[long] = t.help
  if t.env then 
    env_default[long] = os.getenv(t.env)
  end
end

----------------------------------------------------------------
__doc.parse = [[function(args, [opt_tab]) returns option table, arg list
'opt_tab', if present, is a table mapping long names to option types.
If absent, the parser uses the table created by 'options.register'.
The function parses the list of args, peeling off options and
returning a table of their values, plus any remaining arguments.  The
syntax of an option may be any of the following:

  --name=value
  -name=value
  --name value
  -name value
  --name
  -name

Whether a value is expected depends on the type of the option.

The function reads --multi-part-name as --multi_part_name.

The end of options may be forced with -- or -.  

XXX   Things that are bogus   XXX
We may one day want - to mean standard input.
The wild diversity of syntax represents needless complexity.
How about if we pick standard Unix long-option syntax (-name value)
and stick with it?]]

function parse(args, options)
  options = options or parsers
  local found = {}

  while(args[1]) do
    -- changed + to * to allow forced end of options with "--" or "-"
    local key, eq, value = string.match(args[1], '^%-%-?([^=]*)(=?)(.*)')
    if eq == '=' and value == '' then
      util.die('option ' .. args[1] .. ' is ambiguous')
    end
    if not key or args[1] == '-' then
      break -- no more options
    else
      key = key:gsub('-', '_')
      table.remove(args, 1)
      found[key] = (options[key] or no_such_option)(key, value, args) or true
    end
  end
  for k, f in pairs(options) do
    if not found[k] and env_default[k] then
      found[k] = env_default[k]
    end
  end
  return found, args
end

