#!/usr/bin/lua5.1

local options      = require 'osbf3.options'
options.register { long = 'window', type = options.std.number,
                   usage = '-window <number>' }

local opts, args  = options.parse(arg)

local window = opts.window and tonumber(opts.window) or 1000
local step = math.floor(window/10)
local errors = 0
local reinforcements = 0
local positives, fp = 0, 0
local negatives, fn = 0, 0

local result_file = arg[1]
if not result_file then
  io.stderr:write("Sintax: ", arg[0], ' <result_file>\n')
  os.exit(1)
end
local lines = {}
for line in io.lines(result_file) do
  if string.find(line, 'judge=') then
    table.insert(lines, line)
  end
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

local function is_fp(line)
 return line and string.find(line, 'judge=ham class=spam')
end
local function is_fn(line)
 return line and string.find(line, 'judge=spam class=ham')
end
local function is_reinforcement(line)
  return line and string.find(line, 'judge=(.+) class=%1 train=true')
end
local function is_train(line)
  return line and string.find(line, 'train=true')
end

local pipe = {
  _in = 1,
  _out = 2 - window,
  reinforcements = 0,
  fp = 0,
  fn = 0,
}

function pipe:insert(line)
    if is_train(line) then
      if is_reinforcement(line) then
        self.reinforcements = self.reinforcements + 1 
      elseif is_fp(line) then
        self.fp = self.fp + 1
        fp = fp + 1
      elseif is_fn(line) then
        self.fn = self.fn + 1
        fn = fn + 1
      end
    end
    self[self._in] = line
    self._in = self._in + 1

    if self._in > window then self._in = 1 end
    local line_out = self[self._out]
    if is_train(line_out) then
      if is_reinforcement(line_out) then
        self.reinforcements = self.reinforcements - 1 
      elseif is_fp(line_out) then
        self.fp = self.fp - 1
      elseif is_fn(line_out) then
        self.fn = self.fn - 1
      end
    end
    self._out = self._out + 1
    if self._out > window then self._out = 1 end
end
 
for l = 1, #lines do
  local line = lines[l]
  if string.find(line, 'judge=spam') then
    positives = positives + 1
  elseif string.find(line, 'judge=ham') then
    negatives = negatives + 1
  end
  if is_reinforcement(line) then
    reinforcements = reinforcements + 1
  end
  pipe:insert(line)
  if (l - remainder) % step == 0 then
    LE:write(string.format('%d %d %d %d, %f %f %f\n', l, pipe.fp, pipe.fn,
                           pipe.reinforcements, fp/negatives, fn/positives,
                           (fp+fn)/l, reinforcements/l))
  end
end

LE:close()

G = write_open('learning.plot')

if #lines == 92189 then
  G:write('set title "OSBF-Lua  -  Corpus: TREC 2005 (92,189 messages)  -  Hams: 38,399  -  Spams: 52,790"\n')
else
  G:write('set title "OSBF-Lua  -  Corpus: TREC 2006 (37,822 messages)  -  Hams: 12,910  -  Spams: 24,912"\n')
end

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

