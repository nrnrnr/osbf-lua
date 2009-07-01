#! /usr/bin/env lua

local osbf         = require 'osbf3'
local command_line = require 'osbf3.command_line'
local options      = require 'osbf3.options'
local util         = require 'osbf3.util'
local commands     = require 'osbf3.commands'
local msg          = require 'osbf3.msg'
local cfg          = require 'osbf3.cfg'
local cache        = require 'osbf3.cache'
local core         = require 'osbf3.core'

local md5sum = false -- compute md5 sums of databases
local md5run = md5sum and os.execute or function() end

options.register { long = 'buckets', type = options.std.val, 
                   usage = '-buckets <number>|small|large' }

options.register { long = 'max', type = options.std.num, usage = '-max <number>' }

options.register { long = 'o', type = options.std.val, usage = '-o <outfile>' }

options.register { long = 'keep', type = options.std.bool, help = 'keep temporary directory and files' }

options.register { long = 'ctimes', type = options.std.bool, help = 'compute classification rate without training' }

local opts, args  = options.parse(arg)

local debug = os.getenv 'OSBF_DEBUG'

local trecdir = args[1] 
if not trecdir then
  print('Usage: trec.lua [-ctimes] [-buckets <number>|small|large] [-max <n>] [-keep] [-o outfile] <trec_index_dir>')
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
local test_dir = os.capture 'mktemp -d' or ''
if test_dir:len() == 0 then
  test_dir = '/tmp/osbf-lua'
  os.execute('/bin/mkdir ' .. test_dir)
  os.execute('/bin/rm -rf ' .. test_dir)
end

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


local using_cache = false

local max_lines = opts.max or 5000
local learnings = 0
local start_time = os.time()
local files = { }
local nclass = 0  -- number of classifications
if md5sum then os.remove(test_dir .. '/md5sums') end

-- valid a_priori strings: LEARNINGS, INSTANCES, CLASSIFICATIONS and  MISTAKES
-- default is LEARNINGS'
core.config{a_priori = os.getenv 'PRIOR' or 'LEARNINGS'}

for l in assert(io.lines(trecdir .. 'index')) do
  md5run('md5sum ' .. test_dir .. '/*.cfc >> ' .. test_dir .. '/md5sums')
  local labelled, file = string.match(l, '^(%w+)%s+(.*)')
  if debug then io.stderr:write("\nMsg ", file) end 
  table.insert(files, file)
  --local m = msg.of_file(trecdir .. file)
  local m = msg.of_string(util.file_contents(trecdir .. file))
  -- find best class
  local bc = commands.classify(m)
  nclass = nclass + 1
  local ham_pR = bc.class == 'ham' and bc.pR or (bc.pR > 0 and -bc.pR or bc.pR)
  if bc.train or bc.class ~= labelled then
    local sfid = cache.generate_sfid(bc.sfid_tag, ham_pR)
    cache.store(sfid, msg.to_orig_string(m))
    local ok, errmsg = opcall(commands.learn, sfid, labelled)

    --local ok, errmsg = opcall(commands.learn_msg, m, labelled)
    if ok then
      learnings = learnings + 1
    else
      io.stderr:write(errmsg, '\n')
    end
  end

  result:write(string.format("%s judge=%s class=%s train=%s score=%.4f\n",
                             file, labelled, bc.class, tostring(bc.train), -ham_pR))
  if nclass >= max_lines then break end
end
local end_time = os.time()
local info = string.format(
  'Using %d buckets, %d classifications (%.1f/s) require %d learnings',
  num_buckets, nclass, (nclass / os.difftime(end_time, start_time)), learnings)
result:write('# ', info, '\n')
io.stderr:write(info, '\n')

if opts.ctimes then
  local start_time = os.time()
  for _, file in ipairs(files) do
    local m = cache.msg_of_any(trecdir .. file)
    commands.classify(m)
  end
  local end_time = os.time()
  local sec = os.difftime(end_time, start_time)
  local info = string.format(
    'Without training, %d classifications (%.1f/s) in %d:%02d',
    nclass, (nclass / sec), math.floor(sec / 60), sec % 60)
  result:write('# ', info, '\n')
  io.stderr:write(info, '\n')
end

if result ~= io.stdout then
  result:close()
end

if not opts.keep then
  os.execute('/bin/rm -rf ' .. test_dir)
end

