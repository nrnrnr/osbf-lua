local modname = ...
local util = require(string.gsub(modname, '[^%.]+$', 'util'))

local osbf = _G[assert(string.match(modname, '(.-)%.'))]

local function internals(out, s)
  if not s then
    local documented, undocumented = { }, { }
    for k, v in pairs(osbf) do
      if k ~= '_M' and type(v) == 'table' and v['_M'] then
        (v.__doc and documented or undocumented)[k] = true
      end
    end
    local function show(what, t)
      local l = table.sorted_keys(t)
      if #l > 0 then
        out:write(what, ':\n')
        for _, m in ipairs(l) do out:write('  ', m, '\n') end
      end
    end
    show('Documented modules', documented)
    show('Undocumented modules', undocumented)
  else
    local module, member
    if osbf[s] then
      module, member = s, nil
    else
      module, member = string.match(s, '^([^%.]+)%.([^%.]+)$')
    end
    if not module then
      out:write("There is no internal module called ", s, '\n')
      return
    end
    if not osbf[module] then
      out:write('There is no such internal module as ', module, '\n')
      return
    end
    local doc = osbf[module].__doc

    local function final_newline(s)
      return string.match(s, '\n$') and '' or '\n'
    end

    local function document(k)
      if string.find(k, '^__') then return end
      local d = string.gsub(doc[k], '\n\n', '\n  \n')
      d = string.gsub(d, '\n(.)', '\n  %1')
      out:write('\n', s, '.', k, ' = ', d, final_newline(d))
    end

    if not doc then
      out:write('Internal module ', module, ' is not documented\n')
    elseif not member then -- document the whole module
      local first = doc.__order or { }
      local sorted = table.sorted_keys(doc)
      local written = { }
      if doc.__overview then
        out:write('=============== Overview of module ', s, ' ===============\n\n')
        out:write(doc.__overview, final_newline(doc.__overview))
        out:write('===================================', string.gsub(s, '.', '='),
                  '===============\n')
      end
      for _, k in ipairs(first) do
        written[k] = true
        document(k)
      end
      for _, k in ipairs(sorted) do
        if not written[k] then
          document(k)
        end
      end
    else -- document just the member
      if not osbf[module][member] then
        out:write('There is no such thing as ', s, '\n')
      elseif not doc[member] then
        out:write(s, " seems to exist, but it's not documented")
      else
        document(member)
      end
    end
  end
end

return internals