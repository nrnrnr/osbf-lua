local f = assert(io.open '../osbf-modname.h') -- very bogus
for l in f:lines() do
  local modname = l:match('^%#define%s+OSBF_MODNAME%s+(%S+)%s*$')
  if modname then
    f:close()
    return modname
  end
end
error("Cannot find module name in header file")
