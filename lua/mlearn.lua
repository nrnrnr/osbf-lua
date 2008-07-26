-- See Copyright Notice in osbf.lua

local select = select


-- experimental constants
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
--local modname = modname:gsub('[^%.]+$', 'commands')
module(modname)

local util   = require(_PACKAGE .. 'util')
local cfg    = require(_PACKAGE .. 'cfg')
local msg    = require(_PACKAGE .. 'msg')
local core   = require(_PACKAGE .. 'core')
local classifier = require(_PACKAGE .. 'classifier')

local function fingerprint(s)
  local function hex(s) return string.format('%02x', string.byte(s)) end
  return (md5.sum(s):gsub('.', hex))
end

__doc = __doc or { }

local num_leaf_classes
local all_classes, parent_classifier, parent_class = { }, { }, { }

__doc.reinforce_header = [[The standard classifier.
Uses TONE-HR to reinforce on headers when training.
Not safe to use until after configuration is loaded.
]]

do
  cfg.after_loading_do(function()
    local lim = cfg.text_limit
    local memo = util.memoize
    -- cfg.classes = nil -- not ready yet
    cfg.classifier = cfg.classifier or classifier.reinforce_header(cfg.classes)
    classifier.check_unique_names(cfg.classifier)
    local parent
    all_classes, parent = classifier.classes(cfg.classifier)
    parent_classifier, parent_class = parent.classifier, parent.class
    num_leaf_classes = classifier.count_leaves(cfg.classifier)
  end)
end

__doc.probs = [[function(classifier, msg) returns probs, probsnot
Takes as argument a classifier and a message and returns two tables.
Each table is indexed by class name; one returns the probability that
the message is in the class, and the other returns the probability that
the message is not in the class.  Invariants:

  * Probabilities of leaf classes should sum to 1
  * Probability of an internal class should be sum of children
]]

local function dbtable(classifier)
  return util.tablemap(function(t) return t:open 'r' end, classifier.classes)
end
dbtable = util.memoize(dbtable) -- not sure this is safe, but was in old code

function probs(cf, msg)
  local cflags = cfg.constants.classify_flags
  local leaves, leavesnot = { }, { }
  local function at_node(cf, prior, priornot)
    -- first compute probs and probsnot as if summing to 1
    local probs = core.classify(cf.extract(msg), dbtable(cf), cflags)
    local function prob_not(class) --- probability that it's not class
      local saved = probs[class]
      probs[class] = 0
      local answer = util.sum(util.table_sorted_values(probs))
      probs[class] = saved
      return answer
    end
    local probsnot = util.tablemapk(function(class) return prob_not(class) end, probs)

    -- now adjust both tables for the priors
    probs    = util.tablemap(function(p) return prior * p end)
    probsnot = util.tablemap(function(p) return p + priornot end)

    -- finally deal with tree structure
    for class, t in pairs(cf.classes) do
      if t.subclassifier then
        at_node(t.subclassifier, probs[class], probsnot[class])
      else
        leaves[class], leavesnot[class] = probs[class], probsnot[class]
      end
    end
  end
  at_node(cf, 1, 0)
  return leaves, leavesnot
end

__doc.confs = [[function(probs, probsnot) return table
Takes two tables indexed by class name giving P(message in class)
and P(message not in class) and returns a table giving
confidence (log odds) indexed by class name.]]

function confs(probs, probsnot)
  local conf = { }
  local n = 0
  local k = num_leaf_classes - 1
  assert(k > 0, 'Must choose among two or more classes')
  for class, prob in pairs(probs) do
    conf[class] = core.pR(prob, probsnot[class] / k) + leaf_boosts[class]
    debugf('%-20s = %9.3g; P(others) = %9.3g; pR(%s) = %.2f\n',
           'P(' .. class .. ')', probs[class], probsnot[class], class, conf[class])
  end
  return conf
end


__doc.best_class = 
[[function(classifier, message, [probs, conf]) returns class-table, conf
classifier is a classier and message is the message to be classified.

probs and conf are also optional; if given, it must be true that
  probs = $P.probs(classifier, message)              and
  conf  = $P.confs($P.probs(classifier, message))

Returns a class table for the class with the highest confidence, along
with conf as computed or passed in.

A class table contains this information:
  { class = class name, 
    conf  = confidence,
    train = boolean: message should be trained (classification is 'near error'),
  }

This function has no effect on classification counts.
]]

function best_class(cf, msg, probs, confs)
  -- find the class with the largest confidence

  if not (probs and confs) then
    if probs or confs then
      error("Classifier got probabilities or confidence but not both")
    end
    local probsnot
    probs, probsnot = _M.probs(cf, msg)
    confs = _M.confs(probs, probsnot)
  end
  local class = util.key_max(confs)
  local conf  = confs[class]
  local train = conf < all_classes[class].train_below
    debugf('Classified %s as class %s with confidence %.2f%s\n',
           table.concat(cfg.classlist(), '/'), class, pR,
           train and ' (train)' or '')
  return { class = class, conf = conf, train = train }, confs
end




__doc.bump_classification_counts = [[function(classifier, class)
Accounts for a classification into the named class by bumping
the count of every database on the path to that class.]]

function bump_classification_counts(cf, class)
  local bump = bump_classification_counts
  for c, t in pairs(cf.classes) do
    if c == class or t.subclassifier and bump(t.subclassifier, class) then
      local db = all_classes[class]:open 'rwh'
      db.classifications = db.classifications + 1 -- errors on overflow
        -- no close needed; let it be garbage-collected
      return true
    end
  end
end

----------------------------------------------------------------

__doc.learn_msg = [[function(msg, class)
Returns comment, orig_pR, new_pR or calls error

Updates databases to reflect human classification of an unlearned
message.  If new class is different from current class, adds to
false positives of current class and false negatives of new class.
Does not touch the cache or classification counts.
The message is learned even if it contains headers that make
it appear to be the output of an OSBF-Lua filter.
]]

function learn_msg(msg, class)
  local function bcc(cf) return best_class(cf, msg) end
  local conf, newconf -- confidence tables before and after training
  local bc, new_bc    -- best classes before and after training

  local function tone(target_class)
    local cf = parent_classifier[target_class]
    bc, conf = bcc(cf)

    if bc.class ~= target_class then
      -- wrong classification => train on error
      local text = cf.feature(msg)
      local db = all_classes[target_class]:open 'rw'
      db.fn = db.fn + 1
        -- We increment the false-negative counter because the current
        -- classification is wrong now, even though the original classification
        -- (which may be different because of intervening trainings) of
        -- this message may have been correct.  (The fn counter is approximate.)
      core.learn(text, db, cfg.constants.learn_flags)
      do
        local c = all_classes[bc.class]:open 'rwh'
        -- increment if less than max uint32_t
        -- should limits be hidden in lua_set_classfields?
        c.fp = c.fp + 1
        -- don't close; OK for c to be garbage collected
      end

      new_bc, newconf = bcc(cf)
      debugf("Tone after 1 FALSE_NEGATIVE training: classified %s (pR %.2f); " ..
             "target class %s\n", new_bc.class, new_bc.conf, target_class)

      -- try hard to make the starting class for tone-hr equal to the target class
      for i = 1, mistake_limit do
        if new_bc.class == target_class then break end
        core.learn(text, db, cfg.constants.learn_flags + core.EXTRA_LEARNING)
        new_bc, newconf = bcc(cf)
        debugf(" Tone %d - forcing right class: classified %s (pR %.2f); " ..
               "target class %s\n", i, new_bc.class, new_bc.conf, target_class)
      end
      util.insistf(new_bc.class == target_class, 
                   "%d trainings insufficient to reclassify %s as %s",
                   mistake_limit, new_bc.class, target_class)
    elseif bc.target_pR < all_classes[target_class].train_below then
      -- right classification but pR < training threshold => train near error
      local db = all_classes[target_class]:open 'rw'
      core.learn(text, db, cfg.constants.learn_flags)
      new_bc, newconf = bcc(cf)
      debugf("Tone - near error, after training: classified %s (pR %.2f); " ..
             "target class %s\n", new_bc.class, new_bc.conf, target_class)
    else
      -- no need to train - nothing changes
      new_bc, newconf = bc, conf
    end
  end

    
  -- This function implements reinforcement training, which is a
  -- generalization the TONE-HR training protocol described in
  -- http://osbf-lua.luaforge.net/papers/trec2006_osbf_lua.pdf
    
  local function tone_r(target_class)
    -- first train on the whole message if on or near error
    tone(target_class)
    local cf = parent_classifier[target_class]
    if cf.rfeature then
      local old_pR, new_pR = conf[target_class], newconf[target_class]
      if new_pR < all_classes[target_class].train_below
         and (new_pR - old_pR) < header_learn_threshold
      then 

        -- Iterative training on reinforcement feature only (typically
        -- the header) as described in the paper.  Continues until pR
        -- exceeds a calculated threshold or pR changes by another
        -- threshold or we run out of iterations.  Thresholds and
        -- iteration counts were determined empirically.  They probably
        -- need to be calculuated differently for each classifier, but
        -- for the moment we have only one reinforcing classifier (the
        -- TONE-HR described in the paper, so we keep the constants
        -- here, not in the classifier.)

        local db    = all_classes[target_class]:open 'rw'
        local trd   = threshold_reinforcement_degree * 
                        all_classes[target_class].train_below
        local rd    = reinforcement_degree * header_learn_threshold
        local rtext = cf.rfeature(msg)
        for i = 1, reinforcement_limit do
          -- (may exit early if the change in new_pR is big enough)
          local pR = new_pR
          core.learn(rtext, db, cfg.constants.learn_flags + core.EXTRA_LEARNING)
          new_bc, newconf = bcc(cf)
          new_pR = newconf[target_pR]
          debugf('Reinforced %d class %s: %.2f -> %.2f\n', i, target_class,
                  pR, new_pR)
          if new_pR > trd or (new_pR - pR) >= rd then
            break
          end
        end
        assert(new_bc.class == target_class)
        if new_bc.class ~= target_class then
          debugf('Reinforcement training unable to make class equal to target class\n')
        end
      end
    end
  end

  local function tone_r_to_root(target_class, interior)
    tone_r(target_class)
    debugf('Tone result: originally %s (pR %.2f), now %s (pR %.2f); ' ..
           'target %s (pR %.2f)\n', bc.class, bc.conf, new_bc.class, new_bc.conf,
           target_class, newconf[target_class])
    -- no need to guarantee same class because new code always compares
    -- old and new pR of the target class
    if new_bc.class ~= target_class then
      debugf('Tone unable to make class equal to target class\n')
    end
    local cf = parent_classifier[target_class]
    if parent_class[cf] then
      local save1, save2 = bc, conf
      tone_r_to_root(parent_class[cf], true)
      if not interior then
        bc, conf = save1, save2
        new_bc, newconf = bcc(cf) -- might be redundant; worth checking
      end
    end
  end

  -- body of learn_msg starts here
  local cf = parent_classifier[class]
  debugf('\n Learning <%s> (%s) as %s...\n', 
         fingerprint(cf.feature(msg)),
         cf.rfeature
           and string.format('reinforcing with <%s>', fingerprint(cf.rfeature(msg)))
           or  'no reinforcement',
         class)
  tone_r_to_root(class)
  local comment = bc == new_bc and
    string.format(cfg.training_not_necessary, conf[target_class],
                  all_classes[class].train_below) or
    string.format('Trained as %s: confidence %4.2f -> %4.2f', class,
                  conf[target_class], newconf[target_class])
  return comment, conf[target_class], newconf[target_class]
end




__doc.unlearn_msg = [[function(msg, class)
Returns comment, orig_pR, new_pR or calls error

Undoes the effect of the learn_msg command.  
The class must be equal to the class originally learned.
This command is for internal use only; in particular, 
it doesn't update the cache.  However, if after the 
unlearning the classification changes, this function
decrements the false positives of the new class and the
false negatives of the originally learned class.
]]

function unlearn_msg(msg, old_class)

  local function bcc(cf) return best_class(cf, msg) end
  local conf, newconf -- confidence tables before and after training
  local bc, new_bc    -- best classes before and after training

  bc, conf = bcc(cfg.classifier)
  if bc.class ~= old_class then
    debugf('Unlearning %s from class %s, but currently classifies as %s',
           tostring(msg), old_class, bc.class)
  end

  local function unlearn_r(old_class) -- undo learning and reinforcement
    local k = cfg.constants
    -- find old best class
    local cf = parent_classifier[old_class]
    core.unlearn(cf.feature(msg), db, k.learn_flags)

    if cf.rfeature then -- undo reinforcement
      local rtext = cf.rfeature(msg)
      -- find new best class
      new_bc, newconf = bcc(cf)
      for i = 1, reinforcement_limit do
        if new_bc.class == old_class and new_bc.conf > 0 then
          core.unlearn(rtext, db, k.learn_flags+core.EXTRA_LEARNING)
          new_bc, newconf = bcc(cf)
        else
          break
        end
      end
    end
    new_bc, newconf = bcc(cf)
    if new_bc.class ~= old_class then -- adjust false positives and negatives
      local db = all_classes[old_class]:open 'rw'
      if db.fn > 0 then db.fn = db.fn - 1 end
      local db = all_classes[new_bc.class]:open 'rw'
      if db.fp > 0 then db.fp = db.fp - 1 end
    end      
  end

  local function unlearn_r_to_root(old_class, interior)
    unlearn_r(old_class)
    debugf('Unlearn result: originally %s (pR %.2f), now %s (pR %.2f); ' ..
           'target %s (pR %.2f)\n', bc.class, bc.conf, new_bc.class, new_bc.conf,
           old_class, newconf[old_class])
    -- no need to guarantee same class because new code always compares
    -- old and new pR of the target class
    if new_bc.class ~= old_class then
      debugf('Unlearn unable to make class equal to target class\n')
    end
    local cf = parent_classifier[old_class]
    if parent_class[cf] then
      local save1, save2 = bc, conf
      unlearn_r_to_root(parent_class[cf], true)
      if not interior then
        bc, conf = save1, save2
        new_bc, newconf = bcc(cf)
      end
    end
  end

  -- report msg numbers not header numbers
  return string.format('Message unlearned (was %s [%4.2f], is now %s [%4.2f])',
                       old_bc.class, old_bc.conf, new_bc.class, new_bc.conf)
end

return _M
