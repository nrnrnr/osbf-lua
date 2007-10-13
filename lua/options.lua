-- registration of options and their parsing

local table, string, require, assert, ipairs, error =
      table, string, require, assert, ipairs, error

module(...)
local core = require (_PACKAGE .. 'core')

---- standard kinds of options we recognize:
-- value required, directory required, value optional , boolean

-- each is represented as a higher-order function to be used during parsing

__doc = {
  std = [[table of option types:
val   - an option that must take an argument
dir   - an option that must take an existing directory as argument
bool  - an option that is either present or not; it takes no argument
]],

  register = [[function {long = string, type = type, usage = string, help = string}
Registers a command-line option used by the main program.
  long  - The long name of the option (short options aren't supported)
  type  - The type of the option, from the option.std table
  usage - A usage line for the option (optional)
  help  - A long help text for the option (optional)
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
    error('missing argument for option ' .. key)
  end
end
function std.dir(key, value, args)
  local v, err = std.val(key, value, args)
  if not v then
    return v, err
  elseif core.isdir(v) then
    return v
  else
    error('Path ' .. v .. ' given for option --' .. key .. ' is not a directory')
  end
end
function std.bool(key, value, args)
  if value ~= '' then
    error('Option ' .. key .. ' takes no argument')
  else
    return true
  end
end
local function no_such_option(key, value, args)
    if key == '' and value then
      error('Missing option name before "="')
    end
    error('Unknown option: ' .. key)
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
      error('option ' .. args[1] .. ' is ambiguous')
    end
    if not key or key == '' and value == '' and table.remove(args, 1) then
      break -- no more options
    else
      table.remove(args, 1)
      found[key] = (options[key] or no_such_option)(key, value, args)
    end
  end
  return found, args
end

