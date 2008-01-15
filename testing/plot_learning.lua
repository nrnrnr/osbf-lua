#!/usr/bin/lua5.1

local options      = require 'osbf3.options'
local util         = require 'osbf3.util'

options.register { long = 'window', type = options.std.number,
                   usage = '-window <number>' }

local opts, args  = options.parse(arg)

local window = opts.window and tonumber(opts.window) or 1000
local step = math.floor(window/10)

local result_file = arg[1]
if not result_file then
  io.stderr:write("Usage: ", arg[0], ' <result_file>\n')
  os.exit(1)
end

local lines = {}
for line in io.lines(result_file)  do
  if string.find(line, 'judge=') then
    table.insert(lines, line)
  end
end

if not (string.find(lines[1], ' train=true ') or
        string.find(lines[1], ' train=false ')) then
  io.stderr:write('Error: invalid result file - no "train=" field.\n')
  os.exit(1)
end

local function write_open(f)
  local h = io.open(f, 'w')
  if not h then
    io.stderr:write('Could not create file ', f, '\n')
    os.exit(1)
  end
  return h
end

local LE = write_open('le.points')
local LR = write_open('lr.points')
local num_lines = #lines
local remainder = num_lines % window

local function is_positive(line)
 return line and string.find(line, 'judge=spam')
end
local function is_negative(line)
 return line and string.find(line, 'judge=ham')
end
local function is_fp(line)
 return line and string.find(line, 'judge=ham class=spam')
end
local function is_fn(line)
 return line and string.find(line, 'judge=spam class=ham')
end
local function is_rf(line) -- is_reinforcement
  return line and string.find(line, 'judge=(.+) class=%1 train=true')
end
local function is_train(line)
  return line and string.find(line, 'train=true')
end


local pipe = {
  _in = {
    i = 1,  -- pipe input
    p = 0,  -- number of positives that entered the pipe
    n = 0,  -- number of negatives that entered the pipe
    rf = 0, -- number of reinforcements entered the pipe
    fp = 0, -- number of false positives that entered the pipe
    fn = 0, -- number of false negatives that entered the pipe
  },
  _out = {
    i = 2 - window,  -- pipe output
    p = 0,  -- number of positives that went out the pipe
    n = 0,  -- number of negatives that went out the pipe
    rf = 0, -- number of reinforcements went out the pipe
    fp = 0, -- number of false positives that went out the pipe
    fn = 0, -- number of false negatives that went out the pipe
  },

  insert = function (self, line)
    function update_counters(c)
      local line = self[c.i]
      if not line then return end
      if is_positive(line) then
        c.p = c.p + 1
      elseif is_negative(line) then
        c.n = c.n + 1
      else
        error('Invalid line: ' .. line)
      end
      if is_train(line) then
        if is_rf(line) then
          c.rf = c.rf + 1
        elseif is_fp(line) then
          c.fp = c.fp + 1
        elseif is_fn(line) then
          c.fn = c.fn + 1
        end
      end
    end
    self[self._in.i] = line
    update_counters(self._in) -- update input counters
    self._in.i = self._in.i + 1
    if self._in.i > window then self._in.i = 1 end

    update_counters(self._out) -- update output counters
    self._out.i = self._out.i + 1
    if self._out.i > window then self._out.i = 1 end
  end,

  fp_in_pipe = function (self)
    assert(self._in.fp >= self._out.fp)
    return self._in.fp - self._out.fp
  end,

  fn_in_pipe = function (self)
    assert(self._in.fn >= self._out.fn)
    return self._in.fn - self._out.fn
  end,

  rf_in_pipe = function (self)
    assert(self._in.rf >= self._out.rf)
    return self._in.rf - self._out.rf
  end,
}
 
local mt = {}
mt.__index = function(t, k) return t._in[k] end
setmetatable(pipe, mt)


for l = 1, #lines do
  pipe:insert(lines[l])
  if (l - remainder) % step == 0 then
    LE:write(
      string.format('%d %d %d %d %f %f %f\n', l, pipe:fp_in_pipe(),
                     pipe:fn_in_pipe(), pipe:rf_in_pipe(),
                     pipe.fp/pipe.n, pipe.fn/pipe.p,
                     (pipe.fp+pipe.fn)/l, pipe.rf/l))
  end
end

LE:close()

G = write_open('learning.plot')

local corpus = 'Unknown'
if #lines == 92189 then
  corpus = 'TREC 2005'
elseif #lines == 37822 then
  corpus = 'TREC 2006'
end
G:write('set title "OSBF-Lua  -  Corpus: ', corpus, ' (', pipe.p + pipe.n, ' messages)  -  Hams: ', pipe.n, '  -  Spams: ', pipe.p, '"\n')
G:write([[
set size 1.0, 0.84
set terminal png size 1024 768
set xrange [1:]], #lines, [[]
set yrange [0.00001:0.02]
set xlabel 'Number of messages processed'
set ylabel 'Rate'
set mxtics 5
set mytics 5
set grid xtics ytics mytics
set logscale y

plot 'le.points'  using 1:7 title 'Error rate' with linespoints lt -1 lw 3 ps 0, \
     'le.points'  using 1:5 title 'FP rate' with linespoints lt 3 lw 3 ps 0, \
     'le.points'  using 1:6 title 'FN rate' with linespoints lt 9 lw 3 ps 0

]])
G:close()

os.execute('gnuplot learning.plot > l.png')
os.execute('display l.png')

