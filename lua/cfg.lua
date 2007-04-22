local pairs, require, tostring
    = pairs, require, tostring

local prog = arg and arg[0] or 'OSBF'

module (...)

local d = require (_PACKAGE .. 'default_cfg')
local util = require (_PACKAGE .. 'util')

for k, v in pairs(d) do
  _M[k] = v
end

constants = util.table_read_only
  {
    classify_flags            = 0,
    count_classification_flag = 2,
    learn_flags               = 0,
    mistake_flag              = 2,
    reinforcement_flag        = 4,
  }

text_limit = 100000

function load(filename)
  local config, err = util.protected_dofile(filename)
  if not config then return nil, err end
  for k, v in pairs(config) do
    if d[k] == nil then
      util.die(prog, ': fatal error - configuration "', tostring(k),
               '" cannot be set by a user')
    else
      _M[k] = v
    end
  end
end

  