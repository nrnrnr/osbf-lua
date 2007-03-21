local string, require = string, require

module(...)

local lists = require(_PACKAGE .. 'lists')

function whitelist(msg, s) return lists.eval('whitelist', s) end
function blacklist(msg, s) return lists.eval('blacklist', s) end
