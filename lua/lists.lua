local io, string, table, print, assert, pairs, ipairs, type, require, _G
    = io, string, table, print, assert, pairs, ipairs, type, require, _G

module (...)

local util = require(_PACKAGE .. 'util')
local cfg  = require(_PACKAGE .. 'cfg')
local msg  = require(_PACKAGE .. 'msg')

__doc = { }

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

__doc.load = [[function(name) Internal function for loading a list by name.
name: Basename of the file in the lists dir holding this list.
Returns the internal representation of the list (to be kept private).
]]
local function load(name)
  if cache[name] then
    return cache[name]
  else
    local list = util.protected_dofile(cfg.dirfilename('lists', name)) or
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

__doc.save = [[function(nname, l) Internal function for saving a list by name.
Actually works with any table in which keys are strings and values 
are strings or similar tables.  Updates the cache.
name: Basename of the file in the lists dir holding this list.
l: List to be saved.
Returns true on success; nil, msg on failure.
]]

local function save(name, l)
  cache[name] = assert(l, 'Tried to save nil as a list?!')
  local f, err = io.open(cfg.dirfilename('lists', name), 'w')
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
      assert(false, 'Cannot write value of type ' .. type(v))
    end
  end
  f:write('return ')
  writeval(l, '')
  return true
end

__doc.add = [[function(listname, part, tag, string) Adds a pair to a list.
listname: Name of the list to be added to.
part: Either strings or pats.
tag: Header tag.
string: String or pattern to be added.
Returns boolean saying if it was already there.
]]

function add(listname, part, tag, string)
  local l = load(listname)
  local t = assert(l[part], 'Table is not a list')
  local already_there = t[tag][string]
  t[tag][string] = true
  if not already_there then
    save(listname, l)
  end
  return already_there
end

__doc.del = [[function(listname, part, tag, string) Removes a pair from a list.
listname: Name of the list to be removed from.
part: Either strings or pats.
tag: Header tag.
string: String or pattern to be added.
Returns boolean saying if it was already there.
]]

function del(listname, part, tag, string)
  local l = load(listname)
  local t = assert(l[part], 'Table is not a list')
  local already_there = t[tag][string]
  t[tag][string] = nil
  local not_empty = false -- assume t[tag] is empty
  for k in pairs(t[tag]) do
    not_empty = true
    break
  end
  t[tag] = not_empty and t[tag] or nil
  if already_there then
    save(listname, l)
  end
  return already_there
end

----------------------------------------------------------------

__doc.show = [[function(listname) prints the contents of the list
in a human readable format.
listname: Name of the list to be printed.
]]
function show(listname)
  local l = load(listname)
  local stags = table.sorted_keys(l.strings, util.case_lt)
  local ptags = table.sorted_keys(l.pats, util.case_lt)
  if #stags == 0 and #ptags == 0 then
    util.write('======= ', listname, ' is empty ==========\n')
  else
    util.write('======= ', listname, ' ==========\n')
    if #stags > 0 then
      util.write('Strings:\n')
      for _, tag in ipairs(stags) do
        for s in pairs(l.strings[tag]) do
          util.write('  ', util.capitalize(tag), ': ', s, '\n')
        end
      end        
      if #ptags > 0 then util.write '\n' end
    end
    if #ptags > 0 then
      util.write('Patterns:\n')
      for _, tag in ipairs(ptags) do
        for s in pairs(l.pats[tag]) do
          util.write('  ', util.capitalize(tag), ': ', s, '\n')
        end
      end        
    end
  end
end

local progname = _G.arg and string.gsub(_G.arg[0], '.*' .. cfg.slash, '') or 'osbf'

__doc.show_op = [[function(op) returns a function that prints the necessary
commands to rebuild the list, if op == 'add', or to delete its elements if
op == 'del'.
op: name of operator. 
The returned function requires one argument:
listname: the name of the list to operate on.
]]

function show_op(op)
  return function (listname)
           local l = load(listname)
           local stags = table.sorted_keys(l.strings, util.case_lt)
           local ptags = table.sorted_keys(l.pats, util.case_lt)
           for _, tag in ipairs(stags) do
             for s in pairs(l.strings[tag]) do
               local cmd = { progname, listname, op, tag, util.os_quote(s) }
               util.write(table.concat(cmd, ' '), '\n')
             end
           end
           for _, tag in ipairs(ptags) do
             for s in pairs(l.pats[tag]) do
               local cmd = { progname, listname, op..'-pat', tag, util.os_quote(s) }
               util.write(table.concat(cmd, ' '), '\n')
             end
           end
         end
end

__doc.show_add = [[function(listname) shows thei necessary commands to
rebuild the list.]]

show_add = show_op 'add'

__doc.show_del = [[function(listname) shows the necessary commands to
deletes all elements of listname.]]

show_del = show_op 'del'

--- still missing: function print(file, listname)



----------------------------------------------------------------

--- Evaluating a command from a string.

__doc.show_cmd = [[Table that shows what arguments should be passed to list
commands. Used to check and to enumerate show commands and their names.
Commands should not be called directly but only through 'run'.
]]

show_cmd = { show = show, ['show-add'] = show_add, ['show-del'] = show_del }

local list_cmd  = { add = add, ['add-pat'] = add,
                    del = del, ['del-pat'] = del }
local list_part = { add = 'strings', ['add-pat'] = 'pats',
                    del = 'strings', ['del-pat'] = 'pats' }

__doc.run = [[function(listname, cmd, tag, arg) implements list commands.
listname: Name of the list.
cmd: Command.
tag: Tag, if needed by command.
arg: Argument, if needed by command.
Return Non-nil on success; nil, errmsg on failure.
]]

function run(listname, cmd, tag, arg)
  if show_cmd[cmd] then
    return show_cmd[cmd](listname)
  elseif not list_cmd[cmd] then
    return nil, 'Unrecognized command ' .. cmd
  elseif not tag or not arg or arg == '' then
    return nil, 'Command "' .. cmd .. '" expects a tag and an argument'
  else
    return list_cmd[cmd](listname, list_part[cmd], string.lower(tag), arg)
  end
end


__doc.runstring = [[function(listname, s) implements list commands as strings.
listname: Name of the list.
s: Command string: add[-pat] <tag> <string>.
Return Non-nil on success; nil, errmsg on failure.
]]

function runstring(listname, s)
  local cmd, tag, arg = string.match(s, '^(%S+)%s+(%S+)%s+(.*)$')
  if not cmd then
    cmd, tag, arg = unpack(util.split(s))
  end
  return run(listname, cmd, tag, arg)
end


__doc.match = [[ function(listname, m) tells whether a message matches
the list.
listname: Name of the list.
m: Message in table format.
return true if the message matches the list.
]]
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
