local pairs, assert, require
    = pairs, assert, require

local table
    = table

module(...)
local util   = require(_PACKAGE .. 'util')

__doc = __doc or { }

__doc.__order = { 'classifier', 'class' }

__doc.class = [[A table of information about a class.  
The only information *required* for a class is a 'sfid', which must be
a lowercase letter that is unique to the class.  Every class must also
have a globally unique name; that name is used to find the class in
the 'classes' field of its classifier.

A class table may include other information:

  sfid          -- unique lowercase letter to identify class (required)
  sure          -- Subject: tag when mail definitely classified (defaults empty)
  unsure        -- Subject: tag when mail in reinforcement zone (defaults '?')
  train_below   -- confidence below which training is assumed needed (defaults 20)
  conf_boost    -- during classification, a number added to confidence for this 
                   class; larger boost makes the classifier more likely to choose
                   the class (default 0)
  resend        -- if this message is trained, 
                   resend it with new headers (default true)
  subclassifier -- an optional classifier for messages within this class

Sfids 's' and 'h' are reserved for 'spam' and 'ham', and sfids 'w',
'b', and 'e' are reserved for whitelisting, blacklisting, and errors.

Once the filter is well trained, training thresholds should be reduced from the 
default value of 20 to something like 10, to reduce the burden of training.
(We'd love to have an automatic reduction, but we don't have an algorithm.)

For internal clients, osbf.init adds the following fields:

  db         -- full pathname of the class database file
  open       -- function(self, mode) returns core.open_class(self.db, mode)

Usage is, e.g., classes.ham:open 'rwh'.
]]


__doc.classifier = [[tree of classes
A node is a table containing 
    feature  : function(msg) returns string
                  -- extract feature for classification and training
    rfeature : (function(msg) returns string) or nil
                  -- extract feature for extra reinforcement in training
    classes  : a table of classes indexed by name

A minimal class table might look like

  classes = { spam = { sfid = 's', resend = false },
              ham  = { sfid = 'h' },
            }

A more aggressive mail filter might contain more classes, e.g., 

  classes = { spam          = { sfid = 's', resend = false },
              work          = { sfid = 'w' },
              ecommerce     = { sfid = 'c' },
              entertainment = { sfid = 'e' },
              sports        = { sfid = 's' },
              personal      = { sfid = 'p' },
            }

A class may contain subclasses, which are classified by a subclassifier.
]]

__doc.count_leaves = [[function(classifier) returns int
Walks a classifier tree and counts the number of leaf classes.
]]

function count_leaves(c)
  local function ccount(class)
    return class.subclassifier and count_leaves(class.subclassifier) or 1
  end
  local n = 0
  for _, class in pairs(c.classes) do
    n = n + ccount(class)
  end
  return n
end


__doc.check_unique_names = [[function(classifier) does nothing or calls error
Checks the classifier to make sure every class in the tree has a unique
name.  If not, calls error().]]

function check_unique_names(classifier, ntab)
  ntab = ntab or { }
  for class, t in pairs(classifier.classes) do
    if ntab[class] then
      error('Class ' .. class .. ' is not unique within the classifier')
    else
      ntab[class] = true
    end
    if t.subclassifier then
      check_unique_names(t.subclassifier, ntab)
    end
  end
end

__doc.classes = [[function (classifier) returns class table, parent table
A class table maps the class name to the class.
The parent table contains two subtables:
  class:      maps a subclassifier to the name of its parent class
  classifier: maps a class name to its classifier
Every class has a parent classifier, but the root classifier
has no parent class.
]]

function classes(classifier)
  local ac, pc, pcf = { }, { }, { }
  local function visit(cf)
    for class, t in pairs(cf.classes) do
      assert(not ac[class], 'A class name is duplicated')
      ac [class] = t
      pcf[class] = cf
      if t.subclassifier then
        pc[t.subclassifier] = class
        visit(t.subclassifier)
      end
    end
  end
  return ac, { class = pc, classifier = pcf }
end

__doc.leaf_boosts = [[function(classifier) returns table of numbers
Visits every class in the classifier, accumulating confidence
boosts as it goes.  Return a table giving the total boost
of each leaf class, indexed by name of the class.]]

function leaf_boosts(classifier)
  local leaf_boosts = { }
  local function set_boosts(classifier, boost)
    boost = boost or 0
    for class, t in pairs(classifier.classes) do
      if t.subclassifier then
        set_boosts(t.subclassifier, boost + t.conf_boost)
      else
        leaf_boosts[class] = boost + t.conf_boost
      end
    end
  end
  return leaf_boosts
end

----------------------------------------------------------------
-- Standard classifiers

__doc.reinforce_header = [[function(class table) returns classifier
The TONE-HR classifier described in
http://osbf-lua.luaforge.net/papers/trec2006_osbf_lua.pdf
]]

local memo = util.memoize

function reinforce_header(classes)
  return {
    feature  = memo (function(m) return m:_to_orig_string():sub(1, lim) end),
    rfeature = memo (function(m) return m.__header:sub(1, lim) end),
    classes  = classes,
  }
end


__doc.subj_body = [[function(class table) returns classifier
Classifies using only Subject: line and body.
No reinforcement.]]

function subj_body(classes)
  local r = "9,¼¦y{2eÊXØþ¾¿<s"
  local function feature(m)
    return table.concat ({ m.subject or '<no-subject>', r, r, r, r, r, m.__body}, ' ')
  end
  return { feature = memo (feature), classes = classes }
end


