local string, io, require, os, assert, ipairs, type, math =
      string, io, require, os, assert, ipairs, type, math

module(...)

local lists = require(_PACKAGE .. 'lists')
local util  = require(_PACKAGE .. 'util')
local cfg   = require(_PACKAGE .. 'cfg')
local core  = require(_PACKAGE .. 'core')
local dirs  = assert(cfg.dirs)

local function mk_list_command(cmd, part)
  return function(listname, tag, arg)
           return lists[cmd](listname, part, string.lower(tag), arg)
         end
end

list_add_string = mk_list_command('add', 'strings')
list_add_pat    = mk_list_command('add', 'pats')
list_del_string = mk_list_command('del', 'strings')
list_del_pat    = mk_list_command('del', 'pats')

-- The init command creates directories and databases and the default config.
-- dbsize is the size in bytes of each database to be created
function init(dbsize)
  local ds = { dirs.user, dirs.database, dirs.lists, dirs.cache, dirs.log }
  for _, d in ipairs(ds) do
    util.mkdir(d)
  end

  local header_size, bucket_size = core.db_header_and_bucket_sizes()
  dbsize = dbsize or 94321 * bucket_size + header_size
  assert(type(dbsize) == 'number') 
  local num_buckets = math.floor((dbsize - header_size) / bucket_size)

  -- create new, empty databases
  util.validate(core.create_db(cfg.dbset.classes, num_buckets))
  local config = cfg.configfile
  if util.file_is_readable(config) then
    io.stderr:write('Warning: not overwriting existing ', config, '\n')
  else
    local default = util.validate(util.submodule_path 'default_cfg')
    local f = util.validate(io.open(default, 'r'))
    local u = util.validate(io.open(config, 'w'))
    u:write(f:read '*a')
    f:close()
    u:close()
  end
end
