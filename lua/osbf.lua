local require, print, pairs, ipairs, type, io =
      require, print, pairs, ipairs, type, io

local modname = ...

module(modname)

for _, submodule in ipairs { 'core', 'util', 'lists', 'commands', 'cfg' } do
  require (modname .. '.' .. submodule)
end

dirs = { }

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
