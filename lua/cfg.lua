local assert, ipairs, pairs, require, tostring, type
    = assert, ipairs, pairs, require, tostring, type

local package, string, os, math, table, io
    = package, string, os, math, table, io

local prog = _G.arg and _G.arg[0] or 'OSBF'

module (...)

version = '3.0rc1'

local d       = require (_PACKAGE .. 'default_cfg')
local util    = require (_PACKAGE .. 'util')
local options = require (_PACKAGE .. 'options')
local boot    = require (_PACKAGE .. 'boot')
local core    = require (_PACKAGE .. 'core')

default_threshold = 20

--- put default configuration in my configuration
for k, v in pairs(d) do
  _M[k] = v
end


----------------------------------------------------------------
-------- documentation for values set in default_cfg

__doc = {
  pwd = 'Password for subject-line commands',
  classes = [[Classes of email to be identified.

This value is a table with two parts: a list part and a keyword part.
The list part is a list of all the classes of interest.  A default list
might be
   'spam', 'ham'
a longer list might be
   'spam', 'work', 'ecommerce', 'entertainment', 'sports', 'personal'
and a list might be subdivided to group related messages:
   { 'spam', 'ecommerce' }, { 'entertainment', 'sports' }, 'work', 'personal'

The table part contains a table for each named class.  The only
required entry in this table is 'sfid', which must be a lowercase
letter that is unique to the class.  (This letter is used to tag the
class of learned messages.)  The list of all possible entries is:
  sfid      -- unique lowercase letter to identify class (required)
  sure      -- Subject: tag when mail definitely classified (defaults empty)
  unsure    -- Subject: tag when mail in reinforcement zone (defaults '?')
  threshold -- half width of reinforcement zone (defaults 20)
  dbnames   -- list of databases for this class (defaults { class .. '.cfc' })
  min_pR    -- minimum absolute ratio of probabilities to choose class (default 0)

Sfids 's' and 'h' must be for 'spam' and 'ham', and sfids 'w', 'b',
and 'e' are reserved for whitelisting, blacklisting, and errors.

Once the filter is well trained, thresholds should be reduced from the 
default value of 20 to something like 10, to reduce the burden of training.
(We'd love to have an automatic reduction, but we don't have an algorithm.)

If dbnames is given, each name should be relative to the user's database 
directory (normally the 'udir').  It is pointless to give dbnames unless
there is more than one name on the list.
]],

  tag_subject     = 'Flag to turn on of off subject tagging',

  trained_as_subject = [[
Table mapping class to format string for trained messages.
There can be an entry for each class name; the string is made by
calling string.format with the entry and the name of the class.
If there is no entry, OSBF-Lua uses the entry 'default'.]],

  training_not_necessary_single = [[
Result format string for messages which don't need training and 
which use a single classification (i.e., exactly two classes).
It expects two arguments: string representations of the score and
the reinforcement zone.
]],

  training_not_necessary_multi = [[
Result format string for messages which don't need training and 
which use a multiple classifications (more than two classes).
It expects two arguments: string representations of the scores and
the reinforcement zones.
]],

  header_prefix = [[Prefix of every header inserted by OSBF-Lua.]],
  header_suffixes = [[Table of suffixes used in different headers;
  Key      Suffix   Content
  score    Score    score(s) of the message
  class    Class    ultimate classification
  train    Train    'yes' if the message should be trained; 'no' otherwise
]],

  use_sfid     = 'Flag to turn on or off use of SFID',
  rightid      = [[
String with SFID's right id. Defaults to spamfilter.osbf.lua.]],

  insert_sfid_in  = [[Specifies where SFID must be inserted.
Valid values are:
 {"references"}, {"message-id"} or {"references", "message-id"}.
]],

  save_for_training = [[Save messages for later training,
if set to true. Defaults to true.]],
  log_incoming      = [[Log all incoming messages, if set to true.
Defauts to true.]],
  log_learned       = [[Log all learned messages, if set to true.
Defaults to true.]],
  log_dir           = [[Name of the log dir, relative to the user
osbf-lua dir. Defaults to "log".]],

  use_sfid_subdir = [[If use_sfid_subdir is true, messages cached
for later training are saved under a subdir under log_dir, formed by
the day of the month and the time the message arrived (DD/HH), to avoid
excessive files per dir. The subdirs must be created before you enable
this option.
]],


  count_classifications = [[Flag to turn on or off classification
counting.]],

  training_output  = [[If training_output is set to 'message', the original message
will be written to stdout after a training, with the correct tag.
To have the original behavior, that is, just a report message, comment
this option out or set it to false.
]],

  remove_body_threshold = [[Set remove_body_threshold to the score
value below which you want the message body to be removed. Use this
option after you have well trained databases. Defaults to false,
no body removal.
]],

  report_locale = [[Language to use in the cache-report training message.
  Default of true uses the user's locale; otherwise we understand
  'en_US' and 'pt_BR'.
]],

  mail_cmd = [[Command to send pre-formatted command messages.
Defaults to  "/usr/lib/sendmail -it < %s".  The %s in the command
will be replaced with the name of a file containing the pre-formatted
message to be sent.
]],

  cache_report_limit = [[Limit on the number of messages in a single
 cache report. Defaults to 50.
]],

  cache_report_order_by =[[Option to set what to order sfids by in cache
report. Valid values are 'date' and 'score' (absolute value). Defaults to
'score'.
]],

  cache_report_order = [[Sets the order of messages in cache report.
  '<' => older to newer; '>' => newer to older.
  Defauts to '<'.
]],

  command_address = [[Email address where command-messages should be
  sent to. Normally, this is set to user's email address.
]],

}

----------------------------------------------------------------




local default_pwd = assert(d.pwd)

__doc.version = "OSBF-Lua version."
__doc.slash = "Holds the detected OS slash char, '/' or '\\'."
 
slash = assert(string.match(package.path, [=[[\/]]=]))

__doc.homepage = 'Home page of the OSBF-Lua project.'
homepage = 'http://osbf-lua.luaforge.net'


--- XXX could we get rid of this and make all of config read-only
--- except changeable via 'load'?

__doc.constants = "Constants used by OSBF-Lua"

constants = 
  {
    classify_flags            = 0,
    learn_flags               = 0,
    default_db_megabytes      = 1.08332062 -- 94321 buckets by default
  }

__doc.text_limit = [[Initial length of a message to be used in
classifications and learnings.]]

text_limit = 100000

__doc.load = [[function(filename)
Loads a config file.
]]

function load(filename)
  local config, err = util.protected_dofile(filename)
  if not config or type(config) ~= 'table' then
    util.errorf('%s is not a valid config file.', filename)
  end
  for k, v in pairs(config) do
    if d[k] == nil then
      util.die(prog, ': fatal error - configuration "', tostring(k),
               '" cannot be set by a user')
    else
      _M[k] = v
    end
  end
end

__doc.load_if_readable = [[function(filename)
Loads a config file if readable.
Normally used to load user's config file.
]]

function load_if_readable(filename)
  if util.file_is_readable(filename) then
    return load(filename)
  else
    return true
  end
end

---------------- options

local val, bool, opt, dir =
  options.std.val, options.std.bool, options.std.opt, options.std.dir

local uhelp = [[
  --udir=<user_dir> 
        set  the  user  directory,  where  its  osbf-lua  configuration,
        databases,  lists and log files  are located.  The  location  of
        these files can also be set individually, see the options below.
]]
local dbhelp = [[
  --dbdir=<database_dir>
        specify a  location for the  database files different  than that
        specified with --udir.
]]
local cfhelp = [[
  --config=<config-file>
        specify a configuration file different from config.lua in the
        directory specified with --udir.
]]
local lhelp = [[
  --listdir=<list_dir>
        specify  a  location  for  the  list  files,  whitelist.lua  and
        blacklist.lua, different than that specified with --udir.
]]
local chelp = [[
  --cachedir=<cache-dir>
        specify a directory in which to cache messages for possible later training;
        defaults to the $udir/cache
]]


local opts = {
  { type = dir, long = 'udir', usage = "=<dir>      # User's OSBF-Lua directory", help = uhelp },
  { type = val, long = 'config', usage = "=<file>   # Configuration file", help = cfhelp },
  { type = dir, long = 'dbdir', usage = "=<dir>     # Database directory", help = dbhelp },
  { type = dir, long = 'listdir', usage = "=<dir>   # Directory for blacklist, whitelist",
    help = lhelp },
  { type = dir, long = 'cachedir', usage = "=<dir>  # Directory for message cache", help = chelp},
}

for _, o in ipairs(opts) do options.register(o) end

--------------------------------------------

--- directories

__doc.dirs = [[Table with system dirs:
dirs.udir     - User's OSBF-Lua directory. Defaults to $HOME/.osbf-lua.
dirs.dbdir    - Database directory. Defaults to dirs.udir.
dirs.listdir  - Directory for blacklist and whitelist. Defaults to dirs.udir.
dirs.cachedir - Directory for message cache. Defaults to dirs.udir/cache.
]]

dirs = { }

__doc.configfile = [[Configuration file; initialized by set_dirs.
Defaults to dirs.udir/config.lua.]]

configfile = nil -- initialized by set_dirs

__doc.set_dirs = [[function(options, no_dirs_ok)
Sets directories used by OSBF-Lua to command-line option values
or default values.
If no_dirs_ok is false, all dirs, given or default, are checked for
existance. In that case, the program exits with error if any doesn't exist.
]]

function set_dirs(options, no_dirs_ok)
  local HOME = os.getenv 'HOME'
  local default_dir = HOME and table.concat { HOME, slash, '.osbf-lua' }
  options = options or { }
  dirs.user = options.udir or (no_dirs_ok or core.isdir(default_dir)) and default_dir

  if not dirs.user then
    util.die('No --udir option given and ', default_dir, ' is not a directory.\n',
             'To create it, run\n  ', prog, ' init\n')
  end

  dirs.database = options.dbdir    or dirs.user
  dirs.lists    = options.listsdir or dirs.user

  for k in pairs(dirs) do dirs[k] = util.append_slash(dirs[k]) end

  configfile = options.config   or dirfilename('user', 'config.lua')
  dirs.cache = options.cachedir or util.append_slash(dirs.user .. "cache")
  dirs.log   = util.append_slash(dirs.user .. 'log')

  -- validate that everything is a directory

  if not no_dirs_ok then
    for name, dir in pairs(dirs) do
      if not core.isdir(dir) then
        util.die('The ', name, ' path ', dir, ' is not a directory')
      end
    end
  end
  util.set_log_file(dirs.log .. 'osbf_log')
end


__doc.dirfilename = [[function(dir, filename, suffix)
Returns a filename in particular directory of table dirs.
Suffix is used primarily to deal with sfid suffixes.
]]

function dirfilename(dir, basename, suffix)
  suffix = suffix or ''
  local d = assert(dirs[dir], dir .. ' is not a valid directory indicator')
  return d .. basename .. suffix
end

----------------------------------------------------------------
__doc.password_ok = [[function()
Returns true if password in user config file is OK or false, errmsg.
]]

function password_ok()
  if pwd == default_pwd then
    return false, 'Default password still used in ' .. configfile
  elseif string.find(pwd, '%s') then
    return false, 'password in ' .. configfile .. ' contains whitespace'
  else
    return true
  end
end

__doc.init = [[function(options, no_dirs_ok)
Sets OSBF-Lua directories, databases and loads user's config file.
]]

__doc.after_loading_do = [[function(f)
After the user's config file is loaded, call f passing the cfg table.
]]
local postloads = { }
function after_loading_do(f)
  table.insert(postloads, f)
end

__doc.dbnames = [[A mapping from classification to list of db names]]
dbnames = { }


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

__doc.classlist = [[function() returns sorted list of class names]]
do
  local the_classes
  function classlist()
    if not the_classes then
      the_classes = { }
      for c, v in pairs(classes) do
        if type(c) == 'string' and v.sfid then
          table.insert(the_classes, c)
        end
      end
      table.sort(the_classes)
    end
    return the_classes
  end
end

      
local function init(options, no_dirs_ok)
  set_dirs(options, no_dirs_ok)
  load_if_readable(configfile)
  mk_multitree()
  for _, f in ipairs(postloads) do
    f(_M)
  end
end

boot.initializer(init)
