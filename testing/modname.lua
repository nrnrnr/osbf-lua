assert(arg[0]) -- only works in a script

local function dirname(s)
  s = s:gsub('/$', '')
  local s, n = s:gsub('/[^/]*$', '')
  if n == 1 then return s else return '.' end
end

local mkfiledir = dirname(arg[0]) .. '/../handbuild/'

local function capture(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
  return s
end

-- probably needs a fix that uses Make not mk, but will do for now...

local modname = capture(string.format("(cd '%s' && mk modname)", mkfiledir))
if modname:find '%a' then
  return modname
else
  error("Cannot get module name out of mkfile")
end
