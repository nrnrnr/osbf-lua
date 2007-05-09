local assert, ipairs, pairs, require, tostring
    = assert, ipairs, pairs, require, tostring

local package, string, os, table
    = package, string, os, table

local prog = _G.arg and _G.arg[0] or 'OSBF'

module (...)

version = '0.99'

local d       = require (_PACKAGE .. 'default_cfg')
local util    = require (_PACKAGE .. 'util')
local options = require (_PACKAGE .. 'options')
local boot    = require (_PACKAGE .. 'boot')
local core    = require (_PACKAGE .. 'core')


--- put default configuration in my configuration
for k, v in pairs(d) do
  _M[k] = v
end

local default_pwd = assert(d.pwd)

__doc = __doc or { }
__doc.version = "OSBF-Lua version."
__doc.slash = "Holds the detected OS slash char, '/' or '\\'."
 
slash = assert(string.match(package.path, [=[[\/]]=]))

--- XXX could we get rid of this and make all of config read-only
--- except changeable via 'load'?

__doc.constants = "Constants used by OSBF-Lua"

constants = util.table_read_only
  {
    classify_flags            = 0,
    count_classification_flag = 2,
    learn_flags               = 0,
    mistake_flag              = 2,
    reinforcement_flag        = 4,
    default_db_megabytes      = 1.08332062 -- 94321 buckets by default
  }

__doc.text_limit = [[Initial length of a message to be used in
classifications and learnings.]]

text_limit = 100000

__doc.load = [[function(filename)
Loads a config file.
]]

function load(filename)
  local config, err = util.protected_dofile(filename)
  if not config then return nil, err end
  for k, v in pairs(config) do
    if d[k] == nil then
      util.die(prog, ': fatal error - configuration "', tostring(k),
               '" cannot be set by a user')
    else
      _M[k] = v
    end
  end
  return true
end

__doc.load_if_readable = [[function(filename)
Loads a config file if readable.
Normally used to load user's config file.
]]

function load_if_readable(filename)
  if util.file_is_readable(filename) then
    return load(filename)
  else
    return true
  end
end

---------------- options

local val, bool, opt, dir =
  options.std.val, options.std.bool, options.std.opt, options.std.dir

local uhelp = [[
  --udir=<user_dir> 
        set  the  user  directory,  where  its  osbf-lua  configuration,
        databases,  lists and log files  are located.  The  location  of
        these files can also be set individually, see the options below.
]]
local dbhelp = [[
  --dbdir=<database_dir>
        specify a  location for the  database files different  than that
        specified with --udir.
]]
local cfhelp = [[
  --config=<config-file>
        specify a configuration file different from config.lua in the
        directory specified with --udir.
]]
local lhelp = [[
  --listdir=<list_dir>
        specify  a  location  for  the  list  files,  whitelist.lua  and
        blacklist.lua, different than that specified with --udir.
]]
local chelp = [[
  --cachedir=<cache-dir>
        specify a directory in which to cache messages for possible later training;
        defaults to the $udir/cache
]]


local opts = {
  { type = dir, long = 'udir', usage = "=<dir>      # User's OSBF-Lua directory", help = uhelp },
  { type = val, long = 'config', usage = "=<file>   # Configuration file", help = cfhelp },
  { type = dir, long = 'dbdir', usage = "=<dir>     # Database directory", help = dbhelp },
  { type = dir, long = 'listdir', usage = "=<dir>   # Directory for blacklist, whitelist",
    help = lhelp },
  { type = dir, long = 'cachedir', usage = "=<dir>  # Directory for message cache", help = chelp},
}

for _, o in ipairs(opts) do options.register(o) end

--------------------------------------------

--- directories

__doc.dirs = [[Table with system dirs:
dirs.udir     - User's OSBF-Lua directory. Defaults to $HOME/.osbf-lua.
dirs.dbdir    - Database directory. Defaults to dirs.udir.
dirs.listdir  - Directory for blacklist and whitelist. Defaults to dirs.udir.
dirs.cachedir - Directory for message cache. Defaults to dirs.udir/cache.
]]

dirs = { }

__doc.configfile = [[Configuration file; initialized by set_dirs.
Defaults to dirs.udir/config.lua.]]

configfile = nil -- initialized by set_dirs

__doc.set_dirs = [[function(options, no_dirs_ok)
Sets directories used by OSBF-Lua to command-line option values
or default values.
If no_dirs_ok is false, all dirs, given or default, are checked for
existance. In that case, the program exits with error if any doesn't exist.
]]

function set_dirs(options, no_dirs_ok)
  local HOME = os.getenv 'HOME'
  local default_dir = HOME and table.concat { HOME, slash, '.osbf-lua' }
  options = options or { }
  dirs.user = options.udir or (no_dirs_ok or core.is_dir(default_dir)) and default_dir

  if not dirs.user then
    util.die('No --udir option given and ', default_dir, ' is not a directory.\n',
             'To create it, run\n  ', prog, ' init\n')
  end

  dirs.database = options.dbdir    or dirs.user
  dirs.lists    = options.listsdir or dirs.user

  for k in pairs(dirs) do dirs[k] = util.append_slash(dirs[k]) end

  configfile = options.config   or dirfilename('user', 'config.lua')
  dirs.cache = options.cachedir or util.append_slash(dirs.user .. "cache")
  dirs.log   = util.append_slash(dirs.user .. 'log')

  -- validate that everything is a directory

  if not no_dirs_ok then
    for name, dir in pairs(dirs) do
      if not core.is_dir(dir) then
        util.die('The ', name, ' path ', dir, ' is not a directory')
      end
    end
  end
end


__doc.dirfilename = [[function(dir, filename, suffix)
Returns a filename in particular directory of table dirs.
Suffix is used primarily to deal with sfid suffixes.
]]

function dirfilename(dir, basename, suffix)
  suffix = suffix or ''
  local d = assert(dirs[dir], dir .. ' is not a valid directory indicator')
  return d .. basename .. suffix
end

----------------------------------------------------------------
__doc.password_ok = [[function()
Returns true if password in user config file is OK or nil, errmsg.
]]

function password_ok()
  if pwd == default_pwd then
    return nil, 'Default password still used in ' .. configfile
  elseif string.find(pwd, '%s') then
    return nil, 'password in ' .. configfile .. ' contains whitespace'
  else
    return true
  end
end

__doc.init = [[function(options, no_dirs_ok)
Sets OSBF-Lua directories, databases and loads user's config file.
]]

__doc.dbset = "Table with database info."
local function init(options, no_dirs_ok)
  set_dirs(options, no_dirs_ok)
  dbset = {
    classes = {dirs.database .. ham_db,
               dirs.database .. spam_db},
    ncfs    = 1, -- split "classes" in 2 sublists. "ncfs" is
                 -- the number of classes in the first sublist.
    delimiters = extra_delimiters or '',
    ham_index = 1,
    spam_index    = 2,
  }
  util.validate(load_if_readable(configfile))
end

boot.initializer(init)
