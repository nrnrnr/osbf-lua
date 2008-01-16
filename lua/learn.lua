-- In the spirit of 'every module hides a secret', here we try to hide the
-- fact that databases must be in an ordered list and that the core code
-- will refer to databases by index, not by name.  In fact, the world outside
-- this file should refer only to class names, never to databases.  We attempt
-- to enforce this rule through the external shell script 'test-hiding'.
--
-- See Copyright Notice in osbf.lua

local select = select


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

local debug = os.getenv 'OSBF_DEBUG'
local md5, debugf -- nontrivial only when debugging
if debug then
  md5    = require 'md5' 
  debugf = function(...) return io.stderr:write(string.format(...)) end
else 
  md5    = { sum = function() return "?" end } 
  debugf = function() end
end

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

local function fingerprint(s)
  local function hex(s) return string.format('%02x', string.byte(s)) end
  return string.gsub(md5.sum(s), '.', hex)
end

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
      class_boost[class] = tbl.conf_boost
    end
  end
  cfg.after_loading_do(init)
end

if debug then
  local learn, classify = core.learn, core.classify
  core.learn = function(text, db, ...)
                 local class = string.gsub(db, '%.cfc$', '')
                 class = string.gsub(class, '.*/', '')
                 debugf("** learning %s class %s\n", fingerprint(text), class)
                 return learn(text, db, ...)
               end
  core.classify = function(text, ...)
                    local probs, trainings = classify(text, ...)
                    local out = { }
                    for _, class in ipairs(cfg.classlist()) do
                      table.insert(out, string.format("%s=%.2f", class, probs[class]))
                    end
                    debugf("** classifying %s P(%s)\n", fingerprint(text), table.concat(out, ", "))
                    return probs, trainings
                  end
end


                
local msgmod = msg

__doc.tone = [[function(text, class[, count]) returns old_pR, new_pR or errors
Conditionally train 'text' as belonging to 'class'.  Training is done
'on or near error' (TONE): if the classifier produces the wrong
classification (different from 'original'), we train with the
FALSE_NEGATIVE flag.  Otherwise, if pR (confidence) is below the training
threshold ('near error' or 'within the reinforcement zone'), we train
without the FALSE_NEGATIVE flag.

if 'count' is true, this training should also count as an initial classification.
Should be set when a script is training on messages that have never before been
classified.

class is the target class.
old_pR and new pR are the before-training and after-training pRs of the 
target class. If training was not necessary (correct and not near error), 
return identical probability ratios.
]]



local function tone_inner(text, target_class, count_as_classif)

  local old_pR, class, _, target_pR =
    most_likely_pR_and_class(text, count_as_classif, target_class)
  local target_index = class2index[target_class]

  if class ~= target_class then
    -- old_pR must be old pR of target_class
    old_pR = target_pR
    -- core.FALSE_NEGATIVE indicates that the false negative counter in
    -- the database must be incremented. This is an approximate counting
    -- because there can be cases where there was no false negative in the
    -- first classification, but, because of other trainings in between,
    -- the present classification is wrong. And vice-versa.
    core.learn(text, dblist[target_index], core.FALSE_NEGATIVE)
    do
      local c = core.open_class(dblist[class2index[class]], 'rwh')
      c.fp = c.fp + 1
      -- don't close; OK for c to be garbage collected
    end

    -- guarantee that starting class for tone-hr is the target class
    local new_pR, new_class = most_likely_pR_and_class(text)
    debugf("Tone after 1 FALSE_NEGATIVE training: classified %s (pR %.2f); target class %s\n",
           new_class, new_pR, target_class)
    for i = 1, mistake_limit do
      if new_class == target_class then break end
      core.learn(text, dblist[target_index]) -- no FALSE_NEGATIVE flag here
      new_pR, new_class = most_likely_pR_and_class(text)
      debugf(" Tone %d - forcing right class: classified %s (pR %.2f); target class %s\n",
           i, new_class, new_pR, target_class)
    end
    util.insistf(new_class == target_class, 
                 "%d trainings insufficient to reclassify %s as %s",
                 mistake_limit, class, target_class)
    return old_pR, new_pR, class, new_class
  elseif math.abs(old_pR) < overtraining_protection_threshold then
    -- N.B. We don't test 'train' here because if we reach this point,
    -- the user has decided training is needed.  Thus we use only the
    -- overtraining-protection threshold in order to protect the integrity
    -- of the database.
    core.learn(text, dblist[target_index])
    local new_pR, new_class = most_likely_pR_and_class(text)
    debugf("Tone - near error, after training: classified %s (pR %.2f -> %.2f); target class %s\n",
           new_class, old_pR, new_pR, target_class)
    return old_pR, new_pR, class, new_class
  else
    return old_pR, old_pR, class, class
  end
end

-- XXX we should be sure always to compute pR of a single class
local function tone(text, target_class, count_as_classif)
  local orig_pR, new_pR, orig_class, new_class =
    tone_inner(text, target_class, count_as_classif)
  debugf('Tone result: originally %s (pR %.2f), now %s (pR %.2f); target %s\n',
         orig_class, orig_pR, new_class, new_pR, target_class)
  assert(target_class == new_class)
  return orig_pR, new_pR
end


-- This function implements TONE-HR, a training protocol described in
-- http://osbf-lua.luaforge.net/papers/trec2006_osbf_lua.pdf

local function tone_msg_and_reinforce_header(lim, target_class, count_as_classif)
  -- train on the whole message if on or near error
  local lim_orig_msg = lim.msg
  local orig_pR, new_pR = tone(lim_orig_msg, target_class, count_as_classif)
  if cfg.classes[target_class].hr 
    and new_pR < cfg.classes[target_class].train_below + threshold_offset
    and math.abs(new_pR - orig_pR) < header_learn_threshold
  then 
    -- Iterative training on the header only (header reinforcement)
    -- as described in the paper.  Continues until pR it exceeds a
    -- calculated threshold or pR changes by another threshold or we
    -- run out of iterations.  Thresholds and iteration counts were
    -- determined empirically.
    local trd   = threshold_reinforcement_degree * offset_max_threshold
    local rd    = reinforcement_degree * header_learn_threshold
    local flags = cfg.constants.learn_flags + core.EXTRA_LEARNING
    local pR
    local index = class2index[target_class]
    local lim_orig_header = lim.header
    for i = 1, reinforcement_limit do
      -- (may exit early if the change in new_pR is big enough)
      pR = new_pR
      core.learn(lim_orig_header, dblist[index], flags)
      debugf('Reinforced %d class %s with pR = %.2f\n', i, target_class, pR)
      new_pR = most_likely_pR_and_class(lim_orig_msg)
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
  local comment, orig, new = learn_msg(msg, class)
  cache.change_file_status(sfid, status, class)

  return comment, orig, new
end  

__doc.learn_msg = [[function(msg, classification[, count, force])
Returns comment, orig_pR, new_pR or calls error

Updates databases to reflect human classification of an unlearned
message.  Does not touch the cache.  'count' should be true
if this message has never before been classified and we want to
add the initial classification to the counts in the database.
'force' should be true if we want to learn this message even though
it appears to be the output of an OSBF-Lua filter
]]

local multiheaders
cfg.after_loading_do(
  function()
    multiheaders = { }
    local pre = cfg.header_prefix
    for _, post in pairs(cfg.header_suffixes) do
      table.insert(multiheaders, pre .. '-' .. post)
    end
  end)

function learn_msg(m, class, count, force)
  if not force and msg.header_tagged(m, 'x-osbf-lua-score', unpack(multiheaders))
  then
    error('Tried to learn a message that is the *output* of an OSBF-Lua filter')
  end
  local lim = m.lim
  if type(class) ~= 'string' then error('Class passed to learn_msg is not a string')
  elseif not cfg.classes[class] then error('Unknown class: ' .. class)
  end
  debugf('\n Learning <%s> with header <%s> as %s...\n', 
         fingerprint(lim.msg), fingerprint(lim.header), class)
  local orig, new = tone_msg_and_reinforce_header(lim, class, count)
  local comment = orig == new and
    string.format(cfg.training_not_necessary, orig, cfg.classes[class].train_below) or
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
  local old_pR = most_likely_pR_and_class(lim.msg)
  local db = class2db[status]
  core.unlearn(lim.msg, db, k.learn_flags+core.FALSE_NEGATIVE)
  local pR, class = most_likely_pR_and_class(lim.msg)
  for i = 1, parms.reinforcement_limit do
    if class == status and pR > threshold_offset then
      core.unlearn(lim.header, db, k.learn_flags)
      pR, class = most_likely_pR_and_class(lim.msg)
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
[[function(msg, [probs, conf]) returns train, pR, sfid tag, subject tag, class
train is a boolean or nil; 
pR is the log of ratio of the probability for the chosen class;
it represents the confidence in the classification, where 0 is no
confidence at all (zero information) and 20 is high confidence 
(training not warranted).
tags are always strings

Probs and conf are optional arguments that must be the result
of calling commands.multiclassify on msg.lim.msg.  They are there
so some clients can avoid having to call the classifier twice;
if they are not present, classify() will call multiclassify() itself.

Note that these sfid tags are *classification* tags, not *learning* tags,
and so they are uppercase.
]]

__doc.multiclassify = 
[[function(text) returns probs table, conf table
Returns two tables: probs and conf.  Each is indexed by class.
probs[class] is the probability that the text belongs to the class.
conf[class] is the confidence that the text belongs the the class,
which is the log of the ratio of probs[class] to the average
probability of the other classes, i.e., pR(class).

Because the multiclassify function may be used for statistical
analysis of classification results, it does not increment the
'classifications' count of a database.
]]

local function wrap_subj_tag(s)
  if s and s ~= '' then return '[' .. s .. ']' else return '' end
end

__doc.most_likely_pR_and_class = 
[[function(text, count, tgt_class, probs, conf) returns pR, class, train, tgt_pR
text is the text to be classified.
flags are the flags for classification.
count is optional; if given it is a boolean indicating whether to increment
the number of classifications in the database of the most likely class.
tgt_class is optional. If given, its pR will be returned as the last argument.

probs and conf are also optional; if given, they must be the result of calling 
multiclassify() on the same text

pR the log of ratio of the probability for the chosen class;
classification is the most likely class
train is a boolean or nil; 
tgt_pR is the pR of tgt_class
]]


do
  local cflags
  cfg.after_loading_do(function() cflags = cfg.constants.classify_flags end)
  local dbtable, num_classes
  do
    local cache = { }
    function dbtable() -- must re-open every trip through...
      num_classes = 0
      for class, t in pairs(cfg.classes) do
        cache[class] = core.open_class(t.db)
        num_classes = num_classes + 1
      end
      return cache
    end
  end

  function multiclassify(text)
    local probs, trainings = core.classify(text, dbtable(), cflags)
    local function prob_not(class) --- probability that it's not class
      local saved = probs[class]
      probs[class] = 0
      local answer = util.sum(util.table_sorted_values(probs))
      probs[class] = saved
      return answer
    end

    local k = num_classes - 1
    assert(k > 0, 'Must decide most likely among two or more things')

    local conf = { }
    for class, prob in pairs(probs) do
      local Pnot = prob_not(class)
      conf[class] = core.pR(prob, Pnot / k) + class_boost[class]
      debugf('%-20s = %9.3g; P(others) = %9.3g; pR(%s) = %.2f\n',
             'P(' .. class .. ')', probs[class], Pnot, class, conf[class])
    end
    return probs, conf
  end

  function most_likely_pR_and_class(text, count, target_class, probs, conf)
    -- find the class with the largest pR

    if not (probs and conf) then
      if probs or conf then
        error("Classifier got probabilities or confidence but not both")
      end
      probs, conf = multiclassify(text)
    end
    local class = util.key_max(conf)
    local pR = conf[class]

    if count then
      local c = core.open_class(class2db[class], 'rwh')
      c.classifications = c.classifications + 1
      -- no close needed; let it be garbage-collected
    end
    local train = pR < cfg.classes[class].train_below
    debugf('Classified %s as class %s with confidence %.2f%s\n',
           table.concat(cfg.classlist(), '/'), class, pR,
           train and ' (train)' or '')
    return pR, class, train, target_class and conf[target_class]
  end
end

function classify (msg, probs, conf)
  local sfid_tag, subj_tag

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

  debugf('\nClassifying msg %s...\n', fingerprint(msg.lim.msg))
  local pR, class, train =
    most_likely_pR_and_class(msg.lim.msg, cfg.count_classifications, nil, probs, conf)
  local t = assert(cfg.classes[class], 'missing configuration for class')
  
  if not sfid_tag then
    local tag = util.insistf(t.sfid, 'missing sfid tag for %s', class)
    sfid_tag = train and tag or string.upper(tag)
  end
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
  global_error_rate = fraction of total messages classified incorrectly
where
  rate of classification of class C == fraction of messages that have class C
  error rate for class C = (FP + FN) / (Classifications + FN)
    (this is the fraction of messages that *were* or *should* *have* *been*
     assigned to class C that were assigned to the incorrect class)
full is an optional boolean. If it's not false nor nil, detailed statistics 
of the databases' usage is also calculated and included in the stats table.
]]

function stats(full)
  local stats = { }
  for class in pairs(cfg.classes) do
    stats[class] = core.stats(class2db[class], full)
  end
  local classifications, false_negatives, rates, error_rates,
        global_error_rate = 0, 0, { }, { }, 0
  for class in pairs(cfg.classes) do
    classifications = classifications + stats[class].classifications
    false_negatives = false_negatives + stats[class].false_negatives

    -- defaults in case of no classifications
    error_rates[class] = 0
    rates[class]       = 0
  end
  if classifications > 0 then
    for class in pairs(cfg.classes) do
      local s = stats[class]
      local total = s.classifications + s.false_negatives - s.false_positives
      rates[class] = total / classifications
      local total_with_errors = s.classifications + s.false_negatives
      if total_with_errors > 0 then
        error_rates[class] =
          (s.false_negatives + s.false_positives)  / total_with_errors
          -- divide by 2 here to avoid double-counting
      end
    end
    global_error_rate = false_negatives / classifications
    -- suffices to count the false negatives since every false negative is
    -- an error in another class
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
  local sfmt  = '%-30s' .. string.rep('%12.12s', #classes) .. '\n' -- string report
  local dfmt  = '%-30s' .. string.rep('%12d', #classes) .. '\n' -- integer report
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

  local function classmap(f) return unpack(util.tablemap(f, classes)) end

  hline()
  writef(sfmt, 'Database Statistics', unpack(classes))
  hline()
  writef(sfmt, 'Database version', classmap(function(c) return 'OSBF ' .. tostring(stats[c].db_version)  end))
  report('Total buckets in database', 'buckets')
  local function hbytes(class) return util.human_of_bytes(stats[class].bytes) end
  writef(sfmt, 'Size of database', classmap(hbytes))
  writef(pfmt, 'Buckets used', classmap(function(c) return stats[c].use * 100 end))
  if verbose then
    writef(sfmt, 'Database flags',
      classmap(function(c) return string.format('0x%04x', stats[c].db_flags) end))
    report('Bucket size (bytes)', 'bucket_size')
    report('Header size (bytes)', 'header_size')
    report('Number of chains', 'chains')
    report('Max chain len (buckets)', 'max_chain')
    report('Average chain len (buckets)', 'avg_chain', ffmt)
    report('Max bucket displacement', 'max_displacement')
    report('Buckets unreachable', 'unreachable')
  end

  report('Classifications', 'classifications', ffmt)
  local function instances(c)
    local s = stats[c]
    return s.classifications - s.false_positives + s.false_negatives 
  end
  writef(dfmt, 'Instances of class', classmap(instances))
  report('False negatives', 'false_negatives')
  report('False positives', 'false_positives')
  report('Trainings', 'learnings')

  if verbose then
    report('Header reinforcements', 'extra_learnings')
  end

  writef(p2fmt, 'Accuracy', classmap(function(c) return (1-error_rates[c])*100 end))
  hline()
  writef(gsfmt, 'Global accuracy:', (1-global_error_rate)*100,
         'Spam rate:', (rates.spam or 0) * 100)
  hline()
end
