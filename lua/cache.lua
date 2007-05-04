local require, print, pairs, type, assert, tostring =
      require, print, pairs, type, assert, tostring

local io, string, table, os =
      io, string, table, os

module(...)

__doc = { }

__doc.__order = { 'sfid', 'status', 'file_and_status', 'change_file_status' }

__doc.sfid = 'A string (spam filter id) that uniquely identifies a message'

local cfg = require(_PACKAGE .. 'cfg')
local slash = cfg.slash

----------------------------------------------------------------
-- Utilities for managing the cache

__doc.status = [['spam', 'ham', 'unlearned', or 'missing'
Each message (known by its sfid) has a status, which is
exactly one of the above.  A 'missing' message is not in 
the message cache.]]

local suffixes = { spam = '-s', ham = '-h', unlearned = '' }
  -- used to name cache files according to status

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
	and not string.find(sfid, '%-[hs]$') -- avoid conflict with renamed sfids
	-- rightid must be a valid domain names: only letters, digits, '-' and '.'
	and string.find(sfid, '^sfid%-.-@[%a%d%.%-]+$')
end

__doc.subdir = [[function(sfid) returns string
Returns the subdirectory of the cache in which that sfid should be stored,
or if subdirectories are not used, returns the empty string.]]
               
function subdir(sfid)
  assert(is_sfid(sfid), 'invalid sfid!')
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
file == nil if and only if status == 'missing']]

-- secretly, for internal use only, also returns the filename
function file_and_status(sfid)
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
    return os.rename(filename(sfid, status), filename(sfid, classification))
  else
    return nil, 'invalid to change status from ' .. status .. ' to ' .. classification
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
  return nil, 'could not generate sfid'
end

__doc.store = [[function(sfid, msg) returns string or nil, error
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
  if fn then
    f:close()
    return nil, 'sfid ' .. sfid .. ' is already in the cache!'
  end
  local f = assert(io.open(filename(sfid, 'unlearned'), 'w'))
  f:write(msg)
  f:close()
  return sfid
end

__doc.remove = [[function(sfid)
Removes message from the cache (if present).]]

function remove(sfid)
  local f, _, fname = file_and_status(sfid)
  if f then
    f:close()
    return os.remove(fname)
  end
end
 
__doc.recover = [[function(sfid) returns string or returns nil, error message
If the message is still in the cache, return the contents as a string.
Otherwise returns nil with an error message.]]

function recover(sfid)
  -- returns a string containing the message associated with sfid
  -- or nil, err, if sfid is not in cache
  local f, err = file_and_status(sfid)
  if f then
    local msg = f:read('*a')
    f:close()
    return msg
  else
    return f, 'Message ' .. sfid .. ' is not in the cache'
  end
end

----------------------------------------------------------------
