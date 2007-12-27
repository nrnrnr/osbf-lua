-- exports:
-- osbf.init
-- osbf.command

local require, print, pairs, ipairs, type, io, string, table, os, _G =
      require, print, pairs, ipairs, type, io, string, table, os, _G

local modname = ...

module(modname)

local boot = require (modname .. '.boot')
require (modname .. '.commands')
init = boot.init

__doc = {
  init = [[function(options, no_dirs_ok) returns nothing
Initialize the system passing a table in which the indices are common
options and the values are strings or booleans.  This table should be
returned from options.parse.  If no_dirs_ok is not true, fail if
directories are missing.  This no_dirs_ok is true, continue regardless
of missing directories---the caller must call commands.init as the
next step.
]],
}

