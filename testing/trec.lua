#! /usr/bin/env lua5.1

local osbf         = require 'osbf3'
local command_line = require 'osbf3.command_line'
local options      = require 'osbf3.options'
local util         = require 'osbf3.util'
local commands     = require 'osbf3.commands'
local msg          = require 'osbf3.msg'
local cfg          = require 'osbf3.cfg'
local cache        = require 'osbf3.cache'

local opts, args   = util.validate(options.parse(arg))
if not opts then
  io.stderr:write(args, '\n')
  os.exit(1)
end

local trecdir = args[1] 
if not trecdir then
  print('Usage: trec.lua <trec_index_dir>')
  os.exit(1)
end
trecdir = util.append_slash(trecdir)

local test_dir = '/tmp/osbf-lua'
os.execute('/bin/rm -rf ' .. test_dir)
os.execute('/bin/mkdir ' .. test_dir)

opts['udir'] = test_dir

osbf.init(opts, true)
-- local db_total_size = 96009072 -- 4000037 buckets/database, used in TREC2006
local email = 'test@test'
commands.init(email, db_total_size)

cfg.min_pR_success = 0
cfg.limit = 500000
local th, ts = 20, -20
local sfid_tags = { H = 'ham', ['+'] = 'ham', S = 'spam', ['-'] = 'spam' }

local result = assert(io.open('result', 'w'))
local max_lines = 5000
local num_lines = 0
for l in assert(io.lines(trecdir .. 'index')) do
  num_lines = num_lines + 1
  if num_lines > max_lines then
    break
  end
  local class, file = string.match(l, '^(%w+)%s+(.*)')
  local m = util.validate(msg.of_any(trecdir .. file))
  local pR, tag = commands.classify(m)
  if class == 'ham' and pR < th or class == 'spam' and pR > ts then
    local sfid = cache.generate_sfid(tag, pR)
    cache.store(sfid, msg.to_orig_string(m))
    _, _, _, new_pR = commands.learn(sfid, class)
  end

  result:write(string.format("%s %s %s %s%.4f\n",
	 file, 'judge=' .. class, 'class=' .. sfid_tags[tag], 'score=', -pR))
end
result:close()
