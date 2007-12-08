local require, print, pairs, type, assert, loadfile, setmetatable =
      require, print, pairs, type, assert, loadfile, setmetatable

local io, string, table, math =
      io, string, table, math

local modname = ...
local modname = string.gsub(modname, '[^%.]+$', 'core')
module(modname)

__doc = __doc or { }

__doc.__order = {
  'create_db', 'header_size', 'bucket_size',
  'classify', 'learn', 'unlearn', 'train', 'pR', 'stats', 'config', 'dump',
  'restore', 'import', 'chdir', 'getdir', 'dir', 'isdir',
}


__doc.create_db = [[function(filename, num_buckets) returns nothing or calls lua_error
Creates an OSBF database with the given filename and
using the given number of buckets.  On success it returns nothing;
on failure it calls lua_error.
Example:
  core.create_db('spam.cfc', 94321)
]]

__doc.pR = [[function(p1, p2) returns log(p1/p2)
Compute the logarithm of the ratio of two probabilities, where the
base of the logarithm is chosen such that if p1 and p2 are (sums of)
probabilities returned by core.classify, then pR of less than 20
means that training is suggested (Train Near Error).
In the user documentation, the number returned by core.pR is
called 'confidence'.
]]

__doc.old_pR = [[old version of pR.  One or the other must go.]]

__doc.classify = [=[function(text, dblist, flags, min_p_ratio, delimiters) 
     returns sum, probs, trainings
  or calls lua_error

Classifies the string text using the databases in dblist

Arguments are as follows:

  text: String with the text to be classified

  dbset: list of pathnames, each of which is an on-disk database
         Example: {"ham.cfc", "spam.cfc"}

  flags: Number with the classification control flags. Each bit is a flag.
     The available flags are:
       * core.NO_EDDC                - disable EDDC;
       * core.COUNT_CLASSIFICATIONS  - turn on the classification counter;
     The NO_EDDC flag is intended for tests because disabling EDDC
     normally lowers accuracy.

  min_p_ratio: Optional number with the minimum feature probability ratio. 
     The probability ratio of a feature is the ratio between the
     maximum and the minimum probabilities it has over the
     classes. Features with less than min_p_ratio are not considered
     for classification. This parameter is optional. The default is 1,
     which means that all features are considered.

  delimiters: optional parameter containing additional token
    delimiters; defaults to the empty string.  The tokens are produced
    by the internal fixed pattern ([[:graph:]]+), or, in other words,
    by sequences of printable chars except tab, new line, vertical
    tab, form feed, carriage return, or space. If delimiters is not
    empty, its chars will be considered as extra token delimiters,
    like space, tab, new line, etc.

Results are as follows:
  returns probs, trainings, sum
    * probs:     a Lua array with the probability of each single class
    * trainings: a Lua array with the number of trainings for each
                 class
    * sum:       the sum of all probabilities in probs
In case of error, core.classify calls lua_error.
]=]

__doc.increment_false_positives = [=[
function(database, [delta]) 
  returns nothing or calls lua_error

Adds delta to false positive counter of database. delta is optional and
defaults to 1.

]=]

__doc.learn = [=[
function(text, dblist, class_index, [flags, [delimiters]]) 
  returns nothing or calls lua_error

Learns the string text as belonging to the single class database
indicated by the number class_index in dbset.classes.

Arguments are as follows:

  text: string with the text to be learned

  dblist: list of databases, as in core.classify

  class_index: index to the single database in dblist to be
      trained with text

  flags: Number with the flags to control the learning operation.
     Each bit is a flag. The available flags are:
       * core.NO_MICROGROOM  - disable microgrooming
       * core.FALSE_NEGATIVE - increment the false negative counter, 
                               in addition to the learning counter
       * core.EXTRA_LEARNING - increment the extra-learning, or
                               reinforcement, counter, in addition to
                               the learning counter
     The NO_MICROGROOM flag is more intended for tests because the
     databases have fixed size and the pruning mechanism is necessary
     to guarantee space for new learnings. The FALSE_NEGATIVE and the
     EXTRA_LEARNING flags shouldn't be used simultaneously.

  delimiters: optional extra delimiters as in core.classify
]=]

__doc.unlearn = [=[
function(text, dblist, class_index, [flags, [delimiters]]) 
  returns nothing or calls lua_error

Undoes the effect of core.learn.  Arguments are as for core.learn.
]=]

__doc.train = [=[
function(sense, text, list, index, [flags, [delimiters]])
  calls lua_error or returns nothing

If sense = 1 it's equivalent to core.learn, differing on how args
are passed.

  text, flags, and index are as for core.learn

  dbname: class to be trained with text

  delimiters: string with additional token delimiters. Each char
              in string is an additional delimiter

If sense = -1 it's equivalent to core.unlearn.
]=]

__doc.config = [[function(option_table)
Configures internal parameters. This function is intended for
testing.  option_table is a table whose keys are the options to be set
to their respective values.

The available options are:
   * max_chain: the max number of buckets allowed in a database
     chain. From that size on, the chain is pruned before
     inserting a new bucket.
   * stop_after: max number of buckets pruned in a chain
   * K1, K2, K3: Constants used in the EDDC formula
   * limit_token_size: limit token size to max_token_size, if not
     equal to 0. The default value is 0.
   * max_token_size: maximum number of chars in a token. The
     default is 60. This limit is observed if limit_token_size is
     different from 0.
   * max_long_tokens: sequences with more than max_long_tokens
     tokens where the tokens are greater than max_token_size are
     collapsed into a single hash, as if they were a single token.
     This is to reduce database pollution with the many "tokens"
     found in encoded attachments.
Return the number of options set.

   Ex: core.config {max_chain = 50, stop_after = 100}
]]


__doc.stats = [[function(dbfile [, full]) returns stats_table
Returns a table with information and statistics of the specified
database. The keys of the table are:
   * version - version of the module
   * buckets - total number of buckets in the database
   * bucket_size - size of the bucket, in bytes
   * header_size - size of the header, in buckets
   * learnings - number of learnings
   * extra_learnings - number of extra learnings done internally
     when a single learning is not enough
   * classifications - number of classifications
   * false_positives - number of learnings done to other classes because
     of misclassifications as this one
   * false_negatives - number of learnings done because
     of misclassifications
   * chains - number of bucket chains
   * max_chain - length of the longest chain
   * avg_chain - average length of a chain
   * max_displacement - max distance a bucket is from the "right"
     place
   * used_buckets - number of buckets used
   * use - percentage of buckets used

Arguments are as follows:

  dbfile: string with the database filename

  full: optional boolean argument. If present and equal to false, only
    the values already in the header of the database are returned,
    that is, the values for the keys version, buckets, bucket_size,
    header_size, learnings, extra_learnings, classifications and
    false negatives and false positives. If full is equal to true, or
    not given, the complete statistics are returned. For large databases,
    core.stats is much faster when full is equal to false.  

In case of error, core.stats calls lua_error.
]]


__doc.dump = [[function(dbfile, csvfile) returns nothing or calls lua_error
Creates csvfile, a dump of dbfile in CSV format. Its main use is
to transport dbfiles between different architectures (Intel to
Sparc for instance). A dbfile in CSV format can be restored in
another architecture using core.restore.

Arguments:
   dbfile: string with the database filename.
   csvfile: string with the csv filename.

In case of error, it calls lua_error.
]]

__doc.restore = [[function(dbfile, csvfile) returns nothing or calls lua_error
Restores dbfile from cvsfile. Be careful, if dbfile exists it'll
be rewritten. Its main use is to restore a dbfile in CVS format
dumped in a different architecture.

   dbfile: string with the database filename.
   csvfile: string with the csv filename

In case of error, it calls lua_error.]]

__doc.import = [[function(to_dbfile, from_dbfile) returns nothing or calls lua_error
Imports the buckets in from_dbfile into to_dbfile. from_dbfile
must exist. Buckets originally present in to_dbfile will be
preserved as long as the microgroomer doesn't delete them to make
room for the new ones. The counters (learnings, classifications,
false negatives, etc), in the destination database will be incremented
by the respective values in the origin database. The main purpose of
this function is to expand or shrink a database, importing into a
larger or smaller empty one.

   to_dbfile: string with the database filename.
   from_dbfile: string with the database filename

In case of error, it calls lua_error.]]

__doc.chdir = [[function(dir) returns returns nothing or calls lua_error
Change the current working dir to dir.

   dir: string with the database filename.

In case of error, it calls lua_error.]]

__doc.getdir = [[function() returns nothing or calls lua_error
Returns the current working dir. In case of error, it calls lua_error.]]

__doc.dir = [[function(dir) returns (iterator returns filename)
Returns a Lua iterator that returns a new entry, in the directory
passed as its argument, each time it is called. The example below
will print all entries in the current dir:

  for f in osbf.dir(".") do print(f) end

On error, calls lua_error (since it's of no use to return
nil, error in a 'for' loop).]]

__doc.isdir = [[function(pathname) returns boolean
Tells whether pathname is a directory.]]

__doc.header_size = [[Number of bytes in a database header.
The size of a database is header_size + bucket_size * num_buckets.]]

__doc.bucket_size = [[Number of bytes in a single bucket in a database.
The size of a database is header_size + bucket_size * num_buckets.]]

__doc.NO_EDDC = [[Flag for core.classify
Disables EDDC (normally for testing only ---usually lowers accuracy).]]
__doc.COUNT_CLASSIFICATIONS = [[Flag for core.classify
Turns on the classficiation counter.]]
__doc.NO_MICROGROOM = [[Flag for core.learn
Intended for tests only (explanation not understood).]]
__doc.FALSE_NEGATIVE = [[Flag for core.learn
Increments the false negative counter in addition to the learning counter.
Do not use in conjuction with EXTRA_LEARNING.]]
__doc.EXTRA_LEARNING = [[Flag for core.learn
Increment the extra-learning, or reinforcement, counter, 
in addition to the learning counter.  Do not use in conjunction
with FALSE_NEGATIVE.]]




__doc.__overview = [[
The core module provides access to the C code that does all the good
stuff.  Here are some example usages:

   --------------------------- To create databases
   local core = require "osbf.core"
   local dblist = { "ham.cfc", "spam.cfc" }
   local num_buckets = 94321
   -- remove previous databases with the same name
   for _, p in ipairs(dblist) do os.remove(p) end
   core.create_db(dblist, num_buckets) -- create new, empty databases

   --------------------- To classify a message read from stdin
   local core = require "osbf.core"
   local dblist = { "ham.cfc", "spam.cfc" }
   -- read entire message into var "text"
   local text = io.read("*all")
   local probs, trainings, sum = osbf.classify(text, dblist)
   if probs[1] > probs[2] then
     io.write('ham with confidence ', core.pR(probs[1], probs[2]), '\n')
   else
     io.write('spam with confidence ', core.pR(probs[2], probs[1]), '\n')
   end
]]
