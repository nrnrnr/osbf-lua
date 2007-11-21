local require, print, ipairs, pairs, type, assert, tostring, error, pcall =
      require, print, ipairs, pairs, type, assert, tostring, error, pcall

local io, string, table, os, coroutine, math, tonumber =
      io, string, table, os, coroutine, math, tonumber

module(...)

local cfg  = require(_PACKAGE .. 'cfg')
local core = require(_PACKAGE .. 'core')
local util = require(_PACKAGE .. 'util')
local slash = cfg.slash

----------------------------------------------------------------
-- Utilities for managing the cache

__doc = { }

__doc.__order = { 'sfid', 'table_of_sfid', 'sfid_of_table',
                  'status', 'file_and_status', 'change_file_status' }

__doc.sfid = [[A string (spam filter id) that uniquely identifies a message.
In addition, the sfid encodes various properties such as time received, intial
classification, learned classification (if any), and confidence level.
The format of a sfid is as follows:

  sfid-<tag>-<time>-<confidence>-<serial>@<rightid>[-<learned>]

Where the meanings of the various fields are as follows:

  tag         = A single letter denoting the classification of the message.
                If lower case, the message should be trained (is in the 
                reinforcement zone for that class; if upper case, no
                training is required).  Letters 'b', 'w', and 'e' are
                reserved for blacklisted, whitelisted, and errored messages
                respectively.  These letters are always upper case.

  time        = Time of receipt in the form YYYYmmdd-HHMMSS

  confidence  = A measure of certainty in classification: 0 means the
                classification provides no information whatever; 20 or
                more means very high confidence.   The number is
                computed as the logarithm of a ratio of probabilities;
                the base of the logarithm is chosen empirically.
                The number matches pattern '^[-+]%d+%.%d+$'.

  serial      = A serial number to ensure the sfid is unique

  rightid     = A string that identifies the classifier which generated
                the sfid. Multiple classifiers may share the same
                cache.  A valid rightid is formed of alphanumeric
                characters plus dashes and dots; in other words, it
                should look like a domain name.

  learned     = A lowercase letter identifying the class with which
                this message has been trained.  This suffix is present
                only if the message has been trained.
]]

__doc.table_of_sfid = [[function(sfid) returns table
Takes a spam filter id and returns a table with these fields:
  tag   -- lower or upper case letter designating initial classification
  time    -- time of initial classification as returned by os.time()
  serial  -- a serial number that makes the sfid unique
  rightid -- a string identifying the classifier
  learned -- if the message has been trained, a lowercase letter
             indicating the relevant class; nil otherwise

If sfid is not a string or if  the string is not well formed, 
table_of_sfid() calls error().
]]

__doc.sfid_of_table = [[function(table [, serial]) returns sfid
Takes a table as returned by table_of_sfid and returns a sfid.
All fields of the table are optional except 'tag'.
Defaults are
  time       = current time
  confidence = 0
  serial     = 1
  rightid    = cfg.rightid
  learned    = nil
Parameter serial, if given, overrides table.serial.
]]

local function validate_rightid(id)
  -- returns id if valid or 'spamfilter.osbf.lua' otherwise
  return type(id) == 'string'
	   and
	 -- must be a valid domain name: letters, digits, '.' and '-'
	 string.find(id, '^[%w%-%.]+$')
	   and
	 id
	   or
	 'spamfilter.osbf.lua'
end

local is_valid_tag = { B = true, W = true, E = true }
  -- blacklist, whitelist, and error are always valid

function sfid_of_table(t, serial)
  local s =
    table.concat({ 'sfid',
                   assert(t.tag and is_valid_tag[t.tag] and t.tag),
                   os.date('%Y%m%d-%H%M%S', t.time),
                   string.format('%+4.2f', t.confidence or 0),
                   serial or t.serial or 1,
                   '@',
                   validate_rightid(t.rightid or cfg.rightid),
                   t.learned }, '-')
  return string.gsub(s, '%-%@%-', '@', 1)
end

do
  local last_s, last_t = {}  -- initial last_s can't possibly match any arg

  function table_of_sfid(s)
    if last_s == s then return last_t end -- cache
    if type(s) ~= 'string' then
      util.errorf('Non-string value %s used as sfid', tostring(s))
    end
    local tag, year, month, day, hour, min, sec, confidence, serial, rightid, learned =
      string.match(s, '^sfid%-(%a)%-(%d%d%d%d)(%d%d)(%d%d)%-(%d%d)(%d%d)(%d%d)%-' ..
                      '([%+%-]%d+%.%d+)%-(%d+)%@(.-)%-?(%l?)$')
    if not (tag and learned) then
      error("Ill-formed sfid " .. s)
    end
    local n = tonumber
    local time = os.time { year = n(year), month = n(month), day = n(day),
                           hour = n(hour), min = n(min), sec = n(sec) }
    if learned == '' then learned = nil end
    last_t, last_s = { tag = tag, time = time, confidence = n(confidence),
                       serial = n(serial), rightid = rightid, learned = learned }, s
    return last_t
  end
end

__doc.validate_sfid = [[function(sfid) returns nil or calls error
Calls error() if the argument is not a valid sfid; otherwise
does nothing.]]

local function validate_sfid(sfid)
  table_of_sfid(sfid)
end

__doc.status = [[A classification, 'unlearned', or 'missing'
Each message (known by its sfid) has a status, which is
exactly one of the above.  A 'missing' message is not in 
the message cache.

In OSBF-Lua's default configuration, the only possible classifications
are 'spam' and 'ham'.
]]

local classes

local suffixes = { unlearned = '' }
  -- used to name cache files according to status
do
  local function set_suffixes()
    classes = cfg.classes
    for _, reserved in ipairs { 'unlearned', 'missing' } do
      if classes[reserved] then
        util.errorf("Cannot have a class called '%s'; this name is "..
                    "reserved for use by the message cache", reserved)
      end
    end
    for class, tbl in pairs(classes) do
      assert(not suffixes[class])
      local tag = tbl.sfid
      if not string.match(tag, '^%l$') or string.match(tag, '^[bew]$') then
        error('sfid tag for class ' .. class ..
              ' must be a lowercase letter other than b, e, or w')
      else
        suffixes[class] = '-' .. tag
        is_valid_tag[tag] = true
        is_valid_tag[string.upper(tag)] = true
      end
    end
  end

  cfg.after_loading_do(set_suffixes)
end

__doc.is_sfid = [[function(s) returns bool
Tells whether 's' represents a sfid (spam filter id).]]

function is_sfid(sfid)
  return (pcall(table_of_sfid, sfid))
end

__doc.subdir = [[function(sfid) returns string
Returns the subdirectory of the cache in which that sfid should be stored,
or if subdirectories are not used, returns the empty string.]]

function subdir(sfid)
  local t = table_of_sfid(sfid) -- guarantees we have a sfid even if t not used
  if cfg.use_sfid_subdir then
    return table.concat { t.day, slash, t.hour, slash }
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
status is either 'unlearned', 'missing', or a class
that is a key in cfg.classes.
file == nil if and only if status == 'missing']]

-- secretly, for internal use only, also returns the filename
function file_and_status(sfid)
  validate_sfid(sfid)
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
  assert(sfid_tag and is_valid_tag[sfid_tag], 'invalid sfid tag')
  local t = { confidence = pR, tag = sfid_tag }
  for i = 1, 10000 do 
    local sfid = sfid_of_table(t, i)
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
    error(is_sfid(sfid) and sfid .. ': not found in cache.' or 'Invalid sfid.')
  end
end
 
__doc.try_recover = [[function(sfid) returns string or nil, error
If the message is still in the cache, return the contents as a string.
Otherwise returns nil with an error message.  XXX should be calling
error on missing message XXX (and then name changed to recover, msg.lua
client changed to use pcall)]]

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

__doc.tag_is_unlearnable = [[function(tag) returns boolean
Takes the tag of a sfid table, i.e., table_of_sfid(sfid).tag, 
and returns true if the tag represents an unlearnable initial classification.
Currently the only unlearanable classifications are B (blacklisted),
W (whitelisted), and E (error).]]

function tag_is_unlearnable(tag)
  assert(string.len(tag) == 1 and string.find(tag, '%a'), 'ill-formed tag')
  return (string.find(t.tag, '[WBE]'))
end

----------------------------------------------------------------

__doc.sort_sfids = [[function(sfids) returns sfids
Sorts a list of sfids (in place) into the order specified by 
cfg.cache_report_order_by (date or confidence) and
cfg.cache_report_order ('<' or '>').  Returns sfids just for convenience.
]]


function sort_sfids(sfids)
  -- some hacking here to avoid recomputing table_of_sfid at every comparison
  local key = { }  -- caches table_of_sfid.xxx computation for duration of sort
  local keyfuns =
    { date = function(_, s) return table_of_sfid(s).time end,
      confidence = function(_, s) return table_of_sfid(s).confidence end }
  local keyfun =
    assert(keyfuns[cfg.cache_report_order_by], 'unknown option to order by')
  
  setmetatable(key, { __index = keyfun })
  local ltfuns = 
    { ['<'] = function(s1, s2) return key[s1] < key[s2] end,
      ['>'] = function(s1, s2) return key[s1] > key[s2] end }
  table.sort(sfids, assert(ltfuns[cfg.cache_report_order], 'unknown operator'))
  return sfids
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

  local sfids = {} -- first insert, then sort by time or confidence
  for _, subdir in ipairs(sfid_subdirs) do
    for f in core.dir(cfg.dirs.cache .. subdir) do
      if string.find(f, "^sfid%-") then
        table.insert(sfids, f)
      end
    end
  end
  sort_sfids(sfids)
  for _, f in ipairs(sfids) do
    coroutine.yield(f)
  end
end

__doc.two_days_sfids = [[function() returns iterator
Iterator successively yields a sfid from cache, in the oreder
specified by cfg.cache_report_order.]]

function two_days_sfids() return coroutine.wrap(yield_two_days_sfids) end
