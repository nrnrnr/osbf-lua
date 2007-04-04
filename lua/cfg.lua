local pairs, require = pairs, require

module (...)

local d = require (_PACKAGE .. 'default_cfg')

for k, v in pairs(d) do
  _M[k] = v
end

constants =
  {
    classify_flags            = 0,
    count_classification_flag = 2,
    learn_flags               = 0,
    mistake_flag              = 2,
    reinforcement_flag        = 4,
  }

text_limit = 100000