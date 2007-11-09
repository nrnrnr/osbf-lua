local string, io, require, os, assert, ipairs, type, math =
      string, io, require, os, assert, ipairs, type, math

module(...)

local lists = require(_PACKAGE .. 'lists')
local util  = require(_PACKAGE .. 'util')
local cfg   = require(_PACKAGE .. 'cfg')
local core  = require(_PACKAGE .. 'core')
local dirs  = assert(cfg.dirs)
require(_PACKAGE .. 'learn')  -- load the learning commands
require(_PACKAGE .. 'report') -- load the cache-report command

__doc = __doc or { }

__doc.mk_list_command = [[function(cmd, part)
Factory of list commands.
]]

local function mk_list_command(cmd, part)
  return function(listname, tag, arg)
           return lists[cmd](listname, part, string.lower(tag), arg)
         end
end

__doc.list_add_string = [[function(listname, tag, arg)
Adds key tag with value arg to listname's string table.
]]
list_add_string = mk_list_command('add', 'strings')

__doc.list_add_pat = [[function(listname, tag, arg)
Adds key tag with value arg to listname's pattern table.
]]
list_add_pat    = mk_list_command('add', 'pats')

__doc.list_del_string = [[function(listname, tag, arg)
Removes key tag with value arg from listname's string table.
]]
list_del_string = mk_list_command('del', 'strings')

__doc.list_del_pat = [[function(listname, tag, arg)
Removes key tag with value arg from listname's pattern table.
]]
list_del_pat    = mk_list_command('del', 'pats')

__doc.create_single_db = [[function(db_path, size_in_bytes)
Creates a class database named db_path, with no more than size_in_bytes bytes.
Returns the real size in bytes, which is the greatest multiple of the size
of a bucket not greater than size_in_bytes
]]

function create_single_db(db_path, size_in_bytes)
  assert(type(size_in_bytes) == 'number') 

  local function bytes(buckets)
    return buckets * core.bucket_size + core.header_size
  end

  local min_buckets =   100 --- minimum number of buckets acceptable
  local num_buckets =
    math.floor((size_in_bytes - core.header_size) / core.bucket_size)
  if num_buckets < min_buckets then
    util.die('Database too small; each database must use at least ',
             util.human_of_bytes(bytes(min_buckets)), '\n')
  end
  core.create_db(db_path, num_buckets)
  return bytes(num_buckets)
end

__doc.init = [[function(email, totalsize, lang)
The init command creates directories and databases and the default config.
totalsize is the total size in bytes of all databases to be created.
email is the address for subject-line commands.
lang (optional) is a string with the language for report_locale in config.
]]

function init(email, totalsize, lang)
  local ds = { dirs.user, dirs.database, dirs.lists, dirs.cache, dirs.log }
  for _, d in ipairs(ds) do
    util.mkdir(d)
  end

  local dbcount = #cfg.dblist
  totalsize = totalsize or dbcount * cfg.constants.default_db_megabytes * 1024 * 1024
  if type(totalsize) ~= 'number' then
    util.die('Database size must be a number')
  end
  local dbsize = totalsize / dbcount
  -- create new, empty databases
  local totalbytes = 0
  local function walk(t)
    for _, db in ipairs(t.dbnames or { }) do
      totalbytes = totalbytes + create_single_db(db, dbsize)
    end
    if t.children then walk(t.children[1]); walk(t.children[2]) end
  end    
  walk(cfg.multitree)
  local config = cfg.configfile
  if util.file_is_readable(config) then
    util.write_error('Warning: not overwriting existing ', config, '\n')
  else
    local default = util.submodule_path 'default_cfg'
    local f = util.validate(io.open(default, 'r'))
    local u = util.validate(io.open(config, 'w'))
    local x = f:read '*a'
    -- sets initial password to a random string
    x = string.gsub(x, '(pwd%s*=%s*)[^\r\n]*',
      string.format('%%1%q,', util.generate_pwd()))
    -- sets email address for commands 
    x = string.gsub(x, '(command_address%s*=%s*)[^\r\n]*',
      string.format('%%1%q,', email))
    -- sets report_locale
    if lang then
      x = string.gsub(x, '(report_locale%s*=%s*)[^\r\n]*',
        string.format('%%1%q,', lang))
    end
    u:write(x)
    f:close()
    u:close()
  end
  return totalbytes --- total bytes consumed by databases
end
