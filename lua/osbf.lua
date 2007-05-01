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

