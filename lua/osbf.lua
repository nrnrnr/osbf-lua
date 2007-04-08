-- exports:
-- osbf.init
-- osbf.std_opts
-- submodules


local require, print, pairs, ipairs, type, io, string, table, os, _G =
      require, print, pairs, ipairs, type, io, string, table, os, _G

local modname = ...

module(modname)

dirs = { } -- must come before loading submodules

local submodules =
  { 'core', 'util', 'lists', 'commands', 'mail_commands', 'cfg', 'command_line',
    'msg', 'learn' }

for _, submodule in ipairs(submodules) do
  require (modname .. '.' .. submodule)
end

local val, bool, opt, dir =
  util.options.val, util.options.bool, util.options.opt, util.options.dir

std_opts = 
	{ udir = dir, learn = val, unlearn = val, classify = bool,
	  score = bool, cfdir = dir, dbdir = dir, listdir = dir, source = val,
	  output = val, help = bool}


--- Set osbf.dirs.  
-- @param The first result of util.getopt (an options table).
function set_dirs(options, no_dirs_ok)
  local HOME = os.getenv 'HOME'
  local default_dir = HOME and HOME .. '/.osbf-lua' 
  options = options or { }
  dirs.user = options.udir or (no_dirs_ok or core.is_dir(default_dir)) and default_dir

  if not dirs.user then
    util.die('No --udir option given and ', default_dir, ' is not a directory.\n',
             '<eventually provide a command-line "osbf init" to create the ',
             'directory and fix the problem>')
  end

  dirs.config   = options.cfgdir   or dirs.user
  dirs.database = options.dbdir    or dirs.user
  dirs.lists    = options.listsdir or dirs.user

  for k in pairs(dirs) do dirs[k] = util.append_slash(dirs[k]) end

  dirs.cache = dirs.user .. "cache/"
  dirs.log = dirs.user .. 'log/'

  -- validate that everything is a directory

  if not no_dirs_ok then
    for _, dir in pairs(dirs) do
      if not core.is_dir(dir) then
        util.die(dirs.user, ' is not a directory')
      end
    end
  end

  return dirs
end

function init(options, no_dirs_ok)
  cfg.constants = util.table_read_only (cfg.constants)
     --- can't make it read-only until both cfg and util are loaded

  set_dirs(options, no_dirs_ok)
  cfg.dbset = {
    classes = {dirs.database .. cfg.nonspam_file,
               dirs.database .. cfg.spam_file},
    ncfs    = 1, -- split "classes" in 2 sublists. "ncfs" is
                 -- the number of classes in the first sublist.
    delimiters = cfg.extra_delimiters or '',
    nonspam_index = 1,
    spam_index    = 2,
  }

  return dirs
end

----------------------------------------------------------------
-- Layout of the package:
--   core Core functions coded in C.

--   util Utility functions coded in Lua.

--   cfg  Package configuration parameters

--   dirs Directories used by the package:

--   commands Commands to be called directly.
--     They don't interact with the user.

--   bymail Commands called from a Subject: line.

--   command_line Commands called from the command line 
--     or from the body of a 'batch' command.

local core, util, cfg, dirs, commands, bymail, command_line =
      core, util, cfg, dirs, commands, bymail, command_line
