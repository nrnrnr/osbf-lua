local require, print, pairs, type, assert, tostring =
      require, print, pairs, type, assert, tostring

local io, string, table, os =
      io, string, table, os

module(...)

local cfg = require(_PACKAGE .. 'cfg')
local util = require(_PACKAGE .. 'util')

----------------------------------------------------------------
-- Utilities for managing the cache

--- A status is 'spam', 'ham', 'unlearned', or 'missing' (not in the cache).

local suffixes = { spam = '-s', ham = '-h', unlearned = '' }

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

function is_sfid(sfid)
  return type(sfid) == 'string'
	and not string.find(sfid, '%-[hs]$') -- avoid conflict with renamed sfids
	-- rightid must be a valid domain names: only letters, digits, '-' and '.'
	and string.find(sfid, '^sfid%-.-@[%a%d%.%-]+$')
end

function subdir(sfid)
  -- returns the sfid subdir
  assert(is_sfid(sfid), 'invalid sfid!')
  local sfid_subdir = '' -- empty unless specified in the config file
  if cfg.use_sfid_subdir then
    sfid_subdir = string.sub(sfid, 13, 14) .. '/' .. string.sub(sfid, 16, 17) .. '/'
  end
  return sfid_subdir
end

function filename(sfid, status)
  return util.dirfilename('cache', subdir(sfid) .. sfid, assert(suffixes[status]))
end
    
function file_and_status(sfid)
  -- returns file, status where
  --   file is either nil or a descriptor open for read
  --   status is either 'unlearned', 'spam', 'ham', or 'missing'
  --   file == nil if and only if status == 'missing'
  for status in pairs(suffixes) do
    local f = io.open(filename(sfid, status), 'r')
    if f then return f, status end
  end
  return nil, 'missing'
end

function find_sfid_file(sfid)
  -- returns the sfid filename or nil if not found
  --   status is either 'unlearned', 'spam', 'ham', or 'missing'
  --   file == nil if and only if status == 'missing'
  for status in pairs(suffixes) do
    local f = io.open(filename(sfid, status), 'r')
    if f then
      f:close()
      return filename(sfid, status), status
    end
  end
  return nil, 'missing'
end

function change_file_status(sfid, status, classification)
  if status ~= classification
  and (classification == 'unlearned' or status == 'unlearned') then
    return os.rename(filename(sfid, status), filename(sfid, classification))
  else
    return nil, 'invalid to change status from ' .. status .. ' to ' .. classification
  end
end

function generate_sfid(sfid_tag, pR)
  -- returns a new SFID
  -- if pR is not a number, 0 is used instead.
  assert(type(sfid_tag) == 'string', 'sfid_tag type must be string')
  local at_rightid = '@' .. generate_rightid()
  local leftid = string.format("sfid-%s%s-%+07.2f-", sfid_tag,
				os.date("%Y%m%d-%H%M%S"),
				type(pR) == 'number' and pR or 0)
  for i = 1, 10000 do 
    local sfid = leftid .. i .. at_rightid
    -- for safety this should be an atomic test-and-set (using file locking?)
    if not find_sfid_file(sfid) then
      return sfid
    end
  end
  return nil, "could not generate sfid"
end

function store(sfid, msg)
  -- stores a message in the cache, under the name sfid
  -- msg is a string containing the message
  local fn = find_sfid_file(sfid)
  if fn then
    return nil, 'sfid ' .. sfid .. ' is already in the cache!'
  end
  local f = assert(io.open(filename(sfid, 'unlearned'), 'w'))
  f:write(msg)
  f:close()
  return sfid
end

function remove(sfid)
  local f = find_sfid_file(sfid)
  if f then return os.remove(f) end
end
 
function recover(sfid)
  -- returns a string containing the message associated with sfid
  -- or nil, err, if sfid is not in cache
  local f, err = file_and_status(sfid)
  if f then
    local msg = f:read('*a')
    f:close()
    return msg
  else
    return f, err
  end
end

----------------------------------------------------------------
