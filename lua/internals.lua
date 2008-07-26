--
-- See Copyright Notice in osbf.lua

local modname = ...
local osbfname = modname:gsub('%..-$', '')
local util = require(osbfname .. '.util')

local osbf = _G[osbfname]

local function internals(out, s, short)
  -- out: file
  -- s: optional thing to be documented
  -- short: show short documentation

  -- add undocumented functions in m to ufuns table
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

  -- show lists of documented or undocumented keys
  local function showkeys(what, t)
    local l = table.sorted_keys(t)
    if #l > 0 then
      local width = 0
      for m in pairs(t) do if m:len() > width then width = m:len() end end
      local fmt = ('  %%-%ds %%s\n'):format(width)
      out:write('\n', what, ':\n')
      for _, m in ipairs(l) do
        local module = osbf[m]
        local oneline = module and module.__doc and module.__doc.__oneline
        out:write(fmt:format(m, oneline and '-- ' .. oneline or ''))
      end
    end
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
    showkeys('Documented modules', documented)
    showkeys('Undocumented modules', undocumented)
    showkeys('Undocumented functions', ufuns)
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
      io.stderr:write('Looking for ', osbfname, '.', s, '\n')
      local ok, r = pcall (require, osbfname .. '.' .. s)
      if ok then module = s end
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
      if k:find('^__') or type(doc[k]) ~= 'string' then return end
      local d = doc[k]:gsub('\n\n', '\n  \n'):gsub('\n(.)', '\n  %1')
      local exported = type(osbf[module]) ~= 'table' or osbf[module][k] ~= nil
      if not exported then
        d = d:gsub('^%s*function', 'local function')
      end
      if short then
        d = d:gsub('\n.*', ''):gsub('%s*[%,%;%:]%s*$', '')
      end
      out:write('\n', module, exported and '.' or ': ', k, ' = ', d, final_newline(d))
    end

    if not doc then
      out:write('Internal module ', module, ' is not documented\n')
    elseif not member then -- document the whole module
      local first = doc.__order or { }
      local sorted = table.sorted_keys(doc)
      local written = { }
      if doc.__overview and not short then
        out:write('=============== Overview of module ', s, ' ===============\n\n')
        out:write(doc.__overview, final_newline(doc.__overview))
        out:write('===================================', (s:gsub('.', '=')),
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
      showkeys('Undocumented functions', undoc(module, osbf[module]))
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
