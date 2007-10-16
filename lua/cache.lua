local require, print, ipairs, pairs, type, assert, tostring, error =
      require, print, ipairs, pairs, type, assert, tostring, error

local io, string, table, os, coroutine, math, tonumber =
      io, string, table, os, coroutine, math, tonumber

module(...)

__doc = { }

__doc.__order = { 'sfid', 'status', 'file_and_status', 'change_file_status' }

__doc.sfid = 'A string (spam filter id) that uniquely identifies a message'

local cfg  = require(_PACKAGE .. 'cfg')
local core = require(_PACKAGE .. 'core')
local util = require(_PACKAGE .. 'util')
local slash = cfg.slash

----------------------------------------------------------------
-- Utilities for managing the cache

__doc.status = [['spam', 'ham', 'unlearned', or 'missing'
Each message (known by its sfid) has a status, which is
exactly one of the above.  A 'missing' message is not in 
the message cache.

If multiclassification is enabled, each classification may be an additional status.
]]

local suffixes = { spam = '-s', ham = '-h', unlearned = '' }
  -- used to name cache files according to status

cfg.after_loading_do(function()
  if cfg.multi then
    assert(cfg.multi.tags and cfg.multi.tags.sfid)
    for class, tag in pairs(cfg.multi.tags.sfid) do
      if not suffixes[class] then
        if not string.match(tag, '^%l$') or string.match(tag, '^[sh]$') then
          error('sfid tag for class ' .. class ..
                ' must be lowercase letter other than s or h')
        else
          suffixes[class] = '-' .. tag
        end
      end
    end
  end
end)

local function generate_rightid()
  -- returns cfg.right id if valid or 'spamfilter.osbf.lua'
  return type(cfg.rightid) == 'string'
	   and
	 -- must be a valid domain name: letters, digits, '.' and '-'
	 string.find(cfg.rightid, '^[%a%d%-%.]+$')
	   and
	 cfg.rightid
	   or
	 'spamfilter.osbf.lua'
end

__doc.is_sfid = [[function(s) returns bool
Tells whether 's' represents a sfid (spam filter id).]]

function is_sfid(sfid)
  return type(sfid) == 'string'
	and not string.find(sfid, '%-%l$') -- avoid conflict with renamed sfids
	-- rightid must be a valid domain names: only letters, digits, '-' and '.'
	and string.find(sfid, '^sfid%-.-@[%a%d%.%-]+$')
end

__doc.subdir = [[function(sfid) returns string
Returns the subdirectory of the cache in which that sfid should be stored,
or if subdirectories are not used, returns the empty string.]]
               
function subdir(sfid)
  assert(is_sfid(sfid), 'invalid sfid: ' ..
    type(sfid) == 'string' and sfid or 'not string')
  if cfg.use_sfid_subdir then
    return
      table.concat { string.sub(sfid, 13, 14), slash, string.sub(sfid, 16, 17), slash }
  else
    return ''
  end
end

__doc.filename = [[function(sfid, status) returns string
Given a message's sfid and status, returns the pathname of that
message in the cache.  The caller is trusted; there's no guarantee
that the message is actually present with that status.]]

function filename(sfid, status)
  return cfg.dirfilename('cache', subdir(sfid) .. sfid, assert(suffixes[status]))
end
    
__doc.file_and_status = [[function(sfid) returns file, status
file is either nil or a descriptor open for read
status is either 'unlearned', 'spam', 'ham', or 'missing'
or a classification from cfg.multi.classes.
file == nil if and only if status == 'missing']]

-- secretly, for internal use only, also returns the filename
function file_and_status(sfid)
  if not is_sfid(sfid) then
    error('Invalid sfid passed to file_and_status')
  end
  for status in pairs(suffixes) do
    local fname = filename(sfid, status)
    local f = io.open(fname, 'r')
    if f then return f, status, fname end
  end
  return nil, 'missing'
end

__doc.change_file_status = [[
function(sfid, oldstatus, newstatus) returns non-nil or nil, error
Renames the message file in the cache to reflect a change in status.
The change in status must be the result of learning or unlearning.]]

function change_file_status(sfid, status, classification)
  if status ~= classification
  and (classification == 'unlearned' or status == 'unlearned') then
    util.insist(os.rename(filename(sfid, status), filename(sfid, classification)))
  else
    error('invalid to change status from ' .. status .. ' to ' .. classification)
  end
end

__doc.generate_sfid = [[function(sfid_tag, pR) returns string
Returns a new, unique sfid.  The tag is the sfid_tag from
commands.classify, and the pR is the classification score,
which may be a number or nil.

XXX this function is not atomic; to make it atomic, it ought to be 
combined with cache.store XXX]]

function generate_sfid(sfid_tag, pR)
  -- returns a new SFID
  -- if pR is not a number, 0 is used instead.
  assert(type(sfid_tag) == 'string', 'sfid_tag type must be string')
  local at_rightid = '@' .. generate_rightid()
  local leftid = string.format('sfid-%s%s-%+07.2f-', sfid_tag,
				os.date('%Y%m%d-%H%M%S'),
				type(pR) == 'number' and pR or 0)
  for i = 1, 10000 do 
    local sfid = leftid .. i .. at_rightid
    -- for safety this should be an atomic test-and-set (using file locking?)
    if not file_and_status(sfid) then
      return sfid
    end
  end
  error('could not generate sfid')
end

__doc.store = [[function(sfid, msg) returns string or calls error
msg is a string containing the message to which the unique sfid
has been assigned.  This function writes the message into the cache,
returning the sfid if successful, and if unsuccessful (because
of a collision), returning nil, error.

XXX this function should be combined with generate_sfid so
the two could be made atomic XXX]]

function store(sfid, msg)
  -- stores a message in the cache, under the name sfid
  -- msg is a string containing the message
  local f = file_and_status(sfid)
  if f then
    f:close()
    error('sfid ' .. sfid .. ' is already in the cache!')
  end
  local f = assert(io.open(filename(sfid, 'unlearned'), 'w'))
  f:write(msg)
  f:close()
  return sfid
end

__doc.remove = [[function(sfid)
Removes message from the cache (if present); otherwise calls error.]]

function remove(sfid)
  local f, _, fname = file_and_status(sfid)
  if f then
    f:close()
    util.insist(os.remove(fname))
  else
    error(
      type(sfid) == 'string'
        and
      sfid .. ': not found in cache.'
        or
      'Invalid sfid.')
  end
end
 
__doc.try_recover = [[function(sfid) returns string or nil, error
If the message is still in the cache, return the contents as a string.
Otherwise returns nil with an error message.]]

function try_recover(sfid)
  -- returns a string containing the message associated with sfid
  -- or nil, err, if sfid is not in cache
  local f, err = file_and_status(sfid)
  if f then
    local msg = f:read('*a')
    f:close()
    return msg
  else
    if is_sfid(sfid) then
      return nil, sfid .. ': not found in cache.'
    else
      return nil, 'Invalid sfid.'
    end
  end
end

----------------------------------------------------------------

__doc.sfid_score = [[function(sfid) returns sfid score]]

function sfid_score(sfid)
  local score = string.match(sfid, 'sfid%-.%d-%-%d-%-([-+]%d+.%d+)')
  if score then
    return tonumber(score)
  else
    error('not a valid sfid')
  end
end

----------------------------------------------------------------

__doc.sfid_creation_time = [[function(sfid) returns a string with
the creation time of sfid in the format 'YYYYMMDD-HHMMSS'. In case
of error, retursn false if arg is not string or nil if date and time
is not found.]]

function sfid_creation_time(sfid)
  return type(sfid) == 'string'
           and
         string.match(sfid, '^sfid%-.(........%-......)')
end

----------------------------------------------------------------

__doc.sfid_is_learnable = [[function(sfid) returns true if sfid is
learnable, that is, it's unlearned and its tag is not 'W',
'B' or 'E'.]]

function sfid_is_learnable(sfid)
  return is_sfid(sfid) and string.find(sfid, '^sfid%-[^WBE].*[^%-][^%l]$')
end

----------------------------------------------------------------

__doc.sfid_is_in_reinforcement_zone = [[function(sfid) returns true if sfid is
in user reinforcement zone.
Sneakily compares the min-abs pR against the widest zone!]]

function sfid_is_in_reinforcement_zone(sfid)
  return math.abs(sfid_score(sfid) - cfg.multitree.min_pR) < cfg.multitree.threshold
end

----------------------------------------------------------------

local valid_cmp_op = { ['>'] = true, ['<'] = true }
  -- used to validate sfid comparison operators

local valid_order_by = { date = true, score = true }
  -- used to validate option to order sfids by

-- functions for sifd comparison
local cmp_func =
  { ['<'] =
    { date  = function(s1, s2)
                return sfid_creation_time(s1) < sfid_creation_time(s2)
              end,
      score = function(s1, s2)
                return math.abs(sfid_score(s1)) < math.abs(sfid_score(s2))
              end
    },
    ['>'] =
    { date  = function(s1, s2)
                return sfid_creation_time(s1) > sfid_creation_time(s2)
              end,
      score = function(s1, s2)
                return math.abs(sfid_score(s1)) > math.abs(sfid_score(s2))
              end
    }
}
 
__doc.cmp_sfids = [[function(op) returns a function that compares
creation dates or scores of two sfids, depending on the value of
cfg.cache_report_order_by, using comparison operator op.

op is a string and valid values are: 
  '<' => first sfid comes before the second.
  '>' => second sfid comes before the first.
]]

function cmp_sfids(op)
  assert(valid_cmp_op[op], 'unknown operator')
  assert(valid_order_by[cfg.cache_report_order_by], 'unknown option to order by')
  return cmp_func[op][cfg.cache_report_order_by]
end

----------------------------------------------------------------

__doc.yield_two_days_sfids = [[function() yields sfids in cache in the
order specified by cfg.cache_report_order.
If subdir is in use, yields only sfids from last two days.]]

local function yield_two_days_sfids()
  local sfid_subdirs = 
    cfg.use_sfid_subdir and
    {os.date("%d/%H/", os.time()- 24*3600), os.date("%d/%H/", os.time())}
                -- yesterday and today
    or {""}

  --- shouldn't sfids be sorted by time or something?
  local sfids = {}
  for _, subdir in ipairs(sfid_subdirs) do
    for f in core.dir(cfg.dirs.cache .. subdir) do
      if string.find(f, "^sfid%-") then
        table.insert(sfids, f)
      end
    end
  end
  table.sort(sfids, cmp_sfids(cfg.cache_report_order))
  for _, f in ipairs(sfids) do
    coroutine.yield(f)
  end
end

__doc.two_days_sfids = [[function() returns iterator
Iterator successively yields a sfid from cache, in the oreder
specified by cfg.cache_report_order.]]

function two_days_sfids() return coroutine.wrap(yield_two_days_sfids) end
