require 'osbf'
require 'osbf.lists'

local util, lists = osbf.util, osbf.lists

local string = string
      

module(...)

--- Table that shows what arguments should be passed to list commands
local list_cmd  = { add = lists.add, ['add-pat'] = lists.add,
                    del = lists.del, ['del-pat'] = lists.del }
local list_part = { add = 'strings', ['add-pat'] = 'pats',
                    del = 'strings', ['del-pat'] = 'pats' }

--- Function to implement both list commands.
-- @param listname Name of the list.
-- @param s Command string: add[-pat] <tag> <string>.
-- @return Non-nil on success; nil, errmsg on failure.

local function list_command(listname)
  return function(s)
           local cmd, tag, arg = string.match(s, '^(%S+)%s+(%S+)%s+(.*)$')
             if not list_cmd[cmd] then
               return nil, "Unrecognized command " .. cmd
             elseif arg == "" then
               return nil, "Command '" .. cmd .. "' expects an argument"
             else
               list_cmd[cmd](listname, list_part[cmd], string.lower(tag), arg)
               return true
             end
           end
end

--- whitelist and blacklist commands.
whitelist = list_command 'whitelist'
blacklist = list_command 'blacklist'
