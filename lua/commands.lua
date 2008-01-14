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

__doc.init = ([[function(email, size, units, [rightid, lang])
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
]]) : gsub('%$rightid', default_rightid)

do
  
  local function id(x) return x end
  local to_buckets = { buckets = id, totalbuckets = id,
                       bytes = buckets_of_bytes, totalbytes = buckets_of_bytes }
  local divide = { totalbuckets = true, totalbytes = true }


  function init(email, size, units, rightid, lang)
    local to_buckets = assert(to_buckets[units], 'bad units passed to commands.init')
    assert(type(size) == 'number', 'bad size (not a number) passed to commands.init')
    rightid = rightid or default_rightid
    assert(type(rightid) == 'string',
           'bad rightid (not a string) passed to commands.init')
    -- io.stderr:write('Initalization with ', units, ' ', size, '\n')

    local ds = { dirs.user, dirs.database, dirs.lists, dirs.cache, dirs.log }
    util.tablemap(util.mkdir, ds)
    if cfg.cache.use_subdirs then
      cache.make_cache_subdirs(dirs.cache)
    end

    if divide[units] then size = math.floor(size / #cfg.classlist()) end
    local buckets = to_buckets(size)

    -- create new, empty databases
    local totalbytes = 0
    for c, tbl in pairs(cfg.classes) do
      totalbytes = totalbytes + create_single_db(tbl.db, buckets)
    end
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
      -- sets sfid's rightid
      x = string.gsub(x, '(rightid%s*=%s*)[^\r\n]*',
        string.format('%%1%q,', rightid))
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
end

----------------------------------------------------------------
__doc.filter = [[function(msg, options, sfid) returns sfid or calls error
Classify message and insert appropriate tags, headers, and sfid.
Call error() if anything goes wrong.  Does not insert message into
the cache, as this function may be used on the results of cache.recover
to re-deliver a mistakenly classified message.

'sfid' is the sfid assigned to the message, if any; it may be nil,
in which case a fresh sfid may be generated (depending on options).
Options is an optional table in which keys 'notag',
and 'nosfid' can be set to disable subject tagging and sfid insertion.
headers are always inserted; otherwise, why call this function?

This function returns the original sfid or the generated sfid, if any.
]]

function filter(m, options, sfid)
  local probs, conf = multiclassify(m.lim.msg)
  local train, confidence, sfid_tag, subj_tag, class = classify(m, probs, conf)
  local crc32 = core.crc32(msg.to_orig_string(m))
  if not options.nosfid and cfg.use_sfid then
    sfid = sfid or cache.generate_sfid(sfid_tag, confidence)
    msg.insert_sfid(m, sfid, cfg.insert_sfid_in)
  end
  log.lua('filter', log.dt { probs = probs, conf = conf, train = train,
                             synopsis = msg.synopsis(m),
                             class = class, sfid = sfid, crc32 = crc32 })
  if not options.notag and cfg.tag_subject then
    msg.tag_subject(m, subj_tag)
  end
  local classes = cfg.classes
  local summary_header =
    string.format('%.2f/%.2f [%s] (v%s, Spamfilter v%s)',
                  confidence, classes[class].train_below,
                  sfid_tag, core._VERSION, cfg.version)
  local suffixes = cfg.header_suffixes
  msg.add_osbf_header(m, suffixes.summary, summary_header)
  msg.add_osbf_header(m, suffixes.class, class)
  msg.add_osbf_header(m, suffixes.confidence, confidence or '0.0')
  msg.add_osbf_header(m, suffixes.needs_training, train and 'yes' or 'no')
  msg.add_osbf_header(m, suffixes.sfid, sfid)
  return sfid
end
