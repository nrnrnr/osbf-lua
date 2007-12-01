#! ../osbf-lua

-- #! /usr/bin/env lua5.1

local osbf         = require 'osbf3'
local command_line = require 'osbf3.command_line'
local options      = require 'osbf3.options'
local util         = require 'osbf3.util'
local commands     = require 'osbf3.commands'
local msg          = require 'osbf3.msg'
local cfg          = require 'osbf3.cfg'
local cache        = require 'osbf3.cache'

local md5sum = false -- compute md5 sums of databases
local md5run = md5sum and os.execute or function() end

local opts, args   = options.parse(arg)

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
local num_buckets	= 94321 -- min value recommended for production
--local num_buckets	= 4000037 -- value used for TREC tests
local email = 'test@test'
commands.init(email, num_buckets, 'buckets')

cfg.text_limit = 500000

local opcall = pcall
pcall = function(f, ...) return true, f(...) end

local result = assert(io.open('result', 'w'))
local max_lines = tonumber(os.getenv 'TREC_MAX' or 5000)
local num_lines = 0
local learnings = 0
if md5sum then os.remove(test_dir .. '/md5sums') end
for l in assert(io.lines(trecdir .. 'index')) do
  md5run('md5sum ' .. test_dir .. '/*.cfc >> ' .. test_dir .. '/md5sums')
  num_lines = num_lines + 1
  if num_lines > max_lines then
    break
  end
  local labelled, file = string.match(l, '^(%w+)%s+(.*)')
  local m = msg.of_any(trecdir .. file)
  local train, pR, tag, _, class = commands.classify(m)
  pR = class == 'ham' and pR or (pR > 0 and -pR or pR)
  if train or class ~= labelled then
    local sfid = cache.generate_sfid(tag, pR)
    cache.store(sfid, msg.to_orig_string(m))
    local ok, msg = opcall(commands.learn, sfid, labelled)
    if ok then
      learnings = learnings + 1
    else
      io.stderr:write(msg, '\n')
    end
  end

  result:write(string.format("%s judge=%s class=%s score=%.4f\n",
                             file, labelled, class, -pR))
--  io.stderr:write(string.format("%s judge=%s class=%s score=%.4f\n",
--                             file, labelled, class, -pR))
end
result:close()
io.stderr:write('Test suite required ', learnings, ' learnings\n')
