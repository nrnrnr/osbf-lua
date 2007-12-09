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

#include <float.h>
#include <inttypes.h>

enum db_version { OSBF_DB_BASIC_VERSION = 0, OSBF_DB_2007_11_VERSION = 5,
                  OSBF_DB_FP_FN_VERSION = 6 };
#define OSBF_CURRENT_VERSION OSBF_DB_FP_FN_VERSION
extern const char *db_version_names[];
  /* Array pointing to names, indexable by any enum_db_version */


typedef struct
{
  uint32_t hash;
  uint32_t key;
  uint32_t value;
} OSBF_BUCKET_STRUCT;

typedef struct /* used for disk image, so avoiding enum type for db_version */
{
  uint32_t db_version;		/* database version */
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

/* class structure */
typedef struct
{
  const char *classname;
  OSBF_HEADER_STRUCT *header;
  OSBF_BUCKET_STRUCT *buckets;
  int mmapped;
  unsigned char *bflags;	/* bucket flags */
  int fd;
  int flags;			/* open flags, O_RDWR, O_RDONLY */
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
#define OSBF_DB_ID              5

#define BUCKET_LOCK_MASK  0x80
#define BUCKET_FREE_MASK  0x40
#define HASH_INDEX(cd, h) (h % NUM_BUCKETS(cd))
#define NUM_BUCKETS(cd) ((cd)->header->num_buckets)
#define VALID_BUCKET(cd, i) (i < NUM_BUCKETS(cd))
#define BUCKET_HASH(cd, i) (((cd)->buckets)[i].hash)
#define BUCKET_KEY(cd, i) (((cd)->buckets)[i].key)
#define BUCKET_VALUE(cd, i) (((cd)->buckets)[i].value)
#define BUCKET_FLAGS(cd, i) (((cd)->bflags)[i])
#define BUCKET_RAW_VALUE(cd, i) (((cd)->buckets)[i].value)
#define BUCKET_IS_LOCKED(cd, i) ((((cd)->bflags)[i]) & BUCKET_LOCK_MASK)
#define MARKED_FREE(cd, i) ((((cd)->bflags)[i]) & BUCKET_FREE_MASK)
#define MARK_IT_FREE(cd, i) ((((cd)->bflags)[i]) |= BUCKET_FREE_MASK)
#define UNMARK_IT_FREE(cd, i) (((cd)->bflags)[i]) &= (~BUCKET_FREE_MASK)
#define LOCK_BUCKET(cd, i) (((cd)->bflags)[i]) |= BUCKET_LOCK_MASK
#define UNLOCK_BUCKET(cd, i) (((cd)->bflags)[i]) &= (~BUCKET_LOCK_MASK)
#define SET_BUCKET_VALUE(cd, i, val) (((cd)->buckets)[i].value) = val
#define SETL_BUCKET_VALUE(cd, i, val) (((cd)->buckets)[i].value) = (val);  \
                                        LOCK_BUCKET(cd, i)

#define BUCKET_IN_CHAIN(cd, i) (BUCKET_VALUE(cd, i) != 0)
#define BUCKET_HASH_COMPARE(cd, i, h, k) (((cd)->buckets[i].hash) == (h) && \
                                          ((cd)->buckets[i].key)  == (k))
#define NEXT_BUCKET(cd, i) ((i) == (NUM_BUCKETS(cd) - 1) ? 0 : i + 1)
#define PREV_BUCKET(cd, i) ((i) == 0 ?  (NUM_BUCKETS(cd) - 1) : (i) - 1)

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

extern uint32_t strnhash (unsigned char *str, uint32_t len);
extern off_t check_file (const char *file);

extern void
osbf_packchain (CLASS_STRUCT * dbclass, uint32_t packstart, uint32_t packlen);

extern uint32_t osbf_microgroom (CLASS_STRUCT * dbclass, uint32_t bindex);


extern uint32_t osbf_next_bindex    (CLASS_STRUCT * dbclass, uint32_t bindex);

extern uint32_t osbf_prev_bindex    (CLASS_STRUCT * dbclass, uint32_t bindex);

extern uint32_t osbf_first_in_chain (CLASS_STRUCT * dbclass, uint32_t bindex);

extern uint32_t osbf_last_in_chain  (CLASS_STRUCT * dbclass, uint32_t bindex);

extern uint32_t
osbf_find_bucket   (CLASS_STRUCT * dbclass, uint32_t hash, uint32_t key);

extern void
osbf_update_bucket (CLASS_STRUCT * dbclass, uint32_t bindex, int delta);

extern void
osbf_insert_bucket (CLASS_STRUCT * dbclass, uint32_t bindex,
		    uint32_t hash, uint32_t key, int value);
extern int
osbf_create_cfcfile (const char *cfcfile, uint32_t buckets,
		     uint32_t db_id, uint32_t db_version,
                     uint32_t db_flags, char *err_buf);

int osbf_dump    (const char *cfcfile, const char *csvfile, char *err_buf);
int osbf_restore (const char *cfcfile, const char *csvfile, char *err_buf);
int osbf_import  (const char *cfcfile, const char *csvfile, char *err_buf);
int osbf_stats   (const char *cfcfile, STATS_STRUCT * stats,
		  char *err_buf, int full);

extern int
osbf_bayes_classify (const unsigned char *text,
		     unsigned long len,
		     const char *pattern,
		     const char *classes[],
		     enum classify_flags flags,
		     double min_pmax_pmin_ratio, double ptc[],
		     uint32_t ptt[], char *err_buf);

extern int
old_osbf_bayes_learn (const unsigned char *text,
		  unsigned long len,
		  const char *pattern,
		  const char *classes[],
		  unsigned tc, int sense, enum learn_flags flags, char *err_buf);

extern int
osbf_bayes_train (const unsigned char *text,
		  unsigned long len,
		  const char *pattern,
		  const char *class,
		  int sense, enum learn_flags flags, char *err_buf);

extern int
osbf_open_class (const char *classname, int flags, CLASS_STRUCT * class,
		 char *err_buf);
extern int osbf_close_class (CLASS_STRUCT * class, char *err_buf);
extern int osbf_lock_file (int fd, uint32_t start, uint32_t len);
extern int osbf_unlock_file (int fd, uint32_t start, uint32_t len);
extern int
osbf_increment_false_positives (const char *cfcfile, int delta, char *err_buf);

/* We can't use assert() because the mail must be filtered no matter what.
   The CHECK and CHECKF macros help. */

#define CHECK(p, code, message) \
  do { \
    if (!(p)) { \
      strncpy (err_buf, (message), OSBF_ERROR_MESSAGE_LEN); \
      return (code); \
    } \
  } while (0)

#define CHECKF(p, code, fmt, arg) \
  do { \
    if (!(p)) { \
      snprintf (err_buf, OSBF_ERROR_MESSAGE_LEN, fmt, arg); \
      return (code); \
    } \
  } while (0)
		


/* complete header */
/* define header size to be a multiple of the bucket size, approx. 4 Kbytes */
#define OBSOLETE_OSBF_CFC_HEADER_SIZE (4096 / sizeof(OSBF_BUCKET_STRUCT))

/* obsolete headers */

typedef struct
{
  uint32_t version;             /* database version */
  uint32_t db_flags;            /* for future use */
  uint32_t buckets_start;       /* offset to first bucket in bucket size units */
  uint32_t num_buckets;         /* number of buckets in the file */
  uint32_t learnings;           /* number of trainings done */
  uint32_t mistakes;            /* number of wrong classifications */
  uint64_t classifications;     /* number of classifications */
  uint32_t extra_learnings;     /* number of extra trainings done */
} OSBF_HEADER_STRUCT_2007_11;  /* structure through Nov 2007 */

typedef union obsolete_disk_rep
{
  OSBF_HEADER_STRUCT_2007_11 header;
  /*   buckets in header - not really buckets, but the header size is */
  /*   a multiple of the bucket size */
  OSBF_BUCKET_STRUCT bih[OBSOLETE_OSBF_CFC_HEADER_SIZE];
} OBSOLETE_OSBF_HEADER_BUCKET_UNION;

