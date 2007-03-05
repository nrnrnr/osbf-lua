local pairs, require = pairs, require

module (...)

local d = require (_PACKAGE .. 'default_cfg')

for k, v in pairs(d) do
  _M[k] = v
end

sfid_subdir = '' --- subdirectory of cache dir, if enabled
text_limit = 100000