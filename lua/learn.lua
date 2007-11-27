-- In the spirit of 'every module hides a secret', here we try to hide the
-- fact that databases must be in an ordered list and that the core code
-- will refer to databases by index, not by name.  In fact, the world outside
-- this file should refer only to class names, never to databases.  We attempt
-- to enforce this rule through the external shell script 'test-hiding'.


-- experimental constants
local threshold_offset			= 2
local overtraining_protection_threshold = 20 -- overtraining protection
local offset_max_threshold = threshold_offset + overtraining_protection_threshold
local header_learn_threshold            = 14 -- header overtraining protection
local reinforcement_degree              = 0.6
local reinforcement_limit               = 4
local mistake_limit                     = 10 -- number of times to try to correct
                                             -- a bad classification
local threshold_reinforcement_degree    = 1.5

local require, print, pairs, type, assert, loadfile, setmetatable, tostring, unpack =
      require, print, pairs, type, assert, loadfile, setmetatable, tostring, unpack

local error, ipairs = 
      error, ipairs

local io, string, table, math =
      io, string, table, math

local use_smallP = os.getenv 'OSBF_USE_SMALLP' or true

local debug = os.getenv 'OSBF_DEBUG'
local debug_out = os.getenv 'OSBF_DEBUG' and io.stderr or { write = function() end }
local function debugf(...) return debug_out:write(string.format(...)) end

local prog = _G.arg and _G.arg[0] or 'osbf'

local modname = ...
local modname = string.gsub(modname, '[^%.]+$', 'commands')
module(modname)

local util  = require(_PACKAGE .. 'util')
local cfg   = require(_PACKAGE .. 'cfg')
local msg   = require(_PACKAGE .. 'msg')
local core  = require(_PACKAGE .. 'core')
local lists = require(_PACKAGE .. 'lists')
local cache = require(_PACKAGE .. 'cache')

local smallP = core.smallP
core.pR = assert(core.old_pR)

__doc = __doc or { }


-- we need more generic messages because of the email interface
-- local to_unlearn = [[To unlearn it, 
-- try ']] .. prog .. [[ unlearn [<sfid|filename>]'.]]


local function learned_as_msg(classification)
  local fmt = [[This message has already been learned as %s.  You'll need
to unlearn it before another learn operation.]]
  return string.format(fmt, classification)
end

local missing_msg = [[
You asked to train on a message that OSBF-Lua does not recognize.  
In a normal installation, OSBF-Lua keeps a copy of each message, but
only for a few days. The message you are trying to train with has
probably been deleted.]]

local db2class, class2db, dblist, class2index, index2class, class_boost
do
  local function init()
    db2class, class2db, dblist, class2index, index2class, class_boost =
      { }, { }, { }, { }, { }, { }
    for class, tbl in pairs(cfg.classes) do
      class2db[class] = assert(tbl.db)
      db2class[tbl.db] = class
      table.insert(dblist, tbl.db)
      class2index[class] = #dblist
      index2class[#dblist] = class
      class_boost[class] = tbl.pR_boost
    end
  end
  cfg.after_loading_do(init)
end

if debug then
  local learn, classify = core.learn, core.classify
  core.learn = function(text, dbs, i, ...)
                 local class = string.gsub(dbs[i], '%.cfc$', '')
                 class = string.gsub(class, '.*/', '')
                 debugf("** learning class %s\n", class)
                 return learn(text, dbs, i, ...)
               end
  core.classify = function(...)
                    local sum, probs, trainings = classify(...)
                    -- XXX drop sum from the outputs of core.classify
                    local out = { }
                    for i = 1, #probs do
                      table.insert(out, string.format("%s=%.2f", index2class[i], probs[i]))
                    end
                    debugf("** classifying P(%s)\n", table.concat(out, ", "))
                    return sum, probs, trainings
                  end
end


                
local msgmod = msg

__doc.tone = [[function(text, class) returns old_pR, new_pR or errors
Conditionally train 'text' as belonging to 'class'.  Training is done
'on or near error' (TONE): if the classifier produces the wrong
classification (different from 'original'), we train with the MISTAKE
flag.  Otherwise, if pR (confidence) is below the training threshold
('near error' or 'within the reinforcement zone'), we train without
the MISTAKE flag.

XXX --- need to define the exact meaning of old_pR and new_pR.  In
particular they should *always* refer to the same class, which means
the target class, no matter what the initial classification of the
message.

If training was not necessary (correct and not near error), 
return identical probabilities.
]]



local function tone_plus(text, target_class)

  local pR, class = most_likely_pR_and_class(text)
  local target_index = class2index[target_class]

  if class ~= target_class then
    -- core.MISTAKE indicates that the mistake counter in the database
    -- must be incremented. This is an approximate counting because there
    -- can be cases where there was no mistake in the first
    -- classification, but because of other trainings in between, the
    -- present classification is wrong. And vice-versa.
    core.learn(text, dblist, target_index, core.MISTAKE)

    -- guarantee that starting class for tone-hr is the target class
    local new_pR, new_class = most_likely_pR_and_class(text)
    debugf("Tone after 1 MISTAKE training: classified %s (pR %.2f); target class %s\n",
           new_class, new_pR, target_class)
    for i = 1, mistake_limit do
      if new_class == target_class then break end
      core.learn(text, dblist, target_index) -- no mistake flag here
      new_pR, new_class = most_likely_pR_and_class(text)
      debugf(" Tone - forcing right class: classified %s (pR %.2f); target class %s\n",
           new_class, new_pR, target_class)
    end
    util.insistf(new_class == target_class,
                 "%d trainings insufficient to reclassify %s as %s",
                 class, target_class)
    return pR, new_pR, class, new_class
  elseif math.abs(pR) < overtraining_protection_threshold then
    -- N.B. We don't test 'train' here because if we reach this point,
    -- the user has decided training is needed.  Thus we use only the
    -- overtraining-protection threshold in order to protect the integrity
    -- of the database.
    core.learn(text, dblist, target_index)
    local new_pR, new_class = most_likely_pR_and_class(text)
    debugf("Tone - near error, after training: classified %s (pR %.2f -> %.2f); target class %s\n",
           new_class, pR, new_pR, target_class)
    return pR, new_pR, class, new_class
  else
    return pR, pR, class, class
  end
end

-- XXX we should be sure always to compute pR of a single class
local function tone(text, target_class)
  local orig_pR, new_pR, orig_class, new_class = tone_plus(text, target_class)
  debugf('Tone result: originally %s (pR %.2f), now %s (pR %.2f); target %s\n',
         orig_class, orig_pR, new_class, new_pR, target_class)
  assert(target_class == new_class)
  return orig_pR, new_pR
end


-- This function implements TONE-HR, a training protocol described in
-- http://osbf-lua.luaforge.net/papers/trec2006_osbf_lua.pdf

local function tone_msg_and_reinforce_header(lim_orig_msg, lim_orig_header, target_class)
  -- train on the whole message if on or near error
  local orig_pR, new_pR = tone(lim_orig_msg, target_class)
  if new_pR < cfg.classes[target_class].threshold + threshold_offset
  and  math.abs(new_pR - orig_pR) < header_learn_threshold
  then 
    -- Iterative training on the header only (header reinforcement)
    -- as described in the paper.  Continues until pR it exceeds a
    -- calculated threshold or pR changes by another threshold or we
    -- run out of iterations.  Thresholds and iteration counts were
    -- determined empirically.
    local trd = threshold_reinforcement_degree * offset_max_threshold
    local rd  = reinforcement_degree * header_learn_threshold
    local k   = cfg.constants
    local pR
    local index = class2index[target_class]
    for i = 1, reinforcement_limit do
      -- (may exit early if the change in new_pR is big enough)
      pR = new_pR
      core.learn(lim_orig_header, dblist, index, k.learn_flags+core.EXTRA_LEARNING)
      debugf('Reinforced class %s with pR = %.2f\n', target_class, pR)
      new_pR = most_likely_pR_and_class(lim_orig_msg, k.classify_flags)
      if new_pR > trd or math.abs (pR - new_pR) >= rd then
        break
      end
    end
  end
  return orig_pR, new_pR
end


__doc.learn = [[function(sfid, classification)
Returns comment, orig_pR, new_pR or calls error

Updates databases to reflect human classification of an unlearned
message.  Also changes the message's status in the cache.
]]

function learn(sfid, class)
  if type(class) ~= 'string' or not cfg.classes[class].sfid then
    error('learn command requires one of these classes: ' .. cfg.classlist())
  end 

  local msg, status = msg.of_sfid(sfid)
  if status ~= 'unlearned' then
    error(learned_as_msg(status))
  end
  local lim = msg.lim
  debug_out:write('\nLearning as ', class, '...\n')
  local orig, new =
    tone_msg_and_reinforce_header(lim.header, lim.msg, class)
  cache.change_file_status(sfid, status, class)

  local comment = orig == new and
    string.format('Training not needed; confidence %4.2f above threshold', orig) or
    string.format('Trained as %s: confidence %4.2f -> %4.2f', class, orig, new)

  return comment, orig, new
end  

__doc.unlearn = [[function(sfid, class)
Returns comment, orig_pR, new_pR or calls error

Undoes the effect of the learn command.  The class is optional
but if present must be equal to the class originally learned.
]]

function unlearn(sfid, class)
  local msg, status = msg.of_sfid(sfid)
  if not msg then error('Message ' .. sfid .. ' is missing from the cache') end
  class = class or status -- unlearn parm now optional
  if status == 'unlearned' then
    error('This message was already unlearned or was never learned to begin with.')
  end
  if status ~= class then
    error(string.format([[
You asked to unlearn a message that you thought had been learned as %s,
but the message was previously learned as %s.]], 
          class, status))
  end

  local lim = msg.lim
  local k = cfg.constants
  local old_pR = most_likely_pR_and_class(lim.msg, k.classify_flags)
  local index = class2index[status]
  core.unlearn(lim.msg, dblist, index, k.learn_flags+core.MISTAKE)
  local pR, class = most_likely_pR_and_class(lim.msg, k.classify_flags)
  for i = 1, parms.reinforcement_limit do
    if class == status and pR > threshold_offset then
      core.unlearn(lim.header, dblist, index, k.learn_flags)
      pR, class = most_likely_pR_and_class(lim.msg, k.classify_flags)
    else
      break
    end
  end
  cache.change_file_status(sfid, class, 'unlearned')

  return string.format('Message unlearned (was %s [%4.2f], is now %s [%4.2f])',
                       status, old_pR, class, pR)
end


----------------------------------------------------------------
-- classification seems to go with learning

local msgmod = msg

__doc.classify = 
[[function(msgspec) returns train, pR, sfid tag, subject tag, classification
train is a boolean or nil; 
pR the log of ratio of the probability for the chosen class
tags are always strings

Note that these sfid tags are *classification* tags, not *learning* tags,
and so they are uppercase.
]]

local function wrap_subj_tag(s)
  if s and s ~= '' then return '[' .. s .. ']' else return '' end
end

__doc.most_likely_pR_and_class = 
[[function(text, flags) returns pR, classification, train
train is a boolean or nil; 
pR the log of ratio of the probability for the chosen class
]]

do
  local core_pR = core.pR
  local smallP = use_smallP and core.smallP or 0.0

  local function sum_positive_numbers(l)
    table.sort(l)
    local sum = 0
    for i = 1, #l do sum = sum + l[i] end
    return sum
  end

  function most_likely_pR_and_class(msg, flags)
    -- find the class with the largest pR
    local max_pR, most_likely = -10000, 'this cannot happen'

    local sum, probs, trainings = core.classify(msg, dblist, flags)
    assert(type(sum) == 'number' and type(probs) == 'table' and type(trainings) == 'table')
    local function prob_not(i) --- probability that it's not dblist[i]
      local others = util.tablecopy(probs)
      table.remove(others, i)
      return sum_positive_numbers(others)
    end

    assert(#probs == #dblist)
    local k = #probs - 1
    assert(k > 0, 'Must decide most likely among two or more things')

    for i, P in pairs(probs) do
      local class = index2class[i]
      local notP = prob_not(i)
      P, notP = P + smallP, notP + smallP
      local pR = core_pR(P, notP / k) + class_boost[class]
      debugf('%-20s = %8.3g; P(others) = %8.3g; pR(%s) = %.2f\n',
             'P(' .. class .. ')', P, notP, class, pR)
      if pR > max_pR then
        max_pR, most_likely = pR, class
      end
    end
    local train = max_pR < cfg.classes[most_likely].threshold
    debugf('Classified %s as class %s with confidence %.2f%s\n',
           table.concat(cfg.classlist(), '/'), most_likely, max_pR,
           train and ' (train)' or '')
    return max_pR, most_likely, train
  end
end

function classify (msg)
  local sfid_tag, subj_tag

  msg = msgmod.of_any(msg)

  -- whitelist messages with the header 'X-Spamfilter-Lua-Whitelist: <cfg.pwd>'
  -- Used mainly to whitelist the cache report
  local pwd_pat = '^.-: *' .. cfg.pwd .. '$'
  local found_pwd = false
  for i in msgmod.header_indices(msg, 'x-spamfilter-lua-whitelist') do
    if string.find(msg.headers[i], pwd_pat) then
      -- remove password from header
      msg.headers[i] = string.gsub(msg.headers[i], '^(.-:).*', '%1 Password OK')
      found_pwd = true
    end
  end
  if found_pwd or lists.match('whitelist', msg) then
    sfid_tag = 'W'
    subj_tag = cfg.classes.ham  and (cfg.classes.ham.sure  or '') or sfid_tag
  elseif lists.match('blacklist', msg) then
    sfid_tag = 'B'
    subj_tag = cfg.classes.spam and cfg.classes.spam.sure or sfid_tag
  end

  -- continue with classification even if whitelisted or blacklisted

  local count_classifications_flags =
    (cfg.count_classifications and core.COUNT_CLASSIFICATIONS or 0)
         + cfg.constants.classify_flags
  debug_out:write('\nClassifying...\n')
  local pR, class, train =
    most_likely_pR_and_class(msg.lim.msg, count_classifications_flags)
  local t = assert(cfg.classes[class], 'missing configuration for class')
  sfid_tag = sfid_tag or
    string.upper(util.insistf(t.sfid, 'missing sfid tag for %s', class))
  subj_tag = wrap_subj_tag(subj_tag or t[train and 'unsure' or 'sure'])
  return train, pR, sfid_tag, subj_tag, class
end

-----------------------------------------------------------------------------
-- calculate statistics 

__doc.stats = [[function(full) returns stats, error_rates, rates, global_error_rate
where
  stats       = table of core statistics indexed by class
  error_rates = table of error rates indexed by class
  rates       = table of rates of classification indexed by class
  global_error_rate = overall error rate of classifier

full is an optional boolean. If it's not false nor nil, detailed statistics 
of the databases' usage is also calculated and included in the stats table.
]]

function stats(full)
  local stats = { }
  for class in pairs(cfg.classes) do
    stats[class] = core.stats(class2db[class], full)
  end
  local classifications, mistakes, rates, error_rates, global_error_rate =
    0, 0, { }, { }, 0
  for class in pairs(cfg.classes) do
    classifications = classifications + stats[class].classifications
    mistakes        = mistakes        + stats[class].mistakes     

    -- defaults in case of no classifications
    error_rates[class] = 0
    rates[class]       = 0
  end
  if classifications > 0 then
    for class in pairs(cfg.classes) do
      local s = stats[class]
      local corrected = s.classifications + 2 * s.mistakes - mistakes
      if corrected > 0 then
        error_rates[class] = s.mistakes / corrected
      end
      rates[class] = corrected / classifications
    end
    global_error_rate = mistakes / classifications
  end
  return stats, error_rates, rates, global_error_rate
end

-----------------------------------------------------------------------------
-- write statistics of the databases

__doc.write_stats = [[function(verbose)
Writes statistics of the database. If verbose is true, writes even
more statistics.
]]

function write_stats(verbose)
  local stats, error_rates, rates, global_error_rate = stats(verbose)
  local classes = cfg.classlist()
  local width = 30 + 12 * #classes

  -------------- utility functions and values for writing reports

  local function writef(...) return util.write(string.format(...)) end

  local hline = string.rep('-', width)
  local sfmt  = '%-30s' .. string.rep('%12s', #classes) .. '\n' -- string report
  local sfmt  = '%-30s' .. string.rep('%12d', #classes) .. '\n' -- integer report
  local ffmt  = '%-30s' .. string.rep('%12d', #classes) .. '\n' -- floating report(!)
  local pfmt  = '%-30s' .. string.rep('%11.1f%%', #classes) .. '\n' -- percentage rpt
  local p2fmt = '%-30s' .. string.rep('%11.2f%%', #classes) .. '\n' -- 2-digit % rpt

  local gsfmt  = '%-15s%7.2f%%%22s%7.2f%%\n'  -- global accuracy & spam rate

  local hline = function() return util.write(hline, '\n') end -- tricky binding
  local function report(what, key, fmt)
    local data = { }
    for _, c in ipairs(classes) do table.insert(data, stats[c][key]) end
    return writef(fmt or dfmt, what, unpack(data))
  end

  ---------------- actually issue the report

  hline()
  writef(sfmt, 'Database Statistics', unpack(classes))
  hline()
  writef(sfmt, 'Database version', unpack(tablerep(core._VERSION, #classes)))
  report('Total buckets in database', 'buckets')
  local function hbytes(class) return util.human_of_bytes(stats[class].bytes) end
  writef(sfmt, 'Size of database', util.tablemap(hbytes, classes))
  writef(pfmt, 'Buckets used',
         util.tablemap(function(c) return stats[c].use * 100 end, classes))
  if verbose then
    report('Bucket size (bytes)', 'bucket_size')
    report('Header size (bytes)', 'header_size')
    report('Number of chains', 'chains')
    report('Max chain len (buckets)', 'max_chain')
    report('Average chain len (buckets)', 'avg_chain', ffmt)
    report('Max bucket displacement', 'max_displacement')
    report('Buckets unreachable', 'unreachable')
  end

  report('Classifications', 'classifications', ffmt)
  report('Mistakes', 'mistakes')
  report('Trainings', 'learnings')

  if verbose then
    report('Header reinforcements', 'extra_learnings')
  end

  writef(p2fmt, 'Accuracy',
         util.tablemap(function(c) return (1-error_rates[c])*100 end, classes))
  hline()
  writef(gsfmt, 'Global accuracy:', (1-global_error_rate)*100,
         'Spam rate:', (rates.spam or 0) * 100)
  hline()
end
