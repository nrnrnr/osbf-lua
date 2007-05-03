local string, io, require, os, assert, ipairs, type, math =
      string, io, require, os, assert, ipairs, type, math

module(...)

local lists = require(_PACKAGE .. 'lists')
local util  = require(_PACKAGE .. 'util')
local cfg   = require(_PACKAGE .. 'cfg')
local core  = require(_PACKAGE .. 'core')
local dirs  = assert(cfg.dirs)

__doc = __doc or { }

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
-- totalsize is the total size in bytes of all databases to be created
function init(totalsize)
  local ds = { dirs.user, dirs.database, dirs.lists, dirs.cache, dirs.log }
  for _, d in ipairs(ds) do
    util.mkdir(d)
  end

  local num_buckets = 94321 --- default if no size specified
  local min_buckets =   100 --- minimum number of buckets acceptable

  local function bytes(buckets)
    return buckets * core.bucket_size + core.header_size
  end

  if totalsize then
    assert(type(totalsize) == 'number') 
    local dbsize = totalsize / 2
    num_buckets = math.floor((dbsize - core.header_size) / core.bucket_size)
    if num_buckets < min_buckets then
      util.die('Databases too small; each database must use at least ',
               util.human_of_bytes(bytes(min_buckets)), '\n')
    end
  end

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
  return 2 * bytes(num_buckets) --- total bytes consumed by databases
end
