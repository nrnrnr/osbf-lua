local io, string, print
    = io, string, print

require 'osbf.util'

local util = osbf.util

module (...)

--------------------------------------------
--- Lists.
-- A list is represented by a pair of tables.
-- The 'strings' table maps a header tag to a set of strings: 
-- in the set, each key is a string with value true.
-- The 'pats' table maps a header tag to a set of strings, each
-- of which is a pattern to be matched against the contents of 
-- a header with that tag.
-- All tags are stored in lower case.

-- Outside this module, lists are referred to only by name;
-- This code takes care of loading storing, and caching lists.

local cache = { }

--- Internal function for loading a list by name.
-- @param name Basename of the file in the lists dir holding this list.
-- @return The internal representation of the list (to be kept private).
local function load(name)
  if not cache[name] then
    local list = util.protected_dofile(util.dirfilename('lists', name)) or
      { strings = table_tab { }, pats = table_tab { } }
    cache[name] = list
  end
end

--- Internal function for saving a list by name.
-- Actually works with any table in which keys are strings and values 
-- are strings or similar tables.  Updates the cache.
-- @param name Basename of the file in the lists dir holding this list.
-- @param l List to be saved.
-- @return true on success; nil, msg on failure.
local function save(name, l)
  cache[name] = l
  local f, err = io.open(util.dirfilename('lists', name), 'w')
  if not f then return f, err end
  local function writeval(v, indent)
    if type(v) == 'table' then
      f:write(indent, '{ ')
      for k, w in pairs(v) do
        f:write(string.format('%s[%q] = ', indent, k))
        writeval(w)
        f:write(',\n')
      end
      f:write(' }')
    elseif type(v) == 'string' then
      f:write(string.format('%q', v))
    elseif type(v) == 'number' then
      f:write(string.format('%g', v))
    elseif type(v) == 'boolean' then
      f:write(v and 'true' or 'false')
    else
      assert(false, "Cannot write value of type " .. type(v))
    end
  end
  f:write('return ')
  f:writeval(l)
  return true
end

--- Add a pair to a list.
-- @param listname Name of the list to be added to.
-- @param part Either strings or pats.
-- @param tag Header tag.
-- @param string String or pattern to be added.
-- @return boolean saying if it was already there.
function add(listname, part, tag, string)
  local t = assert(load(listname)[part], "Table is not a list")
  local already_there = t[tag][string]
  t[tag][string] = true
  if not already_there then
    save(listname)
  end
  return already_there
end

--- Remove a pair from a list.
-- @param listname Name of the list to be removed from.
-- @param part Either strings or pats.
-- @param tag Header tag.
-- @param string String or pattern to be added.
-- @return boolean saying if it was already there.

function del(listname, part, tag, string)
  local t = assert(load(listname)[part], "Table is not a list")
  local already_there = t[tag][string]
  t[tag][string] = nil
  if already_there then
    save(listname)
  end
  return already_there
end

--- still missing: function 'print'

    