/*
 * OSBF-Lua - library for text classification
 *
 * This software is licensed to the public under the Free Software
 * Foundation's GNU GPL, version 2.  You may obtain a copy of the
 * GPL by visiting the Free Software Foundations web site at
 * www.fsf.org, and a copy is included in this distribution.
 *
 * Copyright 2005, 2006, 2007 Fidelis Assis, all rights reserved.
 * Copyright 2005, 2006, 2007 Williams Yerazunis, all rights reserved.
 *
 * Read the HISTORY_AND_AGREEMENT for details.
 *
 */

#include <assert.h>
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

#include "osbflib.h"

extern int OPENFUN (lua_State * L);  /* exported to the outside world */

/* configurable constants */
extern uint32_t microgroom_chain_length;
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

  lua_pushstring (L, "max_chain");
  lua_gettable (L, 1);
  if (lua_isnumber (L, -1))
    {
      microgroom_chain_length = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_pushstring (L, "stop_after");
  lua_gettable (L, 1);
  if (lua_isnumber (L, -1))
    {
      microgroom_stop_after = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_pushstring (L, "K1");
  lua_gettable (L, 1);
  if (lua_isnumber (L, -1))
    {
      K1 = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_pushstring (L, "K2");
  lua_gettable (L, 1);
  if (lua_isnumber (L, -1))
    {
      K2 = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_pushstring (L, "K3");
  lua_gettable (L, 1);
  if (lua_isnumber (L, -1))
    {
      K3 = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_pushstring (L, "limit_token_size");
  lua_gettable (L, 1);
  if (lua_isnumber (L, -1))
    {
      limit_token_size = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_pushstring (L, "max_token_size");
  lua_gettable (L, 1);
  if (lua_isnumber (L, -1))
    {
      max_token_size = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_pushstring (L, "max_long_tokens");
  lua_gettable (L, 1);
  if (lua_isnumber (L, -1))
    {
      max_long_tokens = luaL_checknumber (L, -1);
      options_set++;
    }
  lua_pop (L, 1);

  lua_pushstring (L, "pR_SCF");
  lua_gettable (L, 1);
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
  const char *cfcname = luaL_checkstring(L, 1);
  uint32_t buckets    = (uint32_t) luaL_checkint(L, 2);
  uint32_t minor = 0;
  char errmsg[OSBF_ERROR_MESSAGE_LEN] = { '\0' };

  if (osbf_create_cfcfile (cfcname, buckets, OSBF_FP_FN_VERSION,
                           minor, errmsg) == EXIT_SUCCESS) {
    return 0;
  } else {
    return luaL_error (L, "%s: %s", cfcname, errmsg);
  }
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
      assert(classes[n]);
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
  for (i = 0; i < num_classes - 1; i++) {
    if (!(sorted[i] <= sorted[i+1])) {
      fprintf(stderr, "Array not sorted: sorted[%d] = %.5g and sorted[%d] = %.5g\n",
              i, sorted[i], i+1, sorted[i+1]);
      assert(0);
    }
  }
  badsum = sum = 0.0;
  /* add small numbers first to avoid rounding error */
  for (i = 0; i < num_classes; i++) {
    sum += sorted[i];
    badsum += p_classes[i];
  }
  assert(fabs(sum - 1.0) < 10 * ULP);
#if 0
  fprintf(stderr, "Sum - 1.0 = %9g; ", sum - 1.0);
  fprintf(stderr, "smallest probability = %9g\n", sorted[0]);
  fprintf(stderr, "badsum - sum = %9g\n", badsum - sum);
#endif
}
#endif




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
  const char *classes[OSBF_MAX_CLASSES + 1];	/* set of classes */
  uint32_t flags = 0;		/* default value */
  double min_p_ratio;		/* min pmax/p,in ratio */
  /* class probabilities are returned in p_classes */
  double p_classes[OSBF_MAX_CLASSES];
  uint32_t p_trainings[OSBF_MAX_CLASSES];
  char errmsg[OSBF_ERROR_MESSAGE_LEN] = { '\0' };
  unsigned i, num_classes;

  /* get the arguments */
  text        = (const unsigned char *) luaL_checklstring (L, 1, &text_len);
  luaL_checktype (L, 2, LUA_TTABLE);
  num_classes = class_list_to_array(L, 2, classes, NELEMS(classes));
  flags       = (uint32_t) luaL_optnumber (L, 3, 0);
  min_p_ratio = (double) luaL_optnumber (L, 4, OSBF_MIN_PMAX_PMIN_RATIO);
  delimiters  = luaL_optlstring (L, 5, "", &delimiters_len);

  /* call osbf_classify */
  if (osbf_bayes_classify (text, text_len, delimiters, classes,
			   flags, min_p_ratio, p_classes, p_trainings,
			   errmsg) < 0)
    {
      return luaL_error(L, "%s", errmsg);
    }
  else
    {
      double sum = 0;
      /* push list of probabilities onto the stack */
      lua_newtable (L);
      /* push table with number of trainings per class */
      lua_newtable (L);
#if 0
      fprintf(stderr, "Classified %5d characters", text_len);
#endif
      for (i = 0; i < num_classes; i++)
	{
          sum += p_classes[i];
#if 0
          fprintf(stderr, "; P(database %d) = %.2g", i, p_classes[i]);
#endif
	  lua_pushnumber (L, (lua_Number) p_classes[i]);
	  lua_rawseti (L, -3, i + 1);
	  lua_pushnumber (L, (lua_Number) p_trainings[i]);
	  lua_rawseti (L, -2, i + 1);
	}
#if 0
      fprintf(stderr, "\n");
#endif
      check_sum_is_one(p_classes, num_classes);
      lua_pushnumber(L, sum);
      lua_insert(L, -3);
      return 3;
    }
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
  char errmsg[OSBF_ERROR_MESSAGE_LEN] = { '\0' };

  /* get args */
  sense  = luaL_checkint(L, 1);
  text   = (unsigned char *) luaL_checklstring (L, 2, &text_len);
  dbname = luaL_checkstring(L, 3);
  flags  = (uint32_t) luaL_optint(L, 4, 0);
  delimiters = luaL_optlstring(L, 5, "", &delimiters_len);
  luaL_checktype (L, 6, LUA_TNONE);

  if (osbf_bayes_train (text, text_len, delimiters, dbname,
			sense, flags, errmsg) < 0)
    {
      return luaL_error(L, "%s", errmsg);
    }
  else
    {
      return 0;
    }
}

/**********************************************************/

static int
old_osbf_train (lua_State * L, int sense)
{
  const unsigned char *text;
  size_t text_len;
  const char *delimiters;	/* extra token delimiters */
  size_t delimiters_len;
  const char *classes[OSBF_MAX_CLASSES + 1];
  int num_classes;
  size_t ctbt;			/* index of the class to be trained */
  uint32_t flags;
  char errmsg[OSBF_ERROR_MESSAGE_LEN] = { '\0' };

  /* get the arguments */
  text = (unsigned char *) luaL_checklstring (L, 1, &text_len);
  luaL_checktype (L, 2, LUA_TTABLE);
  num_classes = class_list_to_array(L, 2, classes, NELEMS(classes));
  ctbt = luaL_checknumber (L, 3) - 1;  /* Lua is 1-indexed; C is 0-indexed */
  flags = (uint32_t) luaL_optnumber (L, 4, (lua_Number) 0);
  delimiters = luaL_optlstring (L, 5, "", &delimiters_len);

  if (old_osbf_bayes_learn (text, text_len, delimiters, classes,
			ctbt, sense, flags, errmsg) < 0)
    {
      return luaL_error(L, "%s", errmsg);
    }
  else
    {
      return 0;
    }
}

/**********************************************************/

static int
lua_osbf_old_learn (lua_State * L)
{
  return old_osbf_train (L, 1);
}

/**********************************************************/

static int
lua_osbf_old_unlearn (lua_State * L)
{
  return old_osbf_train (L, -1);
}

/**********************************************************/

static int
lua_osbf_increment_false_positives (lua_State * L)
{
  const char *cfcfile;
  int delta;
  char errmsg[OSBF_ERROR_MESSAGE_LEN];

  cfcfile = luaL_checkstring (L, 1);
  delta  = luaL_optint(L, 2, 1);

  if (osbf_increment_false_positives (cfcfile, delta, errmsg) == 0)
    {
      return 0;
    }
  else
    {
      return luaL_error (L, "%s", errmsg);
    }
}

/**********************************************************/

static int
lua_osbf_dump (lua_State * L)
{
  const char *cfcfile, *csvfile;
  char errmsg[OSBF_ERROR_MESSAGE_LEN];

  cfcfile = luaL_checkstring (L, 1);
  csvfile = luaL_checkstring (L, 2);

  if (osbf_dump (cfcfile, csvfile, errmsg) == 0)
    {
      return 0;
    }
  else
    {
      return luaL_error (L, "%s", errmsg);
    }
}

/**********************************************************/

static int
lua_osbf_restore (lua_State * L)
{
  const char *cfcfile, *csvfile;
  char errmsg[OSBF_ERROR_MESSAGE_LEN];

  cfcfile = luaL_checkstring (L, 1);
  csvfile = luaL_checkstring (L, 2);

  if (osbf_restore (cfcfile, csvfile, errmsg) == 0)
    {
      return 0;
    }
  else
    {
      return luaL_error (L, "%s", errmsg);
    }
}

/**********************************************************/

static int
lua_osbf_import (lua_State * L)
{
  const char *cfcfile, *csvfile;
  char errmsg[OSBF_ERROR_MESSAGE_LEN];

  cfcfile = luaL_checkstring (L, 1);
  csvfile = luaL_checkstring (L, 2);

  if (osbf_import (cfcfile, csvfile, errmsg) == 0)
    {
      return 0;
    }
  else
    {
      return luaL_error (L, "%s", errmsg);
    }
}

/**********************************************************/

static int
lua_osbf_stats (lua_State * L)
{

  const char *cfcfile;
  STATS_STRUCT class;
  char errmsg[OSBF_ERROR_MESSAGE_LEN];
  int full = 1;

  cfcfile = luaL_checkstring (L, 1);
  if (lua_isboolean (L, 2))
    {
      full = lua_toboolean (L, 2);
    }

  if (osbf_stats (cfcfile, &class, errmsg, full) == 0)
    {
      lua_newtable (L);

      lua_pushliteral (L, "version");
      lua_pushnumber (L, (lua_Number) class.version);
      lua_settable (L, -3);

      lua_pushliteral (L, "buckets");
      lua_pushnumber (L, (lua_Number) class.total_buckets);
      lua_settable (L, -3);

      lua_pushliteral (L, "bucket_size");
      lua_pushnumber (L, (lua_Number) class.bucket_size);
      lua_settable (L, -3);

      lua_pushliteral (L, "header_size");
      lua_pushnumber (L, (lua_Number) class.header_size);
      lua_settable (L, -3);

      lua_pushliteral (L, "bytes");
      lua_pushnumber (L, class.header_size + class.total_buckets * class.bucket_size);
      lua_settable (L, -3);

      lua_pushliteral (L, "learnings");
      lua_pushnumber (L, (lua_Number) class.learnings);
      lua_settable (L, -3);

      lua_pushliteral (L, "extra_learnings");
      lua_pushnumber (L, (lua_Number) class.extra_learnings);
      lua_settable (L, -3);

      lua_pushliteral (L, "false_positives");
      lua_pushnumber (L, (lua_Number) class.false_positives);
      lua_settable (L, -3);

      lua_pushliteral (L, "false_negatives");
      lua_pushnumber (L, (lua_Number) class.false_negatives);
      lua_settable (L, -3);

      lua_pushliteral (L, "classifications");
      lua_pushnumber (L, (lua_Number) class.classifications);
      lua_settable (L, -3);

      if (full == 1)
	{
	  lua_pushliteral (L, "chains");
	  lua_pushnumber (L, (lua_Number) class.num_chains);
	  lua_settable (L, -3);

	  lua_pushliteral (L, "max_chain");
	  lua_pushnumber (L, (lua_Number) class.max_chain);
	  lua_settable (L, -3);

	  lua_pushliteral (L, "avg_chain");
	  lua_pushnumber (L, (lua_Number) class.avg_chain);
	  lua_settable (L, -3);

	  lua_pushliteral (L, "max_displacement");
	  lua_pushnumber (L, (lua_Number) class.max_displacement);
	  lua_settable (L, -3);

	  lua_pushliteral (L, "unreachable");
	  lua_pushnumber (L, (lua_Number) class.unreachable);
	  lua_settable (L, -3);

	  lua_pushliteral (L, "used_buckets");
	  lua_pushnumber (L, (lua_Number) class.used_buckets);
	  lua_settable (L, -3);

	  lua_pushliteral (L, "use");
	  if (class.total_buckets > 0)
	    lua_pushnumber (L, (lua_Number) ((double) class.used_buckets /
					     class.total_buckets));
	  else
	    lua_pushnumber (L, (lua_Number) 100);
	  lua_settable (L, -3);
	}

      return 1;
    }
  else
    {
      return luaL_error (L, "%s: %s", cfcfile, errmsg);
    }
}

/**********************************************************/

/*
** Assumes the table is on top of the stack, left by luaL_register call
*/
static void
set_info (lua_State * L, int idx)
{
  lua_pushliteral (L, "_COPYRIGHT");
  lua_pushliteral (L, "Copyright (C) 2005, 2006, 2007 Fidelis Assis");
  lua_settable (L, idx);
  lua_pushliteral (L, "_DESCRIPTION");
  lua_pushliteral (L, "OSBF-Lua is a Lua library for text classification.");
  lua_settable (L, idx);
  lua_pushliteral (L, "_NAME");
  lua_pushliteral (L, "OSBF-Lua");
  lua_settable (L, idx);
  lua_pushliteral (L, "_VERSION");
  lua_pushliteral (L, LIB_VERSION);
  lua_settable (L, idx);
  lua_pushliteral (L, "header_size");
  lua_pushnumber (L, (lua_Number) OSBF_CFC_HEADER_SIZE * sizeof(OSBF_BUCKET_STRUCT));
  lua_settable (L, idx);
  lua_pushliteral (L, "bucket_size");
  lua_pushnumber (L, (lua_Number) sizeof(OSBF_BUCKET_STRUCT));
  lua_settable (L, idx);

#define add_const(C) lua_pushliteral(L, #C); lua_pushnumber(L, (lua_Number) C); \
                     lua_settable(L, idx);
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
  luaL_getmetatable (L, "LuaBook.dir");
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

static const struct luaL_reg osbf[] = {
  {"create_db", lua_osbf_createdb},
  {"config", lua_osbf_config},
  {"classify", lua_osbf_classify},
  {"learn", lua_osbf_old_learn},
  {"unlearn", lua_osbf_old_unlearn},
  {"train", lua_osbf_train},
  {"increment_false_positives", lua_osbf_increment_false_positives},
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
  {NULL, NULL}
};


/*
** Open OSBF library
*/
int
OPENFUN (lua_State * L)
{
  const char *libname = luaL_checkstring(L, -1);
  /* Open dir function */
  luaL_newmetatable (L, "LuaBook.dir");
  /* set its __gc field */
  lua_pushstring (L, "__gc");
  lua_pushcfunction (L, dir_gc);
  lua_settable (L, -3);
  luaL_register (L, libname, osbf);
  set_info (L, -3); /* must come right after luaL_register */
  return 1;
}
