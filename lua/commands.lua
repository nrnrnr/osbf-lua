local string, require, os, assert, ipairs, type =
      string, require, os, assert, ipairs, type

module(...)

local lists = require(_PACKAGE .. 'lists')
local util  = require(_PACKAGE .. 'util')
local cfg   = require(_PACKAGE .. 'cfg')
local core  = require(_PACKAGE .. 'core')
local osbf  = require(string.gsub(_PACKAGE, '%.$', ''))
local dirs  = assert(osbf.dirs)

local function mk_list_command(cmd, part)
  return function(listname, tag, arg)
           return lists[cmd](listname, part, string.lower(tag), arg)
         end
end

list_add_string = mk_list_command('add', 'strings')
list_add_pat    = mk_list_command('add', 'pats')
list_del_string = mk_list_command('del', 'strings')
list_del_pat    = mk_list_command('del', 'pats')

-- The init command creates directories and databases.
-- Perhaps the optional argument should be denominated in bytes, not buckets?

function init(num_buckets)
  --local create = require(_PACKAGE .. 'create') -- load only on demand
  local ds =
    { dirs.user, dirs.config, dirs.database, dirs.lists, dirs.cache, dirs.log }
  for _, d in ipairs(ds) do
    util.mkdir(d)
  end

  num_buckets = num_buckets or 94321
  assert(type(num_buckets) == 'number') 

  -- create new, empty databases
  return util.validate(core.create_db(cfg.dbset.classes, num_buckets))
end
