#! /usr/bin/env lua5.1
local osbf = require 'osbf3'
local util = osbf.util
local msg = osbf.msg
local cache = osbf.cache
local commands = osbf.commands
local cfg = osbf.cfg

local options, args = util.getopt(arg, osbf.std_opts)

if not options then
  io.stderr:write(args, '\n')
  os.exit(1)
end

local trecdir = args[1] 
if not trecdir then
  print('Usage: trec.lua <trec_index_dir>')
  os.exit(1)
end
trecdir = util.append_slash(trecdir)

options['udir'] = '/tmp/osbf-lua'

osbf.init(options, true)
local num_buckets = 4000037
commands.init(num_buckets)

cfg.min_pR_success = 0
cfg.limit = 500000
local th, ts = 20, -20
local sfid_tags = { H = 'ham', ['+'] = 'ham', S = 'spam', ['-'] = 'spam' }


for l in io.lines(trecdir .. 'index') do
  local class, file = string.match(l, '^(%w+)%s+(.*)')
  local m = util.validate(msg.of_any(trecdir .. file))
  local pR, tag = commands.classify(m)
  if class == 'ham' and pR < th or class == 'spam' and pR > ts then
    local sfid = cache.generate_sfid(tag, pR)
    cache.store(sfid, msg.to_orig_string(m))
    _, _, _, new_pR = commands.learn(sfid, class)
  end
  io.write(string.format("%s %s %s %s%.4f\n",
	 file, 'judge=' .. class, 'class=' .. sfid_tags[tag], 'score=', -pR))
end
