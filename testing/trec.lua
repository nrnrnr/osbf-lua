#! /usr/bin/env lua5.1
--#! ../osbf-lua

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

options.register { long = 'buckets', type = options.std.val, 
                   usage = '-buckets <number>|small|large' }

options.register { long = 'max', type = options.std.num, usage = '-max <number>' }

options.register { long = 'o', type = options.std.val, usage = '-o <outfile>' }

options.register { long = 'keep', type = options.std.val, help = 'keep temporary directory and files' }

local opts, args  = options.parse(arg)

local debug = os.getenv 'OSBF_DEBUG'

local trecdir = args[1] 
if not trecdir then
  print('Usage: trec.lua <trec_index_dir>')
  os.exit(1)
end
trecdir = util.append_slash(trecdir)

function os.capture(cmd, raw)
  local f, msg = io.popen(cmd, 'r')
  if not f then return nil, msg end
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
  return s
end


-- try to avoid collisions on multiple tests
local test_dir = os.capture 'tempfile -p osbf' or '/tmp/osbf-lua'
os.execute('/bin/rm -rf ' .. test_dir)
os.execute('/bin/mkdir ' .. test_dir)

opts.udir = test_dir

osbf.init(opts, true)

local bucket_sizes = { small = 94321, large = 4000037, trec = 4000037 }

local num_buckets =
  opts.buckets and (assert(bucket_sizes[opts.buckets] or tonumber(opts.buckets)))
  or 94321

local email = 'test@test'
commands.init(email, num_buckets, 'buckets')

cfg.text_limit = 500000

local opcall = pcall
pcall = function(f, ...) return true, f(...) end

local outfilename = opts.o or 'result'

local result = outfilename == '-' and io.stdout or assert(io.open(outfilename, 'w'))
local max_lines = opts.max or 5000
local num_lines = 0
local learnings = 0
local start_time = os.time()
if md5sum then os.remove(test_dir .. '/md5sums') end
for l in assert(io.lines(trecdir .. 'index')) do
  md5run('md5sum ' .. test_dir .. '/*.cfc >> ' .. test_dir .. '/md5sums')
  num_lines = num_lines + 1
  if num_lines > max_lines then
    break
  end
  local labelled, file = string.match(l, '^(%w+)%s+(.*)')
  if debug then io.stderr:write("\nMsg ", file) end 
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
end
local end_time = os.time()
local nclass = num_lines - 1
local info = string.format(
  'Using %d buckets, %d classifications (%.1f/s) require %d learnings',
  num_buckets, nclass, (nclass / os.difftime(end_time, start_time)), learnings)
result:write('# ', info, '\n')
if result ~= io.stdout then
  result:close()
end
io.stderr:write(info, '\n')
if not opts.keep then
  os.execute('/bin/rm -rf ' .. test_dir)
end

