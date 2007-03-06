local require, print, pairs, ipairs, type, io, string, table, os, _G =
      require, print, pairs, ipairs, type, io, string, table, os, _G

local modname = ...

module(modname)

local submodules =
  { 'core', 'util', 'lists', 'commands', 'mail_commands', 'cfg', 'command_line',
    'msg', 'learn' }

for _, submodule in ipairs(submodules) do
  require (modname .. '.' .. submodule)
end

dirs = { }

local val, bool, opt, dir =
  util.options.val, util.options.bool, util.options.opt, util.options.dir

std_opts = 
	{ udir = dir, learn = val, unlearn = val, classify = bool,
	  score = bool, cfdir = dir, dbdir = dir, listdir = dir, source = val,
	  output = val, help = bool}


function set_dirs(options)
  local HOME = os.getenv 'HOME'
  local default_dir = HOME and HOME .. '/.osbf-lua' 
  options = options or { }
  dirs.user     = options.udir or core.is_dir(default_dir) and default_dir or '.'
  dirs.config   = options.cfgdir   or dirs.user
  dirs.database = options.dbdir    or dirs.user
  dirs.lists    = options.listsdir or dirs.user

  for k in pairs(dirs) do dirs[k] = util.append_slash(dirs[k]) end

  dirs.cache = dirs.user .. "cache/"
  dirs.log = dirs.user .. 'log/'
  return dirs
end

init = set_dirs


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
