-- experimental constants
local threshold_offset			= 2
local max_learn_threshold		= 20 -- overtraining protection
local header_learn_threshold            = 14 -- header overtraining protection
local reinforcement_degree              = 0.6
local ham_reinforcement_limit           = 4
local spam_reinforcement_limit          = 4
local threshold_reinforcement_degree    = 1.5


local require, print, pairs, type, assert, loadfile, setmetatable =
      require, print, pairs, type, assert, loadfile, setmetatable

local io, string, table, math =
      io, string, table, math


local modname = ...
local modname = string.gsub(modname, '[^%.]+$', 'commands')
module(modname)

local util = require(_PACKAGE .. 'util')
local cfg  = require(_PACKAGE .. 'cfg')
local msg  = require(_PACKAGE .. 'msg')
local core  = require(_PACKAGE .. 'core')
local lists = require(_PACKAGE .. 'lists')


local errmsgs = {
  learn = {
    spam = [[This message has already been learned as spam.  To unlearn it,
    ...]], ham = [[This message has already been learned as ham.  To unlearn
    it, ...]], missing = [[
You asked to train on a message that OSBF-Lua does not recognize.  
In a normal installation, OSBF-Lua keeps a copy of each message, but
only for a few days.  The message you are trying to train with has
probably been deleted.]],
  },
  unlearn = {
    ham = [[the message was learned as ham, not spam]],
    spam = [[the message was learned as spam, not ham]],
    missing = [[OSBF-Lua cannot find the message---messages are kept
for only a few days, and the one you are trying to unlearn has
probably been deleted]],
    unlearned = [[the message was never learned to begin with]],
  },
}

errmsgs.unlearn.missing = errmsgs.learn.missing


local learn_parms 
  -- function given classification, returns table so that
  -- learning and unlearning code can be reused for spam and ham
do
  local cache
    -- cache results, but don't compute initially because
    -- at this point cfg table may not be fully initialized
  function learn_parms(classification)
    cache = cache or {
      spam = {
        index      = cfg.dbset.spam_index,
        threshold  = threshold_offset - cfg.threshold,
        bigger     = function(x, y) return x < y end, -- spamlike == more negative
        trained_as = cfg.trained_as_spam,
        reinforcement_limit  = spam_reinforcement_limit,
        offset_max_threshold = threshold_offset - max_learn_threshold,
      },
      ham  = {
        index      = cfg.dbset.nonspam_index,
        threshold  = threshold_offset + cfg.threshold,
        bigger     = function(x, y) return x > y end, -- hamlike == more positive
        trained_as = cfg.trained_as_nonspam,
        reinforcement_limit = ham_reinforcement_limit,
        offset_max_threshold = threshold_offset + max_learn_threshold,
      },
    }
   cache.nonspam = cache.ham
   return cache[classification]
  end
end

local msgmod = msg

-- train "msg" as belonging to class "class_index"
-- return result (true or false), new_pR, old_pR or
--        nil, error_msg
-- true means there was a training, false indicates that the
-- training was not necessary
local function train(msg, class_index)

  local pR, msg_error = core.classify(msg, cfg.dbset, 0)

  if pR then
    if ( pR <  0 and class_index == cfg.dbset.nonspam_index ) 
    or ( pR >= 0 and class_index == cfg.dbset.spam_index)
    then

      -- approximate count. there could be cases where there was no mistake
      -- in the first classification, but just a change in classification
      -- because ot other trainings - and vice versa.
      core.learn(msg, cfg.dbset, class_index, cfg.mistake_flag)
      local new_pR, msg_error = core.classify(msg, cfg.dbset, 0)
      if new_pR then
        return true, new_pR, pR
      else
        return nil, msg_error
      end

    elseif math.abs(pR) < max_learn_threshold then
      core.learn(msg, cfg.dbset, class_index, 0)
      local new_pR, msg_error = core.classify(msg, cfg.dbset, 0)
      if new_pR then
        return true, new_pR, pR
      else
        return nil, msg_error
      end
    else
      return false, pR, pR
    end
  else
    return nil, msg_error
  end
end



--- the learn command returns 
---      comment, classification, old pR, new pR
function learn(sfid, classification)
  local msg, status = msg.of_sfid(sfid)
  if status ~= 'unlearned' then
    return nil, errmsgs.learn[status]
  end -- set up tables so we can use one training procedure for either ham or spam

  local orig_msg, lim_orig_header, lim_orig_msg =
    msgmod.to_string(msg), msg.lim.header, msg.lim.msg

  local parms = learn_parms(classification)
  if not parms then return
    nil, "Unknown classification " .. classification -- error
  end

  local function iterate_training()
    local r, new_pR, orig_pR = train(orig_msg, parms.index)
    if r == nil then -- r could be false here: what is the right thing to do?
      return r, new_pR --- error
    elseif parms.bigger(parms.threshold, new_pR) and
      math.abs(new_pR - orig_pR) < header_learn_threshold
    then -- train
      local trd = threshold_reinforcement_degree * parms.offset_max_threshold
      local rd  = reinforcement_degree * header_learn_threshold
      local k   = cfg.constants
      local pR
      for i = 1, parms.reinforcement_limit do
        -- (may exit early if the change in new_pR is big enough)
        pR = new_pR
        core.learn(lim_orig_header, cfg.dbset, parms.index,
                   k.learn_flags+k.reinforcement_flag)
        new_pR, p_array = core.classify(lim_orig_msg, cfg.dbset, k.classify_flags)
        if parms.bigger(new_pR, trd) or math.abs (pR - new_pR) >= rd then
          break
        end
      end
      return orig_pR, new_pR
    else -- no training needed
      return new_pR, new_pR
    end
  end

  local orig, new = iterate_training()
  if not orig then return orig, new end -- error case
  util.change_file_status(sfid, status, classification)
  local comment = 
    orig == new and string.format(cfg.training_not_necessary,
                                  new, max_learn_threshold,
                                  max_learn_threshold)
    or string.format('%s: %.2f -> %.2f', parms.trained_as, orig, new)
  return comment, classification, orig, new
end  

function unlearn(sfid, classification)
  local msg, status = msg.of_sfid(sfid)
  classification = classification or status -- unlearn parm now optional
  if status ~= classification then
    return nil, string.format([[
You asked to unlearn a message that you thought had been learned as %s,
but %s.]], classification, errmsgs.unlearn[status])
  end

  local orig_msg, lim_orig_header, lim_orig_msg =
    msgmod.to_string(msg), msg.lim.header, msg.lim.msg

  local parms = learn_parms(classification)
  local k = cfg.constants
  local old_pR, _ = core.classify(lim_orig_msg, cfg.dbset, k.classify_flags)
  core.unlearn(orig_msg, cfg.dbset, parms.index, k.learn_flags+k.mistake_flag)
  local pR, _ = core.classify(lim_orig_msg, cfg.dbset, k.classify_flags)
  local i = 0
  while i < parms.reinforcement_limit and parms.bigger(pR, threshold_offset) do
    core.unlearn(lim_orig_header, cfg.dbset, parms.index, k.learn_flags)
    pR, _ = core.classify(lim_orig_msg, cfg.dbset, k.classify_flags)
    i = i + 1
  end
  util.change_file_status(sfid, classification, 'unlearned')
  local comment =
    string.format('Message unlearned (was %s): %.2f -> %.2f', classification,
                  old_pR, pR)
  return comment, 'unlearned', old_pR, pR
end


----------------------------------------------------------------
-- classification seems to go with learning

sfid_tags = {
  W = 'whitelisted',
  B = 'blacklisted',
  E = 'an error in classification',
  S = 'spam',
  H = 'ham',
  ['-'] = 'spam (in the reinforcement zone)',
  ['+'] = 'ham (in the reinforcement zone)',
}

-- Return subject-line tag and sfid tag for a given pR, even nil
local function tags(pR)
  local zero = cfg.min_pR_success
  if pR == nil then
    return '', 'E'
  elseif pR < zero - cfg.threshold then
    return cfg.tag_spam, 'S'
  elseif pR > zero + cfg.threshold then
    return cfg.tag_ham, "H"
  elseif pR >= zero then
    return cfg.tag_unsure_ham, "+"
  else
    assert (pR < zero)
    return cfg.tag_unsure_spam, sfid_tag
  end
end


local msgmod = msg

-- Classifies msg and returns information from most to least precise:
-- pR, sfid tag, and subject tag.
-- pR might be nil but the last two always have values
function classify(msg)
  local pR, sfid_tag, subj_tag

  msg = msgmod.of_any(msg)
  -- whitelist cache report
  if msgmod.header_tagged(msg, 'x-spamfilter-lua-whitelist') == cfg.pwd
  or lists.match('whitelist', msg)
  then
    sfid_tag, subj_tag = 'W', cfg.tag_ham
  elseif lists.match('blacklist', msg) then
    sfid_tag, subj_tag = 'B', cfg.tag_spam
  end

  -- continue with classification even if whitelisted or blacklisted

  local k = cfg.constants
  local count_classifications_flag =
    cfg.count_classifications and k.count_classification_flag or 0

  local pR, class_probs =
    core.classify(msg.lim.msg, cfg.dbset,
                  count_classifications_flag + k.classify_flags)

  if pR == nil then
     -- log error message
     -- util.log(class_probs, true)
  end

  if not sfid_tag then
    subj_tag, sfid_tag = tags(pR)
  end

  assert(sfid_tag and subj_tag)
  return pR, sfid_tag, subj_tag
end
