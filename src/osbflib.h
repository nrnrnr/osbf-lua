/*
 *  osbflib.h 
 * 
 * This file defines CFC header structure, data and constants used
 * by the OSBF-Lua classifier.
 *
 ***********************************************************************
 * Copyright (C) 2005-2008 Fidelis Assis, all rights reserved.
 * Copyright (C) 2007-2008 Norman Ramsey, all rights reserved.
 * Copyright (C) 2005-2007 Williams Yerazunis, all rights reserved.
 *
 * See HISTORY_AND_AGREEMENT for details.
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 ***********************************************************************
 */

#ifndef OSBF_LIB_H
#define OSBF_LIB_H 1

#include <float.h>
#include <inttypes.h>
#include <sys/types.h>

#include "osbf_intcompat.h"   // needed on some platforms for uint64_t
#include "osbferr.h"

enum db_version { OSBF_DB_BASIC_VERSION = 0, OSBF_DB_2007_11_VERSION = 5,
                  OSBF_DB_FP_FN_VERSION = 6, OSBF_DB_MAGIC_VERSION = 7 };
#define OSBF_CURRENT_VERSION OSBF_DB_MAGIC_VERSION
extern const char *db_version_names[];
  /* Array pointing to names, indexable by any enum_db_version */


/* A variation on a Bloom filter, represented as a sequence of buckets.
   We hash a bigram two ways to find a count.  */

typedef struct
{
  uint32_t hash1; /* bigram hashed with function 1 */
  uint32_t hash2; /* bigram hashed with function 2 */
  uint32_t count; /* number of msgs trained in which bigram has been seen */
} OSBF_BUCKET_STRUCT;

/* The following terminology and invariants apply to the array of buckets:

  - If the count is nonzero, both hash1 and hash2 are nonzero.
  - If the count is zero, the bucket is available to be allocated.
  - A maxmimal sequence of buckets with nonzero counts is called a *chain*.
    A sequence may wrap around from buckets[num_buckets-1] to buckets[0].
  - If the count for a bigram is nonzero, its bucket will be located
    in the chain containing buckets[hash1 % num_buckets], and furthermore,
    it will be at, or to the right of, position (hash1 % num_buckets) in the
    chain. If a bug in the code caused a bucket to violate this invariant,
    the bucket would be deemed *unreachable*.
  - The distance between a bucket's actual position and (hash1 % num_buckets)
    is called the bucket's *displacement*.
  - The number of probes required to find an existing bucket is its
    displacement plus one.
  - To keep probing cost down, the maximum displacement is capped at the value
    of 'microgroom_displacement_trigger'. This number can be built in by means
    of the macro OSBF_MICROGROOM_DISPLACEMENT_TRIGGER, but it is more typical
    for the macro to be zero, in which case the maximum permissible
    displacement is calculated by max(14.85 + 1.5E-4 * NUM_BUCKETS (class), 29)
    in the function osbf_insert_bucket. The expression is a line that passes
    through the points (94321, 29) and (4000037, 615), determined by
    experiments. For databases with less than 94321 buckets, the maximum
    displacement is constant and equal to 29.

  - If a displacement exceeds the trigger, some buckets are removed from the
    chain by the *microgroomer*.  The microgroomer seems surprisingly
    complicated, but the idea is simple:
      . Find the smallest counts in the chain that are not 'locked' and force
        them to zero. Counts that change during a learning are locked so we
        don't zero what we've just learned.
      . Prefer to zero buckets with displacement 0 because they are probably 
        older and perhaps not as relevant to the user's current message stream.
      . Move buckets as needed to re-establish the invariant that every bucket
        b is located in the chain containing buckets[b->hash1 % num_buckets].

*/



typedef struct /* used for disk image, so avoiding enum type for db_version */
{
  uint32_t magic;               /* OSBF or FBSO */
  uint32_t db_version;		/* database version as it was on disk */
  uint32_t num_buckets;		/* number of buckets in the file */
  uint32_t learnings;		/* number of trainings done */
  uint32_t false_negatives;	/* number of false not classifications as this class */
  uint32_t false_positives;	/* number of false classifications as this class */
  uint64_t classifications;	/* number of classifications */
  uint32_t extra_learnings;	/* number of extra trainings done */
} OSBF_HEADER_STRUCT_2008_01;

typedef OSBF_HEADER_STRUCT_2008_01 OSBF_HEADER_STRUCT;

/* what the client promises to do with a class */
typedef enum osbf_class_usage {
  OSBF_READ_ONLY = 0, OSBF_WRITE_HEADER = 1, OSBF_WRITE_ALL = 2
} osbf_class_usage;
/* N.B. these values must be in order of increasing privilege, and they
   must always and forever be different from -1 */

/* three possible representations of class: 
      1. Mapped through mmap(), close via unmap()
      2. Copied into memory, read only so do not write on close
      3. Copied into memory and mutated, write on close
*/

typedef enum osbf_class_state {
  OSBF_CLOSED, OSBF_COPIED, OSBF_MAPPED
} osbf_class_state;

/* class structure */
typedef struct
{
  char *classname;               /* managed with malloc/free */
  const char *fmt_name;          /* short name of the on-disk format;
                                    statically allocated */
  OSBF_HEADER_STRUCT *header;
  OSBF_BUCKET_STRUCT *buckets;
  osbf_class_state state;
  unsigned char *bflags;	/* bucket flags [Note Flags] */
  int fd;                       /* file descriptor of on-disk image */
  off_t fsize;                  /* size of on-disk image */
  osbf_class_usage usage;
  uint32_t learnings;
  double hits;
  uint32_t totalhits;
  uint32_t uniquefeatures;
  uint32_t missedfeatures;
} CLASS_STRUCT;

/* [Note Flags]
   ~~~~~~~~~~~~
   The 'bucket flags' are used to track which buckets have been seen
   during a classification.  They are also used by the microgroomer,
   and so could be consulted during an import operation.  Otherwise 
   the flags are not meaningful.   Therefore the data-structure invariant 
   is as follows:
     - If the class is open, class->bflags points to private memory
       containing class->header->num_buckets bytes.
     - If the classifier or importer is not running, the contents 
       of those flags are meaningless.
*/

/* database statistics structure */
typedef struct
{
  uint32_t db_version;
  uint32_t total_buckets;
  uint32_t bucket_size;
  uint32_t used_buckets;
  uint32_t header_size;
  uint32_t learnings;
  uint32_t extra_learnings;
  uint32_t false_positives;
  uint32_t false_negatives;
  uint64_t classifications;
  uint32_t num_chains;
  uint32_t max_chain;
  double avg_chain;
  uint32_t max_displacement;
  uint32_t unreachable;
} STATS_STRUCT;

#define NELEMS(A) (sizeof(A)/sizeof((A)[0]))

/****************************************************************/

enum osbf_bucket_flags { BUCKET_LOCK_MASK = 0x80, BUCKET_FREE_MASK = 0x40 };

#define HASH_INDEX(cd, h)       (h % NUM_BUCKETS(cd))
#define NUM_BUCKETS(cd)         ((cd)->header->num_buckets)
#define VALID_BUCKET(cd, i)     (i < NUM_BUCKETS(cd))
#define BUCKET_FLAGS(cd, i)     (((cd)->bflags)[i])
#define BUCKET_IS_LOCKED(cd, i) (((cd)->bflags[i]) &  BUCKET_LOCK_MASK)
#define MARKED_FREE(cd, i)      (((cd)->bflags[i]) &  BUCKET_FREE_MASK)
#define MARK_IT_FREE(cd, i)     (((cd)->bflags[i]) |= BUCKET_FREE_MASK)
#define UNMARK_IT_FREE(cd, i)   (((cd)->bflags[i]) &= ~BUCKET_FREE_MASK)
#define LOCK_BUCKET(cd, i)      (((cd)->bflags[i]) |= BUCKET_LOCK_MASK)
#define UNLOCK_BUCKET(cd, i)    (((cd)->bflags[i]) &= ~BUCKET_LOCK_MASK)

#define BUCKET(cd, i) ((cd)->buckets[i])
#define BUCKET_VALUE(cd, i) (BUCKET(cd, i).count)
#define BUCKET_HASH(cd, i)  (BUCKET(cd, i).hash1)
#define BUCKET_KEY(cd, i)   (BUCKET(cd, i).hash2)

#define BUCKET_IN_CHAIN(cd, i) ((cd)->buckets[i].count > 0)
#define BUCKET_HASH_COMPARE(cd, i, h, k) (((cd)->buckets[i].hash1) == (h) && \
                                          ((cd)->buckets[i].hash2) == (k))
#define NEXT_BUCKET(cd, i) ((i) == (NUM_BUCKETS(cd) - 1) ? 0 : (i) + 1)
#define PREV_BUCKET(cd, i) ((i) == 0 ?  (NUM_BUCKETS(cd) - 1) : (i) - 1)

#define FAST_FIND_BUCKET(cd, h, k) \
  ((BUCKET_HASH_COMPARE(cd, HASH_INDEX(cd, h), h, k) || \
    !BUCKET_IN_CHAIN(cd, HASH_INDEX(cd, h))) \
     ? HASH_INDEX(cd, h) \
     : osbf_slow_find_bucket(class, HASH_INDEX(cd, h), h, k))

#define HASH_INDEX2(N, i) ((i) % (N))
#define BUCKET_MATCHES_2(b, h1, h2) ((b).hash1 == (h1) && (b).hash2 == (h2))
#define FAST_FIND_BUCKET2(class, buckets, num_buckets, h1, h2) \
  (BUCKET_MATCHES_2(buckets[HASH_INDEX2(num_buckets, h1)], h1, h2) || \
   buckets[HASH_INDEX2(num_buckets, h1)].count == 0 \
     ? HASH_INDEX2(num_buckets, h1) \
     : osbf_slow_find_bucket(class, HASH_INDEX2(num_buckets, h1), h1, h2))

#define NOT_SO_FAST_FIND_BUCKET(cd, h, k) \
  (BUCKET_HASH_COMPARE(cd, HASH_INDEX(cd, h), h, k) \
     ? HASH_INDEX(cd, h) \
     : osbf_find_bucket(class, h, k))

/****************************************************************/

/* define for CRM114 COMPATIBILITY */
#define CRM114_COMPATIBILITY

/* max feature count */
#define OSBF_MAX_BUCKET_VALUE 65535

/* default number of buckets */
#define OSBF_DEFAULT_SPARSE_SPECTRUM_FILE_LENGTH 94321

/* max chain len - microgrooming is triggered after this, if enabled */
/* #define OSBF_MICROGROOM_DISPLACEMENT_TRIGGER 29 */
/* if the value is zero the length will be calculated automatically */
#define OSBF_MICROGROOM_DISPLACEMENT_TRIGGER 0

/* max number of buckets groom-zeroed */
#define OSBF_MICROGROOM_STOP_AFTER 128

/* groom locked buckets? 0 => no; 1 => yes */
/* comment the line below to enable locked buckets grooming */
#define OSBF_MICROGROOM_LOCKED 0

#if !defined OSBF_MICROGROOM_LOCKED
#define OSBF_MICROGROOM_LOCKED 1
#endif

/* comment the line below to disable long tokens "accumulation" */
#define OSBF_MAX_TOKEN_SIZE 60

#if defined OSBF_MAX_TOKEN_SIZE
  /* accumulate hashes up to this many long tokens */
#define OSBF_MAX_LONG_TOKENS 1000
#endif

/* min ratio between max and min P(F|C) */
#define OSBF_MIN_PMAX_PMIN_RATIO 1

/* max number of classes */
#define OSBF_MAX_CLASSES 128

#define OSB_BAYES_WINDOW_LEN 5

/* define the max length of a filename */
#define MAX_FILE_NAME_LEN 255

#define OSBF_DBL_MIN DBL_MIN
/* #define OSBF_DBL_MIN 1E-50 */
#define OSBF_SMALLP (10 * OSBF_DBL_MIN) /* a very small but nonzero probability */
#define OSBF_ERROR_MESSAGE_LEN 512

enum learn_flags {
  NO_MICROGROOM	 = 1,
  FALSE_NEGATIVE = 2,	/* increase false_negative counter */
  EXTRA_LEARNING = 4	/* flag for extra learning */
};

enum classify_flags {
  NO_EDDC			= 1,
  COUNT_CLASSIFICATIONS		= 2
};

/* possible counters for a-priori probability estimation */
enum a_priori_options {
  LEARNINGS = 0,
  INSTANCES,
  CLASSIFICATIONS,
  MISTAKES,                    /* FALSE_NEGATIVES */
 /* end of valid values */
  A_PRIORI_UPPER_LIMIT         /* upper limit */
};

extern enum a_priori_options a_priori; 
     /* which method to use for prior probabilities */

/* mapping for a_priori_options enum */
extern const char *a_priori_strings[];
 
/****************************************************************/

extern uint32_t
osbf_find_bucket   (CLASS_STRUCT * dbclass, uint32_t hash, uint32_t key);

extern uint32_t
osbf_slow_find_bucket (CLASS_STRUCT * class, uint32_t start, uint32_t hash, uint32_t key);
extern void
osbf_update_bucket (CLASS_STRUCT * dbclass, uint32_t bindex, int delta);

extern void
osbf_insert_bucket (CLASS_STRUCT * dbclass, uint32_t bindex,
		    uint32_t hash, uint32_t key, int value);
extern void
osbf_create_cfcfile (const char *cfcfile, uint32_t buckets, OSBF_HANDLER *h);

extern void
osbf_dump    (const CLASS_STRUCT *cfcfile, const char *csvfile, OSBF_HANDLER *h);
extern void
osbf_restore (const char *cfcfile, const char *csvfile, OSBF_HANDLER *h);
extern void 
osbf_import  (CLASS_STRUCT *class_to, const CLASS_STRUCT *class_from, OSBF_HANDLER *h);
extern void osbf_stats   (const CLASS_STRUCT *cfcfile, STATS_STRUCT * stats,
                          OSBF_HANDLER *h, int full);

extern void append_error_message(char *err1, const char *err2);

extern void
osbf_bayes_classify (const unsigned char *text,
		     unsigned long len,
		     const char *delims,  /* token delimiters */
                     CLASS_STRUCT *classes[],
                     unsigned nclasses,
		     enum classify_flags flags,
		     double min_pmax_pmin_ratio, double ptc[],
		     uint32_t ptt[], OSBF_HANDLER *h);

extern void
osbf_bayes_train (const unsigned char *text,
		  unsigned long len,
                  const char *delims,      /* token delimiters */
		  CLASS_STRUCT *class,
		  int sense, enum learn_flags flags, OSBF_HANDLER *h);

   /* token delimiters are never NULL but may be the empty string */

extern void
osbf_open_class (const char *classname, osbf_class_usage usage, CLASS_STRUCT * class,
		 OSBF_HANDLER *h);
extern void osbf_close_class (CLASS_STRUCT * class, OSBF_HANDLER *h);
extern int osbf_lock_file (int fd, uint32_t start, uint32_t len);
extern int osbf_lock_class (CLASS_STRUCT *class, uint32_t start, uint32_t len);
extern int osbf_unlock_file (int fd, uint32_t start, uint32_t len);
extern int osbf_unlock_class (CLASS_STRUCT *class, uint32_t start, uint32_t len);
extern off_t check_file (const char *file);
  /* Check if a file exists. Return its length if yes and < 0 if no */

uint32_t strnhash (const unsigned char *str, uint32_t len);

extern void
osbf_increment_false_positives (const char *cfcfile, int delta, OSBF_HANDLER *h);

/* We can't use assert() because the mail must be filtered no matter what.
   We use either osbf_raise or UNLESS_CLEANUP_RAISE */

#define UNLESS_CLEANUP_RAISE(p, cleanup, raise_args) \
  do { if (!(p)) { cleanup; osbf_raise raise_args; } } while(0)



void *osbf_malloc(size_t size, OSBF_HANDLER *h, const char *what);
void *osbf_calloc(size_t nmemb, size_t size, OSBF_HANDLER *h, const char *what);

#endif

#ifdef DMALLOC
#include "dmalloc.h"
#endif

#define QUOTEQUOTE(s) #s
#define QUOTE(s) QUOTEQUOTE(s)
