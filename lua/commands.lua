require 'osbf'
require 'osbf.lists'

local util, lists = osbf.util, osbf.lists

local string = string
      

module(...)

local function mk_list_command(cmd, part)
  return function(listname, tag, arg)
           return list[cmd](listname, part, string.lower(tag), arg)
         end
end

list_add_string = mk_list_command('add', 'strings')
list_add_pat    = mk_list_command('add', 'pats')
list_del_string = mk_list_command('del', 'strings')
list_del_pat    = mk_list_command('del', 'pats')

