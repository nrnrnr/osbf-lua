#! /usr/bin/env lua

local osbf = require 'osbf3'

osbf.init({ udir = '.' }, true) --- ignore missing log or cache dirs

local util = require 'osbf3.util'

if not arg[1] then
  io.write("Usage: ", arg[0], " <path-trec-index>\n")
  os.exit(1)
end

local path = util.append_slash(arg[1])
local index = path .. "index"
for l in io.lines(index) do
  local class, msg_file = string.match(l, "(%a+)%s+(.+)")
  io.write(msg_file)
  local m = osbf.msg.of_file(path .. msg_file)
  if osbf.lists.match('whitelist', m) then
    io.write(" -- whitelisted\n")
  else
    io.write("\n")
  end
  io.flush()
end
