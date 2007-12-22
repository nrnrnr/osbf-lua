/*
 *  osbflib.h 
 * 
 * This file defines CFC header structure, data and constants used
 * by the OSBF-Lua classifier.
 *
 * Copyright 2005, 2006, 2007 Fidelis Assis all rights reserved.
 * Copyright 2005, 2006, 2007 Williams Yerazunis, all rights reserved.
 *
 * Read the HISTORY_AND_AGREEMENT for details.
 */

#ifndef OSBF_LIB_H
#define OSBF_LIB_H 1

#include <float.h>
#include <inttypes.h>
#include <sys/types.h>

#include "osbferr.h"


enum db_version { OSBF_DB_BASIC_VERSION = 0, OSBF_DB_2007_11_VERSION = 5,
                  OSBF_DB_FP_FN_VERSION = 6 };
#define OSBF_CURRENT_VERSION OSBF_DB_FP_FN_VERSION
extern const char *db_version_names[];
  /* Array pointing to names, indexable by any enum_db_version */


typedef struct
{
  uint32_t hash1; /* bigram hashed with function 1 */
  uint32_t hash2; /* bigram hashed with function 2 */
  uint32_t count; /* number of msgs trained in which bigram has been seen */
} OSBF_BUCKET_STRUCT;

typedef struct /* used for disk image, so avoiding enum type for db_version */
{
  uint32_t db_version;		/* database version as it was on disk */
  uint32_t db_id;		/* database identification -- which is what, exactly?*/
  uint32_t db_flags;		/* for future use */
  uint32_t num_buckets;		/* number of buckets in the file */
  uint32_t learnings;		/* number of trainings done */
  uint32_t false_negatives;	/* number of false not classifications as this class */
  uint32_t false_positives;	/* number of false classifications as this class */
  uint64_t classifications;	/* number of classifications */
  uint32_t extra_learnings;	/* number of extra trainings done */
} OSBF_HEADER_STRUCT_2007_12;

typedef OSBF_HEADER_STRUCT_2007_12 OSBF_HEADER_STRUCT;

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
  unsigned char *bflags;	/* bucket flags */
  int fd;                       /* file descriptor of on-disk image */
  off_t fsize;                  /* size of on-disk image */
  osbf_class_usage usage;
  uint32_t learnings;
  double hits;
  uint32_t totalhits;
  uint32_t uniquefeatures;
  uint32_t missedfeatures;
} CLASS_STRUCT;

/* database statistics structure */
typedef struct
{
  uint32_t db_id;
  uint32_t db_version;
  uint32_t db_flags;
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

/* Database version */
enum osbf_database_ids {  /* NR is very puzzled about what 5 means */
  OSBF_DB_ID = 5
};

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
/* #define OSBF_MICROGROOM_CHAIN_LENGTH 29 */
/* if the value is zero the length will be calculated automatically */
#define OSBF_MICROGROOM_CHAIN_LENGTH 0

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

/****************************************************************/

extern void
osbf_packchain (CLASS_STRUCT * dbclass, uint32_t packstart, uint32_t packlen);

extern uint32_t osbf_microgroom (CLASS_STRUCT * dbclass, uint32_t bindex);


extern uint32_t osbf_next_bindex    (CLASS_STRUCT * dbclass, uint32_t bindex);

extern uint32_t osbf_prev_bindex    (CLASS_STRUCT * dbclass, uint32_t bindex);

extern uint32_t osbf_first_in_chain (CLASS_STRUCT * dbclass, uint32_t bindex);

extern uint32_t osbf_last_in_chain  (CLASS_STRUCT * dbclass, uint32_t bindex);

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
osbf_create_cfcfile (const char *cfcfile, uint32_t buckets,
		     uint32_t db_id, uint32_t db_version,
                     uint32_t db_flags, OSBF_HANDLER *h);

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
extern int osbf_unlock_file (int fd, uint32_t start, uint32_t len);
extern off_t check_file (const char *file);
  /* Check if a file exists. Return its length if yes and < 0 if no */

uint32_t strnhash (unsigned char *str, uint32_t len);

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
