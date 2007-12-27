-- various ROC calculations drawn from "ROC Graphs: Notes and
-- Practical Considerations for Researchers", by Tom Fawcett:
--   http://www.hpl.hp.com/techreports/2003/HPL-2003-4.pdf

local io, string = io, string -- debugging

local math, table
    = math, table

local require, pairs, ipairs, assert
    = require, pairs, ipairs, assert

module(...)

local util  = require(_PACKAGE .. 'util')


__doc = { }
__doc.__order = { 'overview', 'classification', 'point', 'graph' }
__doc.overview = [[
Produces ROC curves and calculates the areas under them.
Important types are

  classification:   result of a single classification
  point:            single ROC point in the unit rectangle
  graph:            list of points in the unit rectangle

Formulae and code are drawn from "ROC Graphs: Notes and
Practical Considerations for Researchers", by Tom Fawcett:
  http://www.hpl.hp.com/techreports/2003/HPL-2003-4.pdf
]]

__doc.classification = [[
table containing the result of a single classification.
Required fields are

  actual:    string containing the actual class of the message
  scores:    a table indexed by class giving the confidence for
             that class
]]

__doc.point = [[table with keys x and y]]

__doc.graph = [[a list of points sorted by increasing x coordinate]]

__doc.curve = [[function (class, classifications) returns graph
Given a particular class, return the ROC graph for that class vs
all the other classes, as described in equations 1 and 2 on page 19
of the technical report.  Unless there are only two classes, this 
formulation is sensitive to class skew.]]

__doc.curve2 = [[function (class1, class2, classifications) returns graph
Given a pair of classes, return the ROC graph describing the ability
of the classifier to distinguish class1 from class2.  Classifications whose
'actual' class is not class1 or class2 are ignored.
]]

__doc.area_above_hand_till = [[function(classes, classifications) returns number
Returns the unweighted pairwise discriminability of classes as described
by D. J. Hand and R. J. Till in 2001 (and summarized in section 8.2.2
of the technical report cited above).  This area is insensitive to changes 
in class distribution.
]]

__doc.area_above = [[function(graph) returns number
Given a graph on the unit rectangle, returns the area above the curve.
]]


__doc.score1 = [[function(class) returns function(classification) returns number
Given a class, returns a function that gives the score of that class as
compared against the scores of all the other classes.  This would be
    P(C) / \sum {C' ~= C} P(C')
which is equal to pR(C) * (|C|-1).  Since the ROC calculation is insensitive 
to constant factors, we simple return pR(class).
]]

__doc.score2 = [[function(class1, class2) returns
   function(classification) returns number
Here we want to compare just two classes.  I'm not sure exactly how
to justify it, but I'm hoping we can get away with pR(C1) - pR(C2)
as a measure of how much the classifier prefers class C1.
Certainly subtracting logs of ratios seems reasonable.
]]

local function memoize(score)
  local memo = { }
  return function(c)
    local s = memo[c]
    if not s then
      s = score(c)
      memo[c] = s
    end
    return s
  end
end

local function score1(class)
  return memoize(function (cfn) return assert(cfn.scores[class]) end)
end

local function score2(class1, class2)
  return memoize(function (cfn)
                   return assert(cfn.scores[class1]) - assert(cfn.scores[class2])
                 end)
end

local function sort_score(l, score)
  return table.sort(l, function(c1, c2) return score(c1) > score(c2) end)
  -- note list must be sorted *decreasing* by scores!
end
  

local function scurve(posclass, score, cfns)
  -- cfns already a fresh copy
  sort_score(cfns, score)
  local P = util.tablecount(function(c) return c.actual == posclass end, cfns)
  local N = util.tablecount(function(c) return c.actual ~= posclass end, cfns)
  local FP, TP = 0, 0
  local R = { }
  local f_prev = -math.huge
  for _, c in ipairs(cfns) do
    local f_i = score(c)
    if f_i ~= f_prev then
      R[#R+1] = { x = FP / N, y = TP / P, score = f_i, actual = c.actual,
                  s_actual = c.scores[c.actual] }
      f_prev = f_i
    end
    if c.actual == posclass then
      TP = TP + 1
    else
      FP = FP + 1
    end
  end
  R[#R+1] = { x = FP / N, y = TP / P }
  if N == 0 then for i = 1, #R do R[i].x = 1 end end
  if P == 0 then for i = 1, #R do R[i].y = 1 end end
  if R[#R].x < 1 then
    R[#R+1] = { x = 1, y = R[#R].y }
  end
  return R
end
  
function curve(class, classifications)
  return scurve(class, score1(class), util.tablecopy(classifications))
end

function curve2(c1, c2, classifications)
  local function inpair(c) return c.actual == c1 or c.actual == c2 end
  return scurve(c1, score2(c1, c2), util.tablefilter(inpair, classifications))
end


function area_above(points)
  if not points[2] then return nil, 'empty ROC curve' end
  if not ((points[1].x == 0 or points[1].y == 1) and
          (points[#points].x == 1 or points[#points].y == 1)) then
    io.stderr:write(string.format('Warning: ROC curve is (%4.2f,%4.2f)..(%4.2f,%4.2f)\n',
                                  points[1].x, points[1].y, points[2].x, points[2].y))
  end
   
  local area = 0
  for i = 1, #points-1 do
    local p1, p2 = points[i], points[i+1]
    assert(p1.x <= p2.x)
    area = area + (p2.x - p1.x) * (1 - (p1.y + p2.y) / 2)
  end
  return area
end


function area_above_hand_till(classes, classifications)
  local above = 0
  local n = 0
  for i = 1, #classes-1 do
    for j = i+1, #classes do
      local area = area_above(curve2(classes[i], classes[j], classifications))
      if area then
        above = above + area
        n = n + 1
      end
    end
  end
  local above_average = above / n
  assert(n <= #classes * (#classes - 1) / 2)
  assert(0 <= above_average and above_average <= 1)
  return above_average
end


__doc.most_likely_class = [[function (classification) returns class
Takes a classification and returns a class with a maximal score.
]]

function most_likely_class(c)
  local best, bscore = nil, -math.huge
  for class, score in pairs(c.scores) do
    if score > bscore then
      best, bscore = class, score
    end
  end
  return best or error("No scores in classification?!")
end

__doc.jgraph = [[function(file, graph[, extra])
Write the graph to 'file' as a jgraph curve,
with extra properties 'extra'.]]

function jgraph(f, curve, extras)
  f:write('newcurve\n  pts')
  for _, p in ipairs(curve) do
    f:write(' ', p.x, ' ', p.y)
    local pfx, sfx = ' (* ', ''
    for k, v in pairs(p) do
      if k ~= 'x' and k ~= 'y' then
        f:write(pfx, k, ' = ', v, ' ')
        pfx, sfx = '', '*)'
      end
    end
    f:write(sfx, '\n     ')
  end
  if extras then f:write(extras) end
  f:write '\n'
end