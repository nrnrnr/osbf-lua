/*
 * OSBF-Lua - library for text classification
 *
 * See Copyright Notice in osbflua.h
 *
 */

#include <ctype.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include <unistd.h>
#include <errno.h>
#include <dirent.h>
#include <inttypes.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "lua.h"

#include "lauxlib.h"
#include "lualib.h"

#define osbf_error_handler lua_State

#define DEBUG 0

#include "osbflib.h"

extern int OPENFUN (lua_State * L);  /* exported to the outside world */

/****************************************************************/

/* support for OSBF class as userdata */

#define CLASS_METANAME "osbf3.class"
#define DIR_METANAME   "osbf3.dir"

#define check_class(L, i) (CLASS_STRUCT *) luaL_checkudata(L, i, CLASS_METANAME)


/* configurable constants */
extern uint32_t microgroom_displacement_trigger;
extern uint32_t microgroom_stop_after;
extern double K1, K2, K3;
extern uint32_t max_token_size, max_long_tokens;
extern uint32_t limit_token_size;

/* macro to `unsign' a character */
#ifndef uchar
#define uchar(c)        ((unsigned char)(c))
#endif

/* pR scale calibration factor - pR_SCF
   This value is used to calibrate the pR scale so that
   values in the interval [-20, 20] indicate the need
   of reinforcement training, even if the classification 
   is correct.
   The default pR_SCF was determined experimentally,
   but can be changed using the osbf.config call.
   
*/
static double pR_SCF = 0.59;

/**********************************************************/

static int
lua_osbf_config (lua_State * L)
{
  int options_set = 0;

  luaL_checktype (L, 1, LUA_TTABLE);

  lua_getfield (L, 1, "max_chain");
  if (lua_isnumber (L, -1))
    {
      microgroom_displacement_trigger = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_getfield (L, 1, "stop_after");
  if (lua_isnumber (L, -1))
    {
      microgroom_stop_after = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_getfield (L, 1, "K1");
  if (lua_isnumber (L, -1))
    {
      K1 = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_getfield (L, 1, "K2");
  if (lua_isnumber (L, -1))
    {
      K2 = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_getfield (L, 1, "K3");
  if (lua_isnumber (L, -1))
    {
      K3 = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_getfield (L, 1, "limit_token_size");
  if (lua_isnumber (L, -1))
    {
      limit_token_size = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_getfield(L, 1, "max_token_size");
  if (lua_isnumber (L, -1))
    {
      max_token_size = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_getfield(L, 1, "max_long_tokens");
  if (lua_isnumber (L, -1))
    {
      max_long_tokens = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_getfield(L, 1, "pR_SCF");
  if (lua_isnumber (L, -1))
    {
      pR_SCF = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_pushnumber (L, (lua_Number) options_set);
  return 1;
}

/**********************************************************/

static int
lua_osbf_createdb (lua_State * L)
{
  osbf_create_cfcfile (luaL_checkstring(L, 1), (uint32_t) luaL_checkint(L, 2), L);
  return 0;
}

/* takes a Lua state and the index of the list of classes.
   Writes the names of the database files into the array, which
   has size elements, then writes NULL as the last element 
   and returns the number of nonnull elements */

static unsigned class_list_to_array(lua_State *L,
                                    int idx,
                                    const char *classes[],
                                    unsigned size)
{
  unsigned n;

  for (n = 0; ; n++) {
    lua_rawgeti(L, idx, n+1); /* Lua is 1-indexed; C is 0-indexed */
    if (lua_isnil(L, -1)) break;
    else if (!lua_isstring(L, -1))
      return luaL_error(L, "Element %d of the list of databases is not a string",
                        n + 1);
    else if (n == size - 1)
      return luaL_error(L, "Can't handle more than %d classes", size);
    else {
      classes[n] = lua_tostring(L, -1);
      lua_pop(L, 1);
      if (classes[n] == NULL)
        luaL_error(L, "This can't happen: Lua said something was a string and then"
                   "changed its mind");
    }
  }
  classes[n] = NULL;
  if (n < 1)
    return luaL_error (L, "List of OSBF-Lua databases is empty");
  else
    return n;
}
  

/* this function asserts that probabilities add up to 1.0, within rounding error */
static void check_sum_is_one(double *p_classes, unsigned num_classes);

#define ULP 2.23e-16 /* http://docs.sun.com/source/806-3568/ncg_math.html */
  /* one unit in the last place */



#ifdef NDEBUG
static void check_sum_is_one(double *p_classes, unsigned num_classes) { exit(99); }
#else
static int compare_doubles(const void *p1, const void *p2) {
  double x1 = *(const double *)p1;
  double x2 = *(const double *)p2;
  return x1 < x2 ? -1 : x1 > x2 ? 1 : 0;
}

static void check_sum_is_one(double *p_classes, unsigned num_classes) { 
  /* sort before adding to avoid rounding error */
  double sorted[OSBF_MAX_CLASSES], sum, badsum;
  unsigned i;
  for (i = 0; i < num_classes; i++) {
    sorted[i] = p_classes[i];
  }
  qsort(sorted, num_classes, sizeof(sorted[0]), compare_doubles);
  badsum = sum = 0.0;
  /* add small numbers first to avoid rounding error */
  for (i = 0; i < num_classes; i++) {
    sum += sorted[i];
    badsum += p_classes[i];
  }
  if (fabs(sum - 1.0) >= 10 * ULP) {
    fprintf(stderr, "osbf3: sum of probabilities differs from unity "
            "by more then 10 ulps\n");
    fprintf(stderr, "Sum - 1.0 = %9g; ", sum - 1.0);
    fprintf(stderr, "smallest probability = %9g\n", sorted[0]);
    fprintf(stderr, "badsum - sum = %9g\n", badsum - sum);
    for (i = 0; i < num_classes; i++)
      fprintf(stderr, "  probability[%d] = %9g\n", i, p_classes[i]);
  }
}
#endif

/**********************************************************/

/* debugging */


static struct {
  const char *mode;
  osbf_class_usage usage;
  const char *longname;
} usage_array[] = {
  { "r",   OSBF_READ_ONLY, "read only" },
  { "rw",  OSBF_WRITE_ALL, "read/write" },
  { "rwh", OSBF_WRITE_HEADER, "read-all/write-header" },
  { NULL, 0, NULL },
};

static osbf_class_usage usage_from_mode(const char *mode);
static osbf_class_usage usage_from_mode(const char *mode) {
  unsigned i;
  for (i = 0; usage_array[i].mode != NULL; i++) 
    if (!strcmp(usage_array[i].mode, mode)) {
      return usage_array[i].usage;
      break;
    }
  return (osbf_class_usage) -1;
}


static int lua_osbf_class_tostring(lua_State *L) {
  CLASS_STRUCT *c = check_class(L, 1);

  if (c->state == OSBF_CLOSED) {
    lua_pushliteral(L, "closed OSBF class");
    return 1;
  } else {
    unsigned i;
    for (i = 0; usage_array[i].mode != NULL; i++)
      if (usage_array[i].usage == c->usage) {
        lua_pushfstring(L, "OSBF class version %d (%s) open on file %s for %s",
                        c->header->db_version, c->fmt_name,
                        c->classname, usage_array[i].longname);
        return 1;
      }
    return luaL_error(L, "Tried to print OSBF class with unknown usage %d", c->usage);
  }
}

static int lua_osbf_class_mode(lua_State *L) {
  unsigned i;
  CLASS_STRUCT *c = check_class(L, 1);

  if (c->state == OSBF_CLOSED) {
    return 0;
  } else {
    for (i = 0; usage_array[i].mode != NULL; i++)
      if (usage_array[i].usage == c->usage) {
        lua_pushstring(L, usage_array[i].mode);
        return 1;
      }
    return luaL_error(L, "Mode %d of OSBF class not recognized", c->usage);
  }
}

#define DEFINE_FIELD_FUN(fname, push)                                \
  static int lua_osbf_class_ ## fname(lua_State *L) {                \
    CLASS_STRUCT *c = check_class(L, 1);                             \
                                                                     \
    if (c->state == OSBF_CLOSED) {                                   \
      return luaL_error(L, "Asked for " #fname " of closed class");  \
    } else {                                                         \
      push;                                                          \
      return 1;                                                      \
    }                                                                \
  }

#define FFSTRUCT(fname) { #fname, lua_osbf_class_ ## fname }

DEFINE_FIELD_FUN(filename,        lua_pushstring(L, c->classname))
DEFINE_FIELD_FUN(version,         lua_pushnumber(L, c->header->db_version))
DEFINE_FIELD_FUN(version_name,    lua_pushstring(L, c->fmt_name))
DEFINE_FIELD_FUN(num_buckets,     lua_pushnumber(L, c->header->num_buckets))
DEFINE_FIELD_FUN(id,              lua_pushnumber(L, c->header->db_version))
DEFINE_FIELD_FUN(bucket_size,     lua_pushnumber(L, sizeof(*c->buckets)))
DEFINE_FIELD_FUN(header_size,     lua_pushnumber(L, sizeof(*c->header)))
DEFINE_FIELD_FUN(learnings,       lua_pushnumber(L, c->header->learnings))
DEFINE_FIELD_FUN(classifications, lua_pushnumber(L, c->header->classifications))
DEFINE_FIELD_FUN(extra_learnings, lua_pushnumber(L, c->header->extra_learnings))
DEFINE_FIELD_FUN(fn,              lua_pushnumber(L, c->header->false_negatives))
DEFINE_FIELD_FUN(fp,              lua_pushnumber(L, c->header->false_positives))
DEFINE_FIELD_FUN(false_negatives, lua_pushnumber(L, c->header->false_negatives))
DEFINE_FIELD_FUN(false_positives, lua_pushnumber(L, c->header->false_positives))
DEFINE_FIELD_FUN(, lua_pushnil(L))

#define DEFINE_MUTATE_FUN(fname, lvalue)                             \
  static int lua_osbf_class_set_ ## fname(lua_State *L) {            \
    CLASS_STRUCT *c = check_class(L, 1);                             \
    int value = luaL_checkint(L, 2);                                 \
                                                                     \
    if (c->state == OSBF_CLOSED) {                                   \
      return luaL_error(L, "Asked for " #fname " of closed class");  \
    } else if (c->usage == OSBF_READ_ONLY) {                         \
      return luaL_error(L, "Cannot mutate a read-only class");       \
    } else {                                                         \
      lvalue = (value);                                              \
      return 0;                                                      \
    }                                                                \
  }

#define MFSTRUCT(fname) { #fname, lua_osbf_class_set_ ## fname }

DEFINE_MUTATE_FUN(classifications, c->header->classifications)
DEFINE_MUTATE_FUN(learnings,       c->header->learnings)
DEFINE_MUTATE_FUN(extra_learnings, c->header->extra_learnings)
DEFINE_MUTATE_FUN(fn,              c->header->false_negatives)
DEFINE_MUTATE_FUN(fp,              c->header->false_positives)


/* to provide a buckets array, we have to use a table, not userdata, because the 
   buckets array must keep the class live, and only a table can keep another
   value alive.  Therefore we need horrible
*/

/****************************************************************/

/* Once we open a class, we don't close it until it gets garbage collected
   or until we explicitly close the core.  Lua code can open class files by
   name as much as it likes, and we keep the open files in the cache.
   Open files are closed by the garbage collector on normal exit and
   os.exit is rewritten to close them also.  */


static void
push_open_class_using_cache(lua_State *L, const char *filename, osbf_class_usage usage);

static void
push_open_class_using_cache(lua_State *L, const char *filename, osbf_class_usage usage)
{
  if (usage == (osbf_class_usage) -1) 
    luaL_error(L, "Unknown mode for open_class; try 'r' or 'rw' or 'rwh'");

  lua_getfield(L, LUA_ENVIRONINDEX, "cache");  /* s: cache */
  lua_getfield(L, -1, filename);               /* s: cache class */
 cached_on_top:
  if (lua_isnil(L, -1)) {
    CLASS_STRUCT *c = lua_newuserdata(L, sizeof(*c));  /* s: cache nil class */
    luaL_getmetatable(L, CLASS_METANAME);
    lua_setmetatable(L, -2);
    osbf_open_class(filename, usage, c, L);
    lua_remove(L, -2); /* remove loathesome nil */
    lua_pushvalue(L, -1);
    lua_setfield(L, -3, filename);             /* s: cache class */
    if (strcmp(filename, c->classname))
      luaL_error(L, "Tried to load %s from the cache but found %s instead",
                 filename, c->classname);
  } else {
    CLASS_STRUCT *c = check_class(L, -1); /* should always succeed */
    if (c->state == OSBF_CLOSED || c->usage < usage) {
      if (DEBUG)
        fprintf(stderr, "%s in cache, but it must be re-opened for usage %d (%s)\n",
                filename,
                usage,
                c->state == OSBF_CLOSED ? "closed" : "usage too low");
      if (c->state != OSBF_CLOSED)
        osbf_close_class(c, L);
      lua_pop(L, 1); /* goodbye class */
      lua_pushnil(L); /* pretend nothing was in the cache */
      goto cached_on_top;
    } else {
      /* 'opening' a cached file clears its bflags */
      memset(c->bflags, 0, c->header->num_buckets * sizeof(unsigned char));
    }
    if (strcmp(filename, c->classname))
      luaL_error(L, "Tried to load %s from the cache but found %s instead",
                 filename, c->classname);
  }
  lua_remove(L, -2); /* remove the cache from the stack, leaving only the class */
}

static int lua_osbf_close_cached_classes(lua_State *L);
static int lua_osbf_close_cached_classes(lua_State *L) {
  lua_getfield(L, LUA_ENVIRONINDEX, "cache");  /* s: cache */
  lua_pushnil(L);
  while (lua_next(L, -2) != 0) {
    CLASS_STRUCT *c = check_class(L, -1); /* should always succeed */
    if (c->state != OSBF_CLOSED) {
      if (DEBUG)
        fprintf(stderr, "Closing class %s\n", c->classname);
      osbf_close_class(c, L);
    }
    lua_pop(L, 1); /* keep key for next iteration */
  }
  lua_pop(L, 1); /* pop cache off the stack */
  return 0;
}

static int lua_osbf_close_cache_and_exit(lua_State *L);
static int lua_osbf_close_cache_and_exit(lua_State *L) {
  lua_osbf_close_cached_classes(L);
  lua_getfield(L, LUA_ENVIRONINDEX, "exit");  /* s: args exit */
  lua_insert(L, 1);             /* s: exit args */
  lua_call(L, lua_gettop(L)-1, LUA_MULTRET);
  return lua_gettop(L);
}


static int
lua_osbf_open_class(lua_State *L) {
  const char *filename = luaL_checkstring(L, 1);
  const char *mode     = luaL_optstring(L, 2, "r");

  push_open_class_using_cache(L, filename, usage_from_mode(mode));
  return 1;
}

static int
lua_osbf_class_gc(lua_State *L) {
  CLASS_STRUCT *c = check_class(L, 1);
  if (c->state != OSBF_CLOSED) {
    if (DEBUG)
      fprintf(stderr, "Closing class %s, possibly because of GC\n", c->classname);
    osbf_close_class(c, L);
  }
  return 0;
}

/**********************************************************/

static int
lua_osbf_classify (lua_State * L)
     /* classify(text, dbnames, flags, min_p_ratio, delimiters)
        returns sum, probs, trainings */
{
  const unsigned char *text;
  size_t text_len;
  const char *delimiters;	/* extra token delimiters */
  size_t delimiters_len;
  const char *classnames[OSBF_MAX_CLASSES + 1];	/* set of classes */
  uint32_t flags = 0;		/* default value */
  double min_p_ratio;		/* min pmax/p,in ratio */
  /* class probabilities are returned in p_classes */
  CLASS_STRUCT *classes[OSBF_MAX_CLASSES];
  double p_classes[OSBF_MAX_CLASSES];
  uint32_t p_trainings[OSBF_MAX_CLASSES];
  unsigned i, num_classes;
  double sum = 0.0;

  /* get the arguments */
  text        = (const unsigned char *) luaL_checklstring (L, 1, &text_len);
  luaL_checktype (L, 2, LUA_TTABLE);
  num_classes = class_list_to_array(L, 2, classnames, NELEMS(classnames));
  flags       = (uint32_t) luaL_optnumber (L, 3, 0);
  min_p_ratio = (double) luaL_optnumber (L, 4, OSBF_MIN_PMAX_PMIN_RATIO);
  delimiters  = luaL_optlstring (L, 5, "", &delimiters_len);

  if (!lua_checkstack(L, num_classes + 10))
    luaL_error(L, "Could not allocate enough stack space for %d classes",
               num_classes);

  for (i = 0; i < num_classes; i++) {
    push_open_class_using_cache(L, classnames[i], OSBF_READ_ONLY);
    classes[i] = lua_touserdata(L, -1);
  }

  /* call osbf_classify */
  osbf_bayes_classify (text, text_len, delimiters, classes, num_classes,
                       flags, min_p_ratio,
                       p_classes, p_trainings, L);

  lua_pop(L, num_classes); /* no longer need pinning */

  /* push list of probabilities onto the stack */
  lua_newtable (L);
  /* push table with number of trainings per class */
  lua_newtable (L);
  for (i = 0; i < num_classes; i++)
    {
      sum += p_classes[i];
      lua_pushnumber (L, (lua_Number) p_classes[i]);
      lua_rawseti (L, -3, i + 1);
      lua_pushnumber (L, (lua_Number) p_trainings[i]);
      lua_rawseti (L, -2, i + 1);
    }
  check_sum_is_one(p_classes, num_classes);
  lua_pushnumber(L, sum);
  lua_insert(L, -3);
  return 3;
}

static int
lua_osbf_pR (lua_State * L)
     /* core.pR(p1, p2) returns log(p1/p2) */
{
  double p1 = luaL_checknumber(L, 1);
  double p2 = luaL_checknumber(L, 2);
  double ratio;
  if (lua_type(L, 3) != LUA_TNONE)
    return luaL_error(L, "Too many arguments to core.pR");
  else {
    if (p2 <= 0.0)
      p2 = OSBF_SMALLP;
    ratio = p1 / p2;
    if (ratio <= 0.0)
      ratio = OSBF_SMALLP;
    lua_pushnumber (L, (lua_Number) pR_SCF * log10 (ratio));
    return 1;
  }
}


static int
lua_osbf_old_pR (lua_State * L)
     /* core.pR(p1, p2) returns log(p1/p2) */
{
  double p1 = luaL_checknumber(L, 1);
  double p2 = luaL_checknumber(L, 2);
  p1 += OSBF_SMALLP;
  p2 += OSBF_SMALLP;
  if (lua_type(L, 3) != LUA_TNONE)
    return luaL_error(L, "Too many arguments to core.pR");
  else if (p2 <= 0.0 || p1 <= 0.0)
    return luaL_error(L, "in core.pR, a probability is not positive");
  else {
    lua_pushnumber (L, (lua_Number) pR_SCF * log10 (p1 / p2));
    return 1;
  }
}

/**********************************************************/

static int
lua_osbf_train (lua_State * L)
     /* train(sense, text, dbname, [flags, [delimiters]]) returns true or nil, error */
{
  int sense;
  const unsigned char *text;
  size_t text_len;
  const char *dbname;
  uint32_t flags = 0;		/* default value */
  const char *delimiters = "";	/* extra token delimiters */
  size_t delimiters_len = 0;

  /* get args */
  sense  = luaL_checkint(L, 1);
  text   = (unsigned char *) luaL_checklstring (L, 2, &text_len);
  dbname = luaL_checkstring(L, 3);
  flags  = (uint32_t) luaL_optint(L, 4, 0);
  delimiters = luaL_optlstring(L, 5, "", &delimiters_len);
  luaL_checktype (L, 6, LUA_TNONE);

  push_open_class_using_cache(L, dbname, OSBF_WRITE_ALL);
  osbf_bayes_train(text, text_len, delimiters, lua_touserdata(L, -1), sense, flags, L);
  return 0;
}

/**********************************************************/

static int
lua_osbf_learn (lua_State * L)
{
  lua_pushnumber(L, 1);
  lua_insert(L, 1);
  return lua_osbf_train (L);
}

/**********************************************************/

static int
lua_osbf_unlearn (lua_State * L)
{
  lua_pushnumber(L, -1);
  lua_insert(L, 1);
  return lua_osbf_train (L);
}

/**********************************************************/

static int
lua_osbf_dump (lua_State * L)
{
  push_open_class_using_cache(L, luaL_checkstring (L, 1), OSBF_READ_ONLY);
  osbf_dump (check_class(L, -1), luaL_checkstring (L, 2), L);
  return 0;
}

/**********************************************************/

static int
lua_osbf_restore (lua_State * L)
{
  osbf_restore (luaL_checkstring (L, 1), luaL_checkstring (L, 2), L);
  return 0;
}

/**********************************************************/

static int
lua_osbf_import (lua_State * L)
{
  push_open_class_using_cache(L, luaL_checkstring(L, 1), OSBF_WRITE_ALL);
  push_open_class_using_cache(L, luaL_checkstring(L, 2), OSBF_READ_ONLY);

  osbf_import (check_class(L, -2), check_class(L, -1), L);
  return 0;
}

/**********************************************************/

static int
lua_osbf_stats (lua_State * L)
{

  const char *cfcfile;
  STATS_STRUCT stats;
  int full = 1;

  cfcfile = luaL_checkstring (L, 1);
  if (lua_isboolean (L, 2))
    {
      full = lua_toboolean (L, 2);
    }

  push_open_class_using_cache(L, cfcfile, OSBF_READ_ONLY);
  osbf_stats (check_class(L, -1), &stats, L, full);
  lua_newtable (L);

  lua_pushnumber (L, (lua_Number) stats.db_version);
  lua_setfield(L, -2, "db_version");

  lua_pushnumber (L, (lua_Number) stats.total_buckets);
  lua_setfield(L, -2, "buckets");

  lua_pushnumber (L, (lua_Number) stats.bucket_size);
  lua_setfield(L, -2, "bucket_size");

  lua_pushnumber (L, (lua_Number) stats.header_size);
  lua_setfield(L, -2, "header_size");

  lua_pushnumber (L, stats.header_size + stats.total_buckets * stats.bucket_size);
  lua_setfield(L, -2, "bytes");

  lua_pushnumber (L, (lua_Number) stats.learnings);
  lua_setfield(L, -2, "learnings");

  lua_pushnumber (L, (lua_Number) stats.extra_learnings);
  lua_setfield(L, -2, "extra_learnings");

  lua_pushnumber (L, (lua_Number) stats.false_positives);
  lua_setfield(L, -2, "false_positives");

  lua_pushnumber (L, (lua_Number) stats.false_negatives);
  lua_setfield(L, -2, "false_negatives");

  lua_pushnumber (L, (lua_Number) stats.classifications);
  lua_setfield(L, -2, "classifications");

  if (full == 1)
    {
      lua_pushnumber (L, (lua_Number) stats.num_chains);
      lua_setfield(L, -2, "chains");

      lua_pushnumber (L, (lua_Number) stats.max_chain);
      lua_setfield(L, -2, "max_chain");

      lua_pushnumber (L, (lua_Number) stats.avg_chain);
      lua_setfield(L, -2, "avg_chain");

      lua_pushnumber (L, (lua_Number) stats.max_displacement);
      lua_setfield(L, -2, "max_displacement");

      lua_pushnumber (L, (lua_Number) stats.unreachable);
      lua_setfield(L, -2, "unreachable");

      lua_pushnumber (L, (lua_Number) stats.used_buckets);
      lua_setfield(L, -2, "used_buckets");

      if (stats.total_buckets > 0)
        lua_pushnumber (L, (lua_Number) ((double) stats.used_buckets /
                                     stats.total_buckets));
      else
        lua_pushnumber (L, (lua_Number) 100);
      lua_setfield (L, -2, "use");
    }
   return 1;
}

/**********************************************************/

/*
** Assumes the table is on top of the stack, left by luaL_register call
*/
static void
set_info (lua_State * L, int idx)
{
  lua_pushliteral (L, "Copyright (C) 2005-2007 Fidelis Assis and Norman Ramsey");
  lua_setfield (L, idx, "_COPYRIGHT");
  lua_pushliteral (L, "OSBF-Lua is a Lua library for text classification.");
  lua_setfield (L, idx, "_DESCRIPTION");
  lua_pushliteral (L, "OSBF-Lua");
  lua_setfield (L, idx, "_NAME");
  lua_pushliteral (L, LIB_VERSION);
  lua_setfield (L, idx, "_VERSION");
  lua_pushnumber (L, (lua_Number) sizeof(OSBF_HEADER_STRUCT));
  lua_setfield (L, idx, "header_size");
  lua_pushnumber (L, (lua_Number) sizeof(OSBF_BUCKET_STRUCT));
  lua_setfield (L, idx, "bucket_size");

#define add_const(C) lua_pushnumber(L, (lua_Number) C); lua_setfield(L, idx, #C)

  add_const(NO_EDDC);
  add_const(COUNT_CLASSIFICATIONS);
  add_const(NO_MICROGROOM);
  add_const(FALSE_NEGATIVE);
  add_const(EXTRA_LEARNING);

#undef add_const

}

/**********************************************************/

/* auxiliary functions */

#define MAX_DIR_SIZE 256

static int
lua_osbf_changedir (lua_State * L)
{
  const char *newdir = luaL_checkstring (L, 1);

  if (chdir (newdir) != 0)
    {
      return 0;
    }
  else
    {
      return luaL_error (L, "can't change dir to '%s'\n", newdir);
    }
}

/**********************************************************/
/* Test to see if path is a directory */
static int
l_is_dir(lua_State *L)
{
	struct stat s;
	const char *path=luaL_checkstring(L, 1);
	if (stat(path,&s)==-1)
          lua_pushboolean(L, 0);
        else
          lua_pushboolean(L, S_ISDIR(s.st_mode));
        return 1;
}


/**********************************************************/

static int
lua_osbf_getdir (lua_State * L)
{
  char cur_dir[MAX_DIR_SIZE + 1];

  if (getcwd (cur_dir, MAX_DIR_SIZE) != NULL)
    {
      lua_pushstring (L, cur_dir);
      return 1;
    }
  else
    {
      return luaL_error(L, "%s","can't get current dir");
    }
}

/**********************************************************/
/* Directory Iterator - from the PIL book */

/* forward declaration for the iterator function */
static int dir_iter (lua_State * L);

static int
l_dir (lua_State * L)
{
  const char *path = luaL_checkstring (L, 1);

  /* create a userdatum to store a DIR address */
  DIR **d = (DIR **) lua_newuserdata (L, sizeof (DIR *));

  /* set its metatable */
  luaL_getmetatable (L, DIR_METANAME);
  lua_setmetatable (L, -2);

  /* try to open the given directory */
  *d = opendir (path);
  if (*d == NULL)		/* error opening the directory? */
    luaL_error (L, "cannot open %s: %s", path, strerror (errno));

  /* creates and returns the iterator function
     (its sole upvalue, the directory userdatum,
     is already on the stack top */
  lua_pushcclosure (L, dir_iter, 1);
  return 1;
}

static int
dir_iter (lua_State * L)
{
  DIR *d = *(DIR **) lua_touserdata (L, lua_upvalueindex (1));
  struct dirent *entry;
  if ((entry = readdir (d)) != NULL)
    {
      lua_pushstring (L, entry->d_name);
      return 1;
    }
  else
    return 0;			/* no more values to return */
}

static int
dir_gc (lua_State * L)
{
  DIR *d = *(DIR **) lua_touserdata (L, 1);
  if (d)
    closedir (d);
  return 0;
}
/**********************************************************/

/* 32-bit Cyclic Redundancy Code  implemented by A. Appel 1986  
 
   this works only if POLY is a prime polynomial in the field
   of integers modulo 2, of order 32.  Since the representation of this
   won't fit in a 32-bit word, the high-order bit is implicit.
   IT MUST ALSO BE THE CASE that the coefficients of orders 31 down to 25
   are zero.  Fortunately, we have a candidate, from
	E. J. Watson, "Primitive Polynomials (Mod 2)", Math. Comp 16 (1962).
   It is:  x^32 + x^7 + x^5 + x^3 + x^2 + x^1 + x^0

   Now we reverse the bits to get:
	111101010000000000000000000000001  in binary  (but drop the last 1)
           f   5   0   0   0   0   0   0  in hex
*/

#define POLY 0xf5000000

static uint32_t crc_table[256];

static void init_crc(void) {
  int i, j, sum;
  for (i=0; i<256; i++) {
    sum=0;
    for(j = 8-1; j>=0; j=j-1)
      if (i&(1<<j)) sum ^= ((uint32_t)POLY)>>j;
    crc_table[i]=sum;
  }
}

static int lua_crc32(lua_State *L) {
  size_t n;
  const unsigned char *s = (const unsigned char *)luaL_checklstring(L, 1, &n);
  uint32_t sum = 0;
  do sum = (sum>>8) ^ crc_table[(sum^(*s++))&0xff]; while (--n > 0);
  lua_pushnumber(L, (lua_Number) sum);
  return 1;
}

/**********************************************************/

static const struct luaL_reg classmeta[] = {
  {"__tostring", lua_osbf_class_tostring},
  {"__gc", lua_osbf_class_gc},
  {NULL, NULL}
};

  
static int lua_class_pairs(lua_State *L);

#define DEFINE_CONST(name, f) \
  static int name ##_push(lua_State *L) { lua_pushcfunction(L, f); return 1; }
#define USE_CONST(name) { #name, name ##_push }

DEFINE_CONST(close, lua_osbf_class_gc)
DEFINE_CONST(pairs, lua_class_pairs)


static const struct luaL_reg classops[] = {
  USE_CONST(close),
  USE_CONST(pairs),
  {"", lua_osbf_class_},  /* marks start of 'fields' */
  FFSTRUCT(filename),
  FFSTRUCT(classifications),
  FFSTRUCT(learnings),
  FFSTRUCT(extra_learnings),
  FFSTRUCT(fn),
  FFSTRUCT(fp),
  FFSTRUCT(false_negatives),
  FFSTRUCT(false_positives),
  FFSTRUCT(mode),
  FFSTRUCT(version),
  FFSTRUCT(version_name),
  FFSTRUCT(bucket_size),
  FFSTRUCT(header_size),
  FFSTRUCT(num_buckets),
  /*  { "buckets", lua_osbf_class_buckets }, */
  FFSTRUCT(id),
  {NULL, NULL}
};

static const struct luaL_reg mutable_fields[] = {
  MFSTRUCT(classifications),
  MFSTRUCT(learnings),
  MFSTRUCT(extra_learnings),
  MFSTRUCT(fn),
  MFSTRUCT(fp),
  {NULL, NULL}
};

static int lua_class_next(lua_State *L) {
  /* first upvalue is index */
  int i = luaL_checkint(L, lua_upvalueindex(1));
  (void)check_class(L, 1);
  if (classops[i].name == NULL) {
    return 0;
  } else {
    lua_pushnumber(L, i+1);
    lua_replace(L, lua_upvalueindex(1));
    lua_pushstring(L, classops[i].name);
    lua_pushcfunction(L, classops[i].func);
    lua_pushvalue(L, 1);
    lua_call(L, 1, 1);
    return 2;
  }
}

static int lua_class_pairs(lua_State *L) {
  int i;
  (void)check_class(L, 1);
  for (i = 0; classops[i].name && *classops[i].name; i++);
  if (classops[i].name) i++;  /* skip past the "" field */
  lua_pushnumber(L, i);
  lua_pushcclosure(L, lua_class_next, 1);
  lua_pushvalue(L, 1);
  return 2;
}

static int lua_classfields(lua_State *L) {
  const char *key = luaL_checkstring(L,  2);
  lua_getfield(L, lua_upvalueindex(1), key);
  if (lua_isfunction(L, -1)) {
    lua_insert(L, 1);
    lua_call(L, 2, 1);
    return 1;
  } else {
    return luaL_error(L, "OSBF class has no field named %s", key);
  }
}

static int lua_set_classfields(lua_State *L) {
  const char *key = luaL_checkstring(L,  2);
  (void)check_class(L, 1);
  lua_getfield(L, lua_upvalueindex(2), key);
  if (lua_isfunction(L, -1)) {
    lua_pushvalue(L, 1);
    lua_pushvalue(L, 3);
    lua_call(L, 2, 0);
    return 0;
  } else {
    lua_getfield(L, lua_upvalueindex(1), key);
    if (lua_isfunction(L, -1))
      return luaL_error(L, "field %s of the OSBF class is not mutable", key);
    else
      return luaL_error(L, "OSBF class has no field named %s", key);
  }
}

/* XXX todo 'forget' function to drop a cfc file from the cache */

static const struct luaL_reg osbf[] = {
  {"close", lua_osbf_close_cached_classes},
  {"create_db", lua_osbf_createdb},
  {"config", lua_osbf_config},
  {"classify", lua_osbf_classify},
  {"learn", lua_osbf_learn},
  {"unlearn", lua_osbf_unlearn},
  {"train", lua_osbf_train},
  {"open_class", lua_osbf_open_class},
  {"close_class", lua_osbf_class_gc},
  {"pR", lua_osbf_pR},
  {"old_pR", lua_osbf_old_pR},
  {"dump", lua_osbf_dump},
  {"restore", lua_osbf_restore},
  {"import", lua_osbf_import},
  {"stats", lua_osbf_stats},
  {"getdir", lua_osbf_getdir},
  {"chdir", lua_osbf_changedir},
  {"dir", l_dir},
  {"isdir", l_is_dir},
  {"crc32", lua_crc32},
  {NULL, NULL}
};


/*
** Open OSBF library
*/
int
OPENFUN (lua_State * L)
{
  const char *libname = luaL_checkstring(L, -1);

  init_crc();
  
  /* push os.exit onto the stack */
  lua_getfield(L, LUA_GLOBALSINDEX, "os");
  lua_getfield(L, -1, "exit");  /* s: os os.exit */

  /* push and initialize shared environment */
  lua_newtable(L);
  lua_pushvalue(L, -1);
  lua_replace(L, LUA_ENVIRONINDEX);  /* s: os os.exit env */
  lua_insert(L, -2);                 /* s: os env os.exit */
  lua_setfield(L, -2, "exit");       /* s: os env */
  lua_pushcfunction(L, lua_osbf_close_cache_and_exit);
  lua_setfield(L, -3, "exit");       /* s: os env */
  lua_newtable(L);
  lua_setfield(L, -2, "cache");      /* s: os env */
  lua_pop(L, 2); 


  /* class as userdata */
  luaL_newmetatable(L, CLASS_METANAME);     /* s: libname metatable */
  luaL_register(L, NULL, classmeta);
  lua_newtable(L);                          /* s: libname metatable opstable */
  lua_pushvalue(L, -1);  /* duplicate the class ops table */
  luaL_register(L, NULL, classops);        /* s: libname metatable opstable opstable */
  lua_pushcclosure(L, lua_classfields, 1); /* s: libname metatable opstable closure */
  lua_setfield(L, -3, "__index");          /* s: libname metatable opstable */

  lua_newtable(L);
  luaL_register(L, NULL, mutable_fields);
  lua_pushcclosure(L, lua_set_classfields, 2); /* capture ops and mutable fields */
  lua_setfield(L, -2, "__newindex");
  
  lua_pop(L, 1); /* goodbye metatable */

                                                /* s: libname */
  /* Open dir function */
  luaL_newmetatable (L, DIR_METANAME);
  lua_pushcfunction (L, dir_gc);
  lua_setfield (L, -2, "__gc");
  luaL_register (L, libname, osbf);
  set_info (L, lua_gettop(L));
  return 1;
}
