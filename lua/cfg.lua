local pairs, require = pairs, require

module (...)

local d = require (_PACKAGE .. 'default_cfg')

for k, v in pairs(d) do
  _M[k] = v
end

text_limit = 100000