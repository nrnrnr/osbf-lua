-- See Copyright Notice in osbf.lua

local string, io, require, os, assert, ipairs, pairs, type, math =
      string, io, require, os, assert, ipairs, pairs, type, math

module(...)

local lists = require(_PACKAGE .. 'lists')
local util  = require(_PACKAGE .. 'util')
local cfg   = require(_PACKAGE .. 'cfg')
local msg   = require(_PACKAGE .. 'msg')
local log   = require(_PACKAGE .. 'log')
local cache = require(_PACKAGE .. 'cache')
local core  = require(_PACKAGE .. 'core')
local filter = require(_PACKAGE .. 'filter')
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

local function buckets_of_bytes(bytes) 
  if bytes <= core.header_size then
    return 0
  else
    return math.floor((bytes - core.header_size) / core.bucket_size + 0.5)
  end
end

local function bytes_of_buckets(buckets)
  return buckets * core.bucket_size + core.header_size
end

function create_single_db(db_path, buckets)
  assert(type(buckets) == 'number') 
  local min_buckets =   100 --- minimum number of buckets acceptable
  util.checkf(buckets >= min_buckets, 'Database of %d buckets is too small; ' ..
              'must use at least %d buckets or %s\n', buckets,
               min_buckets, util.human_of_bytes(bytes_of_buckets(min_buckets)))
  core.create_db(db_path, buckets)
  return bytes_of_buckets(buckets)
end

local default_rightid = util.local_rightid()

__doc.init = ([[function(email, size, units, [rightid, lang, use_subdirs])
The init command creates directories and databases and the default config.
'size' is the a size, which is interpreted according to 'units', which must
be one of these values:
   buckets      -- number of buckets in one database
   totalbuckets -- number of buckets in all databases
   bytes        -- number of bytes in one database
   totalbytes   -- number of bytes in all databases
email is the address for subject-line commands.
rightid (optional) is the right part of the Spam Filter ID;
  it defaults to $rightid
lang (optional) is a string with the language for cfg.cache.report_locale 
use_subdirs (optional) constrols division of the cache into subdirectories
  if 'daily',          subdirs are YYYY/MM-DD
  if nil or false,     there are no subdirs
  otherwise,           subdirs are DD/HH
]]) : gsub('%$rightid', default_rightid)

do
  
  local function id(x) return x end
  local to_buckets = { buckets = id, totalbuckets = id,
                       bytes = buckets_of_bytes, totalbytes = buckets_of_bytes }
  local divide = { totalbuckets = true, totalbytes = true }


  function init(email, size, units, rightid, lang, use_subdirs)
    local to_buckets = assert(to_buckets[units], 'bad units passed to commands.init')
    assert(type(size) == 'number', 'bad size (not a number) passed to commands.init')
    rightid = rightid or default_rightid
    assert(type(rightid) == 'string',
           'bad rightid (not a string) passed to commands.init')
    -- io.stderr:write('Initalization with ', units, ' ', size, '\n')

    local ds = { dirs.user, dirs.database, dirs.lists, dirs.cache, dirs.log }
    util.tablemap(util.mkdir, ds)

    if divide[units] then size = math.floor(size / #cfg.classlist()) end
    local buckets = to_buckets(size)

    -- create new, empty databases
    local totalbytes = 0
    for c, tbl in pairs(cfg.classes) do
      totalbytes = totalbytes + create_single_db(tbl.db, buckets)
    end
    local config = cfg.configfile
    if util.file_is_readable(config) then
      output.error:write('Warning: not overwriting existing ', config, '\n')
    else
      local default = util.submodule_path 'default_cfg'
      local f = util.validate(io.open(default, 'r'))
      local u = util.validate(io.open(config, 'w'))
      local x = f:read '*a'
      -- sets initial password to a random string
      x = x:gsub('(pwd%s*=%s*)[^\r\n]*', string.format('%%1%q,', util.generate_pwd()))
      -- sets email address for commands 
      x = x:gsub('(command_address%s*=%s*)[^\r\n]*', string.format('%%1%q,', email))
      -- sets email address for reports
      x = x:gsub('(report_address%s*=%s*)[^\r\n]*', string.format('%%1%q,', email))
      -- sets sfid's rightid
      x = x:gsub('(rightid%s*=%s*)[^\r\n]*', string.format('%%1%q,', rightid))
      -- sets report_locale
      if lang then
        x = x:gsub('(report_locale%s*=%s*)[^\r\n]*', string.format('%%1%q,', lang))
      end
      if use_subdirs == 'daily' then
        x = x:gsub('(use_subdirs%s*=%s*)false', '%1"daily"')
      elseif use_subdirs then
        x = x:gsub('(use_subdirs%s*=%s*)false', '%1true')
      end
      u:write(x)
      f:close()
      u:close()
    end
    return totalbytes --- total bytes consumed by databases
  end
end

----------------------------------------------------------------
__doc.filter = filter.__doc.run
_M.filter = assert(filter.run)
