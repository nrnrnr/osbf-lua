require 'osbf'
require 'osbf.lists'

local util, lists = osbf.util, osbf.lists

local string = string
      

module(...)

function whitelist(msg, s) return lists.eval('whitelist', s) end
function blacklist(msg, s) return lists.eval('blacklist', s) end
