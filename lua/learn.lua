-- experimental constants
local threshold_offset			= 2
local max_learn_threshold		= 20 -- overtraining protection
local header_learn_threshold            = 14 -- header overtraining protection
local reinforcement_degree              = 0.6
local ham_reinforcement_limit           = 4
local spam_reinforcement_limit          = 4
local other_reinforcement_limit         = 4
local threshold_reinforcement_degree    = 1.5

local require, print, pairs, type, assert, loadfile, setmetatable, tostring, unpack =
      require, print, pairs, type, assert, loadfile, setmetatable, tostring, unpack

local error = 
      error

local io, string, table, math =
      io, string, table, math

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

__doc = __doc or { }


-- we need more generic messages because of the email interface
-- local to_unlearn = [[To unlearn it, 
-- try ']] .. prog .. [[ unlearn [<sfid|filename>]'.]]


local function learned_as_msg(classification)
  local fmt = [[This message has already been learned as %s.  You'll need
to unlearn it before another learn operation.]]
  return string.format(fmt, classification)
end

local function cannot_unlearn_msg(old, new)
  local fmt = [[The message was learned as %s, not %s.]]
  return string.format(fmt, old, new)
end

local errmsgs = {
  learn = {
    spam = learned_as_msg 'spam',
    ham = learned_as_msg 'ham',
    missing = [[
You asked to train on a message that OSBF-Lua does not recognize.  
In a normal installation, OSBF-Lua keeps a copy of each message, but
only for a few days. The message you are trying to train with has
probably been deleted.]],
  },
  unlearn = {
    ham =  cannot_unlearn_msg('ham', 'spam'),
    spam = cannot_unlearn_msg('spam', 'ham'),
    missing = nil, -- copied below
    unlearned = [[The message was never learned to begin with.]],
  },
}

errmsgs.unlearn.missing = errmsgs.learn.missing


local learn_parms, learn_parms_minus, learn_parms_plus
  -- function given classification, returns table so that
  -- learning and unlearning code can be reused for spam and ham
do
  local pcache -- parameter cache
    -- cache results, but don't compute initially because
    -- at this point cfg table may not be fully initialized
  function learn_parms_minus(threshold)
    return {
      index = 1,  -- left child in multi tree
      threshold  = threshold_offset - threshold,
      bigger     = function(x, y) return x < y end, -- more negative
      offset_max_threshold = threshold_offset - max_learn_threshold,
      reinforcement_limit  = other_reinforcement_limit,
    }
  end
  function learn_parms_plus(threshold)
    return {
      index = 2,  -- left child in multi tree
      threshold  = threshold_offset + threshold,
      bigger     = function(x, y) return x > y end, -- more positive
      offset_max_threshold = threshold_offset + max_learn_threshold,
      reinforcement_limit  = other_reinforcement_limit,
    }
  end
  function learn_parms(classification)
    if not pcache then
      local spam, ham =
        learn_parms_minus(cfg.threshold), learn_parms_plus(cfg.threshold)
      spam.index = cfg.dbset.spam_index
      ham.index  = cfg.dbset.ham_index
      spam.trained_as = cfg.trained_as_spam
      ham.trained_as  = cfg.trained_as_ham
      pcache = { spam = spam, ham = ham }
    end
    local parms = pcache[classification]
    if not parms then error('Unknown classification ' .. classification) end
    return parms
  end
end

local msgmod = msg

__doc.dbset = [[function(treenode) return dbset
Given a multitree node, returns a dbset suitable for
core classification and learning.
]]
local function dbset(node)
  local t = assert(node.children)
  assert(#t == 2)
  return { classes = { t[1].dbname, t[2].dbname },
           ncfs = 1, delimiters = cfg.extra_delimiters or '' }
end


__doc.tone = [[function(msg, parms, dbset) returns new_pR, old_pR or errors
Conditionally train message 'msg' as belonging to database
dbset[parms.index]. Training is actually done 
'on or near error' (TONE): if the classifier produces the wrong
classification, we train with the MISTAKE flag.  Otherwise,
if pR lies within the reinforcement zone (near error), we train
without the MISTAKE flag.

If training was not necessary (correct and not near error), 
return identical probabilities.
]]

local function tone(msg, parms, dbset)

  local pR = core.classify(msg, dbset, 0)

  if parms.bigger(0, pR) then
    -- core.MISTAKE indicates that the mistake counter in the database
    -- must be incremented. This is an approximate counting because there
    -- can be cases where there was no mistake in the first
    -- classification, but because of other trainings in between, the
    -- present classification is wrong. And vice-versa.
    core.learn(msg, dbset, parms.index, core.MISTAKE)
    return (core.classify(msg, dbset, 0)), pR
  elseif math.abs(pR) < max_learn_threshold then
    core.learn(msg, dbset, parms.index, 0)
    return (core.classify(msg, dbset, 0)), pR
  else
    return pR, pR
  end
end



__doc.learn = [[function(sfid, classification)
Returns comment, status, old pR, new pR or calls error

Updates the database to reflect human classification (ham or spam)
of an unlearned message.  Also changes the message's status in the cache.
]]

-- This function implements TONE-HR, a training protocol described in
-- http://osbf-lua.luaforge.net/papers/trec2006_osbf_lua.pdf

local function tone_msg_and_reinforce_header(lim_orig_msg, lim_orig_header, parms, dbset)
  -- train on the whole message if on or near error
  local new_pR, orig_pR = tone(lim_orig_msg, parms, dbset)
  if   parms.bigger(parms.threshold, new_pR)
  and  math.abs(new_pR - orig_pR) < header_learn_threshold
  then 
    -- Iterative training on the header only (header reinforcement)
    -- as described in the paper.  Continues until pR it exceeds a
    -- calculated threshold or pR changes by another threshold or we
    -- run out of iterations.  Thresholds and iteration counts were
    -- determined empirically.
    local trd = threshold_reinforcement_degree * parms.offset_max_threshold
    local rd  = reinforcement_degree * header_learn_threshold
    local k   = cfg.constants
    local pR
    for i = 1, parms.reinforcement_limit do
      -- (may exit early if the change in new_pR is big enough)
      pR = new_pR
      core.learn(lim_orig_header, dbset, parms.index,
                 k.learn_flags+core.EXTRA_LEARNING)
      io.stderr:write('Reinforced ', dbset.classes[parms.index], ' with pR = ', pR, '\n')
      new_pR = core.classify(lim_orig_msg, dbset, k.classify_flags)
      if parms.bigger(new_pR, trd) or math.abs (pR - new_pR) >= rd then
        break
      end
    end
  end
  return orig_pR, new_pR
end


function learn(sfid, classification)
  if type(classification) ~= 'string'
  or classification ~= 'ham' and classification ~= 'spam' then
    error('learn command requires a class: "spam" or "ham".')
  end 
  local msg, status = msg.of_sfid(sfid)
  if status ~= 'unlearned' then
    error(errmsgs.learn[status])
  end -- set up tables so we can use one training procedure for either ham or spam

  local parms = learn_parms(classification)
  local orig, new =
    tone_msg_and_reinforce_header(msg.lim.header, msg.lim.msg, parms, cfg.dbset)
  cache.change_file_status(sfid, status, classification)
  local comment = 
    orig == new and string.format(cfg.training_not_necessary,
                                  new, max_learn_threshold-threshold_offset,
                                  max_learn_threshold+threshold_offset)
    or string.format('%s: %.2f -> %.2f', parms.trained_as, orig, new)
  return comment, classification, orig, new
end  

function multilearn(sfid, classification)
  local msg, status = msg.of_sfid(sfid)
  if status ~= 'unlearned' then
    error(errmsgs.learn[status] or learned_as_message(status))
  end
  local lim = msg.lim

  local trainings = { }
  local new_scores = { }
  local actually_trained = false
  local function learn(node)
    if node.classification == classification then
      return true
    elseif node.children then
      local c1, c2 = unpack(node.children)
      local l1, l2 = learn(c1), learn(c2)
      if l1 or l2 then
        local parms = l1 and c1.parms or c2.parms
        local orig, new = tone_msg_and_reinforce_header(lim.header, lim.msg, parms,
                                                        dbset(node))
        table.insert(trainings, string.format('%.2f -> %.2f', orig, new))
        table.insert(new_scores, string.format('%.2f', new))
        actually_trained = actually_trained or orig ~= new 
        return true
      else
        return false
      end
    end
  end
  learn(cfg.multitree())

  cache.change_file_status(sfid, status, classification)
  local comment
  if actually_trained then
    comment = string.format('Trained as %s: %s', classification,
                            table.concat(trainings, '; '))
  else
    comment =
      string.format('Training not needed; all scores (%s) out of learning region',
                    table.concat(new_scores, ', '))
  end
  return comment, classification
end  

__doc.unlearn = [[function(sfid, classification)
Returns comment, status, old pR, new pR
  or calls error
Undoes the effect of the learn command.  The classification is optional
but if present must be equal to the classification originally learned.
]]

function unlearn(sfid, classification)
  local msg, status = util.validate(msg.of_sfid(sfid))
  classification = classification or status -- unlearn parm now optional
  if status == 'unlearned' then
    error(errmsgs.unlearn['unlearned'])
  end
  if status ~= classification then
    error(string.format([[
You asked to unlearn a message that you thought had been learned as %s,
but %s.]], 
          classification,
          errmsgs.unlearn[status] or cannot_unlearn_msg(status, classification)))
  end

  local lim_orig_header, lim_orig_msg = msg.lim.header, msg.lim.msg

  local parms = learn_parms(classification)
  local k = cfg.constants
  local old_pR = core.classify(lim_orig_msg, cfg.dbset, k.classify_flags)
  core.unlearn(lim_orig_msg, cfg.dbset, parms.index, k.learn_flags+core.MISTAKE)
  local pR = core.classify(lim_orig_msg, cfg.dbset, k.classify_flags)
  local i = 0
  while i < parms.reinforcement_limit and parms.bigger(pR, threshold_offset) do
    core.unlearn(lim_orig_header, cfg.dbset, parms.index, k.learn_flags)
    pR = core.classify(lim_orig_msg, cfg.dbset, k.classify_flags)
    i = i + 1
  end
  cache.change_file_status(sfid, classification, 'unlearned')
  local comment =
    string.format('Message unlearned (was %s): %.2f -> %.2f',
                  classification, old_pR, pR)
  return comment, 'unlearned', old_pR, pR
end


----------------------------------------------------------------
-- classification seems to go with learning

__doc.sfid_tags = [[table mapping sfid tag --> meaning
Where sfid tag is tag used in headers and sfid,
and meaning is an informal explanation.
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

cfg.after_loading_do(function()
                       if cfg.multi then
                         for class, tag in pairs(cfg.multi.tags.sfid) do
                           register_sfid_tag(tag, class)
                         end
                       end
                     end)
                

__doc.tags = [[function(pR) returns subject-line tag, sfid tag
pR may be a numeric score or may be nil (to indicate error trying
to classify).]]

local function tags(pR)
  local zero = cfg.min_pR_success
  if pR == nil then
    return '', 'E'
  elseif pR < zero - cfg.threshold then
    return cfg.tag_spam, 'S'
  elseif pR > zero + cfg.threshold then
    return cfg.tag_ham, 'H'
  elseif pR >= zero then
    return cfg.tag_unsure_ham, '+'
  else
    assert (pR < zero)
    return cfg.tag_unsure_spam, '-'
  end
end


local msgmod = msg

__doc.classify = [[function(msgspec) returns train, pR, sfid tag, subject tag, classification
train tells whether to train
pR is a numeric score or nil; tags are always strings
]]

function classify(msg)
  local pR, sfid_tag, subj_tag

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
    sfid_tag, subj_tag = 'W', cfg.tag_ham
  elseif lists.match('blacklist', msg) then
    sfid_tag, subj_tag = 'B', cfg.tag_spam
  end

  -- continue with classification even if whitelisted or blacklisted

  local k = cfg.constants
  local count_classifications_flag =
    cfg.count_classifications and core.COUNT_CLASSIFICATIONS or 0

  local pR = core.classify(msg.lim.msg, cfg.dbset,
                           count_classifications_flag + k.classify_flags)
  if not sfid_tag then
    subj_tag, sfid_tag = tags(pR)
  end

  assert(sfid_tag and subj_tag)
  return math.abs(pR) < cfg.threshold, pR, sfid_tag, subj_tag, sfid_tag
end

__doc.multiclassify = 
[[function(msgspec) returns train, pRs, sfid tag, subject tag, classification
train is a boolean or nil; 
pRs is a nonempty list of ratios; 
tags are always strings
]]

function multiclassify (msg)
  local function wrap_subj_tag(s)
    if s then return '[' .. s .. '] ' else return '' end
  end

  msg = msgmod.of_any(msg)

  local count_classifications_flags =
    (cfg.count_classifications and core.COUNT_CLASSIFICATIONS or 0)
         + cfg.constants.classify_flags
  local ratios = { }
  local node = cfg.multitree()
  local train = false
  repeat
    assert(type(node) == 'table' and node.children)
    local pR, probs, next =
      core.classify(msg.lim.msg, dbset(node), count_classifications_flags)
    table.insert(ratios, pR)
    node = node.children[next]
    train = train or math.abs(pR) < node.threshold
    --- debugging ---
    for i = 1, #probs do
      io.stderr:write('Probability ', i, ' = ', probs[i], '\n')
    end
    io.stderr:write('Classified ', node.dbname, ' with index ', next, ', score ', pR, 
                    node.classification and ' (as ' .. node.classification .. ')'
                      or ' (no classification)', '\n')
    ----------------
  until node.classification
  local class = node.classification
  local surety = train and 'unsure' or 'sure'
  local multi = cfg.multi
  local sfid_tag = util.insistf(multi.tags.sfid[class], 'missing sfid tag for %s',class)
  local subj_tag = wrap_subj_tag(multi.tags[surety][class])
  return train, ratios, sfid_tag, subj_tag, class
end

-----------------------------------------------------------------------------
-- calculate statistics

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
  local ham_db  = cfg.dbset.classes[cfg.dbset.ham_index]
  local spam_db = cfg.dbset.classes[cfg.dbset.spam_index]
  local stats1 = util.validate(core.stats(ham_db, full))
  local stats2 = util.validate(core.stats(spam_db, full))

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
