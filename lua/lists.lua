local io, string, table, print, assert, pairs, ipairs, type, require, _G
    = io, string, table, print, assert, pairs, ipairs, type, require, _G

module (...)

local util = require(_PACKAGE .. 'util')
local cfg  = require(_PACKAGE .. 'cfg')
local msg  = require(_PACKAGE .. 'msg')


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
  if cache[name] then
    return cache[name]
  else
    local list = util.protected_dofile(util.dirfilename('lists', name)) or
                 { strings = { }, pats = { } }
    for k, v in pairs(list) do
      if type(v) == 'table' then
        list[k] = util.table_tab(v) -- create new sets dynamically
      end
    end
    cache[name] = list
    return list
  end
end

--- Internal function for saving a list by name.
-- Actually works with any table in which keys are strings and values 
-- are strings or similar tables.  Updates the cache.
-- @param name Basename of the file in the lists dir holding this list.
-- @param l List to be saved.
-- @return true on success; nil, msg on failure.
local function save(name, l)
  cache[name] = assert(l, 'Tried to save nil as a list?!')
  local f, err = io.open(util.dirfilename('lists', name), 'w')
  if not f then return f, err end
  local function writeval(v, indent)
    if type(v) == 'table' then
      local nextindent = indent .. '    '
      f:write(indent, '{ ')
      for k, w in pairs(v) do
        f:write(string.format('%s  [%q] = ', indent, k))
        writeval(w, nextindent)
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
  writeval(l, '')
  return true
end

--- Add a pair to a list.
-- @param listname Name of the list to be added to.
-- @param part Either strings or pats.
-- @param tag Header tag.
-- @param string String or pattern to be added.
-- @return boolean saying if it was already there.
function add(listname, part, tag, string)
  local l = load(listname)
  local t = assert(l[part], "Table is not a list")
  local already_there = t[tag][string]
  t[tag][string] = true
  if not already_there then
    save(listname, l)
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
  local l = load(listname)
  local t = assert(l[part], "Table is not a list")
  local already_there = t[tag][string]
  t[tag][string] = nil
  if already_there then
    save(listname, l)
  end
  return already_there
end

----------------------------------------------------------------

function show(file, listname)
  local l = load(listname)
  local stags = table.sorted_keys(l.strings, util.case_lt)
  local ptags = table.sorted_keys(l.pats, util.case_lt)
  if #stags == 0 and #ptags == 0 then
    file:write('======= ', listname, ' is empty ==========\n')
  else
    file:write('======= ', listname, ' ==========\n')
    if #stags > 0 then
      file:write('Strings:\n')
      for _, tag in ipairs(stags) do
        for s in pairs(l.strings[tag]) do
          file:write('  ', util.capitalize(tag), ': ', s, '\n')
        end
      end        
      if #ptags > 0 then file:write '\n' end
    end
    if #ptags > 0 then
      file:write('Patterns:\n')
      for _, tag in ipairs(ptags) do
        for s in pairs(l.pats[tag]) do
          file:write('  ', util.capitalize(tag), ': ', s, '\n')
        end
      end        
    end
  end
end

local progname = _G.arg and string.gsub(_G.arg[0], '.*' .. cfg.slash, '') or 'osbf'

function show_op(op)
  return function (file, listname)
           local l = load(listname)
           local stags = table.sorted_keys(l.strings, util.case_lt)
           local ptags = table.sorted_keys(l.pats, util.case_lt)
           for _, tag in ipairs(stags) do
             for s in pairs(l.strings[tag]) do
               local cmd = { progname, listname, op, tag, util.os_quote(s) }
               file:write(table.concat(cmd, ' '), '\n')
             end
           end
           for _, tag in ipairs(ptags) do
             for s in pairs(l.pats[tag]) do
               local cmd = { progname, listname, op..'-pat', tag, util.os_quote(s) }
               file:write(table.concat(cmd, ' '), '\n')
             end
           end
         end
end
show_add = show_op 'add'
show_del = show_op 'del'

--- still missing: function print(file, listname)



----------------------------------------------------------------

--- Evaluating a command from a string.

--- Table that shows what arguments should be passed to list commands
--- Used to check and to enumerate show commands and their names.
-- Commands should not be called directly but only through 'run'.
show_cmd = { show = show, ['show-add'] = show_add, ['show-del'] = show_del }

local list_cmd  = { add = add, ['add-pat'] = add,
                    del = del, ['del-pat'] = del }
local list_part = { add = 'strings', ['add-pat'] = 'pats',
                    del = 'strings', ['del-pat'] = 'pats' }

--- Function to implement list commands.
-- @param listname Name of the list.
-- @param cmd Command.
-- @param tag Tag, if needed by command.
-- @param arg Argument, if needed by command.
-- @return Non-nil on success; nil, errmsg on failure.
function run(listname, cmd, tag, arg)
  if show_cmd[cmd] then
    return show_cmd[cmd](io.stdout, listname)
  elseif not list_cmd[cmd] then
    return nil, "Unrecognized command " .. cmd
  elseif not tag or not arg or arg == "" then
    return nil, "Command '" .. cmd .. "' expects a tag and an argument"
  else
    return list_cmd[cmd](listname, list_part[cmd], string.lower(tag), arg)
  end
end


--- Function to implement list commands as strings.
-- @param listname Name of the list.
-- @param s Command string: add[-pat] <tag> <string>.
-- @return Non-nil on success; nil, errmsg on failure.
function runstring(listname, s)
  local cmd, tag, arg = string.match(s, '^(%S+)%s+(%S+)%s+(.*)$')
  if not cmd then
    cmd, tag, arg = unpack(util.split(s))
  end
  return run(listname, cmd, tag, arg)
end



--- Tells whether a message matches the list.
-- @param listname Name of the list.
-- @param m Message in table format.
-- @return true if the message matches the list.
function match(listname, m)
  assert(type(m) == 'table')
  local l = load(listname)
  for tag, set in pairs(l.strings) do
    for h in msg.headers_tagged(m, tag) do
      if set[h] then return true end
    end
  end
  local find = string.find
  for tag, set in pairs(l.pats) do
    for h in msg.headers_tagged(m, tag) do
      for pat in pairs(set) do
        if find(h, pat) then return true end
      end
    end
  end
  return false
end
