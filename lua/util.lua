local require, print, pairs, type, io, table =
      require, print, pairs, type, io, table

module(...)

--- Special tables.
-- Metafunction used to create a table on demand.
local function table__index(t, k) local u = { }; t[k] = u; return u end
function table_tab(t)
  setmetatable(t, { __index = table__index })
  return t
end



