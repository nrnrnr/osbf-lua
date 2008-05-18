-- the role of this file is to hold disused code
-- based on the binary-tree approach to classification
-- this file should never be loaded
--
-- See Copyright Notice in osbf.lua


assert(false, 'Loaded obsolete, deprecated code')

__doc.multitree = [[The classification tree built from cfg.classes

A classification tree is a binary tree with a 'classification' at each
leaf and a database at each child.  With the database go a 'dbnames'
field (where it's databases are found in the file system), a 'parms'
table (which knows whether it's on the positive or negative side of
its parent), and a 'threshold' field (which knows whether a ratio lies
in the reinforcement zone.  An internal node has a 'children' field
which is always a list of its two children.

In more detail the fields of a tree node are as follows:
  
  In every node:
    min_pR:     a value such that larger pR's go left, smaller go right
    threshold:  half the width of the reinforcement zone for this node

  In every node except the root:
    dbnames:    a list of databases representing messages trained on
                on this node

  Only in internal nodes:
    children:   a list of two tree nodes

  Only in leaf nodes:
    classification:  the class of document (email) represented by this node


]]

local function mk_multitree()
  local function walk(prefix, node, index)
    local t = { }
    if not node then error 'bad multiclassification config' end
    if type(node) == 'table' then
      assert(#node == 2)
      local n1 = walk(prefix .. '-1', node[1], 1)
      local n2 = walk(prefix .. '-2', node[2], 2)
      t.children = { n1, n2 }
      t.threshold = math.max(n1.threshold, n2.threshold)
      t.min_pR = (n2.min_pR - n1.min_pR) / 2
    else
      t.classification = node
      t.min_pR = classes[node].min_pR or 0
      if index == 1 then t.min_pR = -t.min_pR end
      t.threshold = classes[node].threshold or default_threshold
      classes[node].threshold = t.threshold -- set to default
    end
    if index then
      if t.classification and classes[t.classification].dbnames then
        t.dbnames = { }
        for _, name in ipairs(classes[t.classification].dbnames) do
          table.insert(t.dbnames, dirs.database .. name)
        end
      else
        local edge = t.classification and '-' .. t.classification or ''
        t.dbnames = { table.concat {dirs.database, prefix, edge, '.cfc'} }
          -- for a more readable name, could use only t.classification
      end
      if t.classification then dbnames[t.classification] = t.dbnames end
      io.stderr:write('Noted dbs ', table.concat(t.dbnames, ', '), '\n')
    end
    return t
  end
  local function make_binary(t, lo, hi)
    if type(t) == 'string' then
      return t
    elseif type(t) == 'table' then
      lo = lo or 1
      hi = hi or #t
      if lo == hi then return make_binary(t[lo])
      elseif lo > hi then error 'empty category list in cfg.classes'
      elseif lo + 1 == hi then
        return { make_binary(t[lo]), make_binary(t[hi]) }
      else
        local mid = math.floor((lo + hi) / 2)
        return { make_binary(t, lo, mid), make_binary(t, mid+1, hi) }
      end
    end
  end
  multitree = walk('class', make_binary(classes))
end



__doc.dbset = [[function(treenode) return dbset
Given a multitree node, returns a dbset suitable for
core classification and learning.
]]
local function dbset(node)
  if not node.dbset then 
    local t = assert(node.children)
    assert(#t == 2)
    local classes = { unpack(t[1].dbnames) }
    for _, d in ipairs(t[2].dbnames) do table.insert(classes, d) end
    node.dbset = { classes = classes, ncfs = #t[1].dbnames,
                   delimiters = cfg.extra_delimiters or '' }
  end
  return node.dbset
end





  local count_classifications_flags =
    (cfg.count_classifications and core.COUNT_CLASSIFICATIONS or 0)
         + cfg.constants.classify_flags
  local ratios = { }
  local node = cfg.multitree
  local train = false
  repeat
    assert(type(node) == 'table' and node.children and #node.children == 2)
    local pR, probs =
      core.classify(msg.lim.msg, dbset(node), count_classifications_flags)
    table.insert(ratios, pR)
    local next = pR > node.min_pR and 1 or 2
    --- debugging ---
    do
      local dbnames = dbset(node).classes
      for i = 1, #probs do
        debug_out:write('Probability ', i, ' = ', probs[i], ' (', dbnames[i], ')\n')
      end
    end
    ----------------
    node = node.children[next]
    train = train or math.abs(pR - node.min_pR) < node.threshold
    --- debugging ---
    debug_out:write('Classified ', table.concat(node.dbnames, '/'),
                    ' with index ', next, ', score ', pR, ' vs min = ', node.min_pR, 
                    node.classification and ' (as ' .. node.classification .. ')'
                      or ' (no classification)', '\n')
    ----------------
  until node.classification
  local class = node.classification
  local t = assert(cfg.classes[class], 'missing configuration for class')


function cfg.init(email, totalsize, lang)
  local ds = { dirs.user, dirs.database, dirs.lists, dirs.cache, dirs.log }
  for _, d in ipairs(ds) do
    util.mkdir(d)
  end

  local dbcount = 0
  local function walk(t)
    if t.dbnames then dbcount = dbcount + #t.dbnames end
    if t.children then for _, c in ipairs(t.children) do walk(c) end end
  end
  walk(cfg.multitree)
  totalsize = totalsize or dbcount * cfg.constants.default_db_megabytes * 1024 * 1024
  if type(totalsize) ~= 'number' then
    util.die('Database size must be a number')
  end
  local dbsize = totalsize / dbcount
  -- create new, empty databases
  local totalbytes = 0
  local function walk(t)
    for _, db in ipairs(t.dbnames or { }) do
      totalbytes = totalbytes + create_single_db(db, dbsize)
    end
    if t.children then walk(t.children[1]); walk(t.children[2]) end
  end    
  walk(cfg.multitree)
  local config = cfg.configfile
  if util.file_is_readable(config) then
    output.error:write('Warning: not overwriting existing ', config, '\n')
  else
    local default = util.submodule_path 'default_cfg'
    local f = util.validate(io.open(default, 'r'))
    local u = util.validate(io.open(config, 'w'))
    local x = f:read '*a'
    -- sets initial password to a random string
    x = string.gsub(x, '(pwd%s*=%s*)[^\r\n]*',
      string.format('%%1%q,', util.generate_pwd()))
    -- sets email address for commands 
    x = string.gsub(x, '(command_address%s*=%s*)[^\r\n]*',
      string.format('%%1%q,', email))
    -- sets report_locale
    if lang then
      x = string.gsub(x, '(report_locale%s*=%s*)[^\r\n]*',
        string.format('%%1%q,', lang))
    end
    u:write(x)
    f:close()
    u:close()
  end
  return totalbytes --- total bytes consumed by databases
end



function learn(sfid, classification)
  if type(classification) ~= 'string' or not cfg.classes[classification].sfid then
    error('learn command requires one of these classes: ' .. cfg.classlist())
  end 

  local msg, status = msg.of_sfid(sfid)
  if status ~= 'unlearned' then
    error(learned_as_message(status))
  end
  local lim = msg.lim

  local trainings = { }
  local actually_trained = false
  local function learn(node)
    if node.classification == classification then
      return true
    elseif node.children then
      local c1, c2 = unpack(node.children)
      local l1, l2 = learn(c1), learn(c2)
      if l1 or l2 then
        local parms = l1 and c1.parms or c2.parms
        local orig, new =
          tone_msg_and_reinforce_header(lim.header, lim.msg, parms, dbset(node))
        table.insert(trainings, { orig = orig, new = new, class = node.classification })
        actually_trained = actually_trained or orig ~= new 
        return true
      end
    end
  end
  learn(cfg.multitree)

  cache.change_file_status(sfid, status, classification)

  if actually_trained then
    return string.format('Trained as %s: %s', classification,
                         training_string(trainings)), trainings
  else
    return string.format('Training not needed; all scores (%s) out of learning region',
                         new_scores(trainings)), trainings
  end
end  

__doc.unlearn = [[function(sfid, classification)
Returns comment, trainings or calls error

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
  local trainings = { }
  local function unlearn(node)
    if node.classification == classification then
      return true
    elseif node.children then
      local c1, c2 = unpack(node.children)
      local l1, l2 = unlearn(c1), unlearn(c2)
      if l1 or l2 then
        local parms = l1 and c1.parms or c2.parms
        local dbs = dbset(node)
        local old_pR = core.classify(lim.msg, dbs, k.classify_flags)
        core.unlearn(lim.msg, dbs, parms.index(dbs), k.learn_flags+core.MISTAKE)
        local pR = core.classify(lim.msg, dbs, k.classify_flags)
        for i = 1, parms.reinforcement_limit do
          if parms.bigger(pR, threshold_offset) then
            core.unlearn(lim.header, dbs, parms.index(dbs), k.learn_flags)
            pR = core.classify(lim.msg, dbs, k.classify_flags)
          else
            break
          end
        end
        table.insert(trainings, { orig = old_pR, new = pR, class = node.classification})
        return true
      end
    end
  end
  unlearn(config.multitree)
  cache.change_file_status(sfid, classification, 'unlearned')

  return string.format('Message unlearned (was %s): %s', training_string(trainings)),
         trainings
end

