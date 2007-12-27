local modname = ...
local osbfname = string.gsub(modname, '%..-$', '')
local util = require(osbfname .. '.util')

local osbf = _G[osbfname]

local function internals(out, s)
  local function show(what, t)
    local l = table.sorted_keys(t)
    if #l > 0 then
      out:write('\n', what, ':\n')
      for _, m in ipairs(l) do out:write('  ', m, '\n') end
    end
  end

  local function undoc(modname, m, ufuns)
    local doc = assert(m.__doc)
    ufuns = ufuns or { }
    for f in pairs(m) do
      if not string.find(f, '^_') and not doc[f] then
        ufuns[modname .. '.' .. f] = true
      end
    end
    return ufuns
  end
    

  if not s then
    local documented, undocumented, ufuns = { }, { }, { }
    for k, v in pairs(osbf) do
      if package.loaded[osbfname .. '.' .. k] == v then
        (v.__doc and documented or undocumented)[k] = true
        if v.__doc then
          undoc(k, v, ufuns)
        end
      end
    end
    show('Documented modules', documented)
    show('Undocumented modules', undocumented)
    show('Undocumented functions', ufuns)
  else
    local module, member
    if osbf[s] then
      if type(osbf[s]) == 'table' then
        module, member = s, nil
      else
        module, member = osbfname, s
        assert(osbf[osbfname] == nil)
        osbf[osbfname] = osbf
      end
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
      local exported = type(osbf[module]) ~= 'table' or osbf[module][k] ~= nil
      if not exported then
        d = string.gsub(d, '^%s*function', 'local function')
      end
      out:write('\n', module, exported and '.' or ': ', k, ' = ', d, final_newline(d))
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
      show('Undocumented functions', undoc(module, osbf[module]))
    else -- document just the member
      if doc[member] then
        document(member)
      elseif osbf[module][member] then
        out:write(s, " seems to exist, but it's documented not")
      else
        out:write('There is no such thing as ', s, '\n')
      end
    end
  end
end

return internals
