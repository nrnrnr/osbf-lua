-- experimental constants
local threshold_offset			= 2
local overtraining_protection_threshold = 20 -- overtraining protection
local offset_max_threshold = threshold_offset + overtraining_protection_threshold
local header_learn_threshold            = 14 -- header overtraining protection
local reinforcement_degree              = 0.6
local reinforcement_limit               = 4
local threshold_reinforcement_degree    = 1.5

local require, print, pairs, type, assert, loadfile, setmetatable, tostring, unpack =
      require, print, pairs, type, assert, loadfile, setmetatable, tostring, unpack

local error, ipairs = 
      error, ipairs

local io, string, table, math =
      io, string, table, math

local debug_out = true and io.stderr or { write = function() end }

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

__doc.register_sfid_tag = [[function(tag, name) returns nothing or calls error
Associates the given tag with a named classification or explanation]]

local function register_sfid_tag(tag, name)
  if sfid_tags[tag] and sfid_tags[tag] ~= name then
    util.errorf('Inconsistent names %s and %s for sfid tag "%s"',
                sfid_tags[tag], name, tag)
  else
    sfid_tags[tag] = name
  end
end

local db2class, class2db, class2index, dblist, index2class, boost, classes
cfg.after_loading_do(function()
                       boost, classes = { }, { }
                       for class, tbl in pairs(cfg.classes) do
                         register_sfid_tag(string.upper(tbl.sfid), class)
                         boost[class] = assert(cfg.classes[class].pR_boost)
                         table.insert(classes, class)
                       end
                       db2class, class2db, dblist =
                         cfg.db2class, cfg.class2db, cfg.dblist
                       index2class, class2index = { }, { }
                       for i = 1, #dblist do
                         local class = db2class[dblist[i]]
                         index2class[i] = class
                         class2index[class] = class2index[class] or i
                       end
                     end)
                
local msgmod = msg

__doc.tone = [[function(text, index, original) returns old_pR, new_pR or errors
Conditionally train 'text' as belonging to database
dblist[index]. Training is actually done 'on or near error' (TONE): 
if the classifier produces the wrong classification (different from
'original'), we train with the MISTAKE flag.  Otherwise, if pR lies
within the reinforcement zone (near error), we train without the
MISTAKE flag.

If training was not necessary (correct and not near error), 
return identical probabilities.
]]



local function tone(text, index)

  local pR, cindex = most_likely_pR_and_index(text)

  if cindex ~= index then
    -- core.MISTAKE indicates that the mistake counter in the database
    -- must be incremented. This is an approximate counting because there
    -- can be cases where there was no mistake in the first
    -- classification, but because of other trainings in between, the
    -- present classification is wrong. And vice-versa.
    core.learn(text, dblist, index, core.MISTAKE)
    return pR, (most_likely_pR_and_index(text))
  elseif math.abs(pR) < overtraining_protection_threshold then
    -- N.B. We don't test 'train' here because if we reach this point,
    -- the user has decided training is needed.  Thus we use only the
    -- overtraining-protection threshold in order to protect the integrity
    -- of the database.
    core.learn(text, dblist, index)
    return pR, (most_likely_pR_and_index(text))
  else
    return pR, pR
  end
end



-- This function implements TONE-HR, a training protocol described in
-- http://osbf-lua.luaforge.net/papers/trec2006_osbf_lua.pdf

local function tone_msg_and_reinforce_header(lim_orig_msg, lim_orig_header, index)
  -- train on the whole message if on or near error
  local orig_pR, new_pR = tone(lim_orig_msg, index)
  if   new_pR > cfg.classes[index2class[index]].threshold + threshold_offset
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
    for i = 1, reinforcement_limit do
      -- (may exit early if the change in new_pR is big enough)
      pR = new_pR
      core.learn(lim_orig_header, dblist, index, k.learn_flags+core.EXTRA_LEARNING)
      debug_out:write('Reinforced ', index2class[index], ' with pR = ', pR, '\n')
      local new_class
      new_pR, new_index = most_likely_pR_and_index(lim_orig_msg, k.classify_flags)
      if new_index == index and (new_pR > trd or math.abs (pR - new_pR) >= rd) then
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

function learn(sfid, classification)
  if type(classification) ~= 'string' or not cfg.classes[classification].sfid then
    error('learn command requires one of these classes: ' .. cfg.classlist())
  end 

  local msg, status = msg.of_sfid(sfid)
  if status ~= 'unlearned' then
    error(learned_as_msg(status))
  end
  local lim = msg.lim
  local orig, new =
    tone_msg_and_reinforce_header(lim.header, lim.msg, class2index[classification])
  cache.change_file_status(sfid, status, classification)

  local comment = orig == new and
    string.format('Training not needed; score %4.2f above threshold', orig) or
    string.format('Trained as %s: %4.2f -> %4.2f', classification, orig, new)

  return comment, orig, new
end  

__doc.unlearn = [[function(sfid, classification)
Returns comment, orig_pR, new_pR or calls error

Undoes the effect of the learn command.  The classification is optional
but if present must be equal to the classification originally learned.
]]

function unlearn(sfid, classification)
  local msg, status = msg.of_sfid(sfid)
  if not msg then error('Message ' .. sfid .. ' is missing from the cache') end
  classification = classification or status -- unlearn parm now optional
  if status == 'unlearned' then
    error('This message was already unlearned or was never learned to begin with.')
  end
  if status ~= classification then
    error(string.format([[
You asked to unlearn a message that you thought had been learned as %s,
but the message was previously learned as %s.]], 
          classification, status))
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
  cache.change_file_status(sfid, classification, 'unlearned')

  return string.format('Message unlearned (was %s [%4.2f], is now %s [%4.2f])',
                       status, old_pR, class, pR)
end


----------------------------------------------------------------
-- classification seems to go with learning

__doc.sfid_tags = [[table mapping sfid tag --> meaning
Where sfid tag is tag used in headers and sfid,
and meaning is an informal explanation.  It's
all a bit confusing, but these are the *classification*
tags as opposed to the *learning* tags...
]]

sfid_tags = {
  W = 'whitelisted',
  B = 'blacklisted',
  E = 'an error in classification',
  S = 'spam',
  H = 'ham',
  ['-'] = 'spam (in the reinforcement zone)',
  ['+'] = 'ham (in the reinforcement zone)',
}

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
  local smallP, core_pR = core.smallP, core.pR
  local function most_likely_in_table(probs, size, boost)
    local max_pR, most_likely = -10000, 'this cannot happen'
    -- find the table key with the largest pR
    if not size then size = 0; for _ in pairs(probs) do size = size + 1 end end
    local k = size - 1
    assert(k > 0, 'Must decide most likely among two or more things')
    for key, P in pairs(probs) do
      local pR = core_pR(smallP + P, smallP + (1.0 - P) / k) + boost[key]
      debug_out:write(string.format('%-20s = %8.3g; P(others) = %8.3g; pR(%s) = %.2f\n',
                                  'P(' .. key .. ')',
                                  smallP + P, smallP + (1.0 - P), key, pR))
      if pR > max_pR then
        max_pR, most_likely = pR, key
      end
    end
    return max_pR, most_likely
  end

  local index_boost = { }
  setmetatable(index_boost, { __index = function() return 0 end })

  function most_likely_pR_and_index(msg, flags)
    local sum, probs, trainings = core.classify(msg, dblist, flags)
    assert(type(sum) == 'number' and type(probs) == 'table' and type(trainings) == 'table')
    return most_likely_in_table(probs, #probs, index_boost)
  end

  local class_boost
  cfg.after_loading_do(function()
                         class_boost = { }
                         for class, t in pairs(cfg.classes) do
                           class_boost[class] = t.pR_boost
                         end
                       end)

  function most_likely_pR_and_class(msg, flags)
    local sum, probs, trainings = core.classify(msg, dblist, flags)
    assert(type(sum) == 'number' and type(probs) == 'table' and type(trainings) == 'table')
    local classprobs = { }
    for i = 1, #probs do
      local class = index2class[i]
      classprobs[class] = (classprobs[class] or 0) + probs[i]
    end
    local pR, class = most_likely_in_table(classprobs, #classes, class_boost)
    local train = pR < cfg.classes[class].threshold
    debug_out:write('Classified ', table.concat(dblist, '#'),
                    ' as class ', class, ' with score ', pR,
                    train and ' (train)' or '', '\n')
    return pR, class, train
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
  local pR, class, train =
    most_likely_pR_and_class(msg.lim.msg, count_classifications_flags)
  local t = assert(cfg.classes[class], 'missing configuration for class')
  sfid_tag = sfid_tag or
    string.upper(util.insistf(t.sfid, 'missing sfid tag for %s', class))
  subj_tag = wrap_subj_tag(subj_tag or t[train and 'unsure' or 'sure'])
  return train, pR, sfid_tag, subj_tag, class
end

-----------------------------------------------------------------------------
-- calculate statistics for the special case where classes include 'spam' and 'ham'

__doc.stats = [[function(full) returns hstats, sstats, herr, rerr, srate, gerr
where
  hstats = core ham  statistics
  sstats = core spam statistics
  herr   = ham  error rate
  serr   = spam error rate
  srate  = spam rate
  gerr   = global error rate

full is optional boolean. If it's not false nor nil, detailed statistics of
the databases usage is also calculated and included in hstats and sstats.
]]

function stats(full)
  local ham_db  = (cfg.classes.ham.dbs or error 'No database for ham')[1]
  local spam_db = (cfg.classes.spam.dbs or error 'No database for spam')[1]
  local stats1 = core.stats(ham_db, full)
  local stats2 = core.stats(spam_db, full)

  ---------- compute derived statistics
  local error_rate1, error_rate2, spam_rate, global_error_rate = 0, 0, 0, 0

  if stats1.classifications + stats2.classifications > 0 then
    local function error_rate(s1, s2)
      if s1.classifications + s1.mistakes - s2.mistakes > 0 then
        return s1.mistakes / (s1.classifications + s1.mistakes - s2.mistakes)
      else
        return 0
      end
    end
    error_rate1, error_rate2 = error_rate(stats1, stats2), error_rate(stats2, stats1)
    spam_rate = (stats2.classifications + stats2.mistakes - stats1.mistakes) /
                    (stats1.classifications + stats2.classifications)
    global_error_rate = (stats1.mistakes + stats2.mistakes) /
                             (stats1.classifications + stats2.classifications)
  end
  return stats1, stats2, error_rate1, error_rate2, spam_rate, global_error_rate
end

-----------------------------------------------------------------------------
-- write statistics of the databases

__doc.write_stats = [[function(verbose)
Writes statistics of the database. If verbose is true, writes even
more statistics.
]]

function write_stats(verbose)
  local stats1, stats2, error_rate1, error_rate2, spam_rate, global_error_rate =
    stats(verbose)

  -------------- utility functions and values for writing reports

  local function writef(...) return util.write(string.format(...)) end

  local hline = string.rep('-', 54)       -- line of width 54
  local sfmt  = '%-30s%12s%12s\n'         -- string report, width 54
  local dfmt  = '%-30s%12d%12d\n'         -- integer report, width 54
  local ffmt  = '%-30s%12d%12d\n'         -- floating report, width 54
  local pfmt   ='%-30s%11.1f%%%11.1f%%\n' -- percentage report, width 54
  local p2fmt  ='%-30s%11.2f%%%11.2f%%\n' -- percentage report, width 54, 2 digits
  local gsfmt  = '%-15s%7.2f%%%22s%7.2f%%\n'  -- global accuracy & spam rate

  local hline = function() return util.write(hline, '\n') end -- tricky binding
  local function report(what, key, fmt)
    return writef(fmt or dfmt, what, stats1[key], stats2[key])
  end

  ---------------- actually issue the report

  hline()
  writef(sfmt, 'Database Statistics', 'ham', 'spam')
  hline()
  writef(sfmt, 'Database version', core._VERSION, core._VERSION)
  report('Total buckets in database', 'buckets')
  writef(sfmt, 'Size of database', util.human_of_bytes(stats1.bytes),
                                   util.human_of_bytes(stats2.bytes))
  writef(pfmt, 'Buckets used', stats1.use * 100, stats2.use * 100)
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

  writef(p2fmt, 'Accuracy', (1-error_rate1)*100, (1-error_rate2)*100)
  hline()
  writef(gsfmt, 'Global accuracy:', (1-global_error_rate)*100,
         'Spam rate:', spam_rate * 100)
  hline()
end
