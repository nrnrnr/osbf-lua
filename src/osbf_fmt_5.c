/*
 * Format for database version 5
 *
 * See Copyright Notice in osbflib.h
 */


#include <string.h>

#include "osbflib.h"
#include "osbf_disk.h"

#include "osbfcvt.h"

static int i_recognize_image(void *image);
static off_t expected_size(void *image);
static void copy_header (OSBF_HEADER_STRUCT *header, void *image,
                         CLASS_STRUCT *class, OSBF_HANDLER *h);
static void copy_buckets(OSBF_BUCKET_STRUCT *buckets, void *image,
                          CLASS_STRUCT *class, OSBF_HANDLER *h);

#define MY_FORMAT osbf_format_5

struct osbf_format MY_FORMAT = {
  5,  /* my unique id */
  "OSBF-old",
  "OSBF_Bayes-spectrum file with false negatives only",
  0,  /* I am not native */
  i_recognize_image,
  expected_size,
  OSBF_COPY_FUNCTIONS(copy_header, copy_buckets),
};

/****************************************************************/

/* The obsolete format */

/* complete header */
/* define header size to be a multiple of the bucket size, approx. 4 Kbytes */
#define OBSOLETE_OSBF_CFC_HEADER_SIZE (4096 / sizeof(OSBF_BUCKET_STRUCT))

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

typedef struct
{
  uint32_t hash1;
  uint32_t hash2;
  uint32_t count;
} MY_BUCKET_STRUCT;

typedef union 
{
  OSBF_HEADER_STRUCT_2007_11 header;
  /*   buckets in header - not really buckets, but the header size is */
  /*   a multiple of the bucket size */
  MY_BUCKET_STRUCT bih[OBSOLETE_OSBF_CFC_HEADER_SIZE];
} MY_DISK_IMAGE;

static int i_recognize_image(void *p) {
  MY_DISK_IMAGE *image = p;
  return (image->header.version == MY_FORMAT.unique_id);
}

static off_t expected_size(void *p) {
  MY_DISK_IMAGE *image = p;
  MY_BUCKET_STRUCT *buckets = p;
  MY_BUCKET_STRUCT *buckets_lim =
    buckets + image->header.buckets_start + image->header.num_buckets;
  return (char *)buckets_lim - (char *)buckets;
}

static void
copy_header (OSBF_HEADER_STRUCT *xxxheader, void *p,
             CLASS_STRUCT *class, OSBF_HANDLER *h) 
{
  MY_DISK_IMAGE *image = p;
  OSBF_UNIVERSAL_HEADER uni;

  if (image->header.version != MY_FORMAT.unique_id)
    osbf_raise(h, "This can't happen: format for id %d sees "
                  "file %s with database version %d",
               MY_FORMAT.unique_id, class->classname, image->header.version);

  if (image->header.db_flags != 0) {
    char classname[200];
    strncpy(classname, class->classname, sizeof(classname));
    classname[sizeof(*classname)] = '\0';

    cleanup_partial_class(image, class, MY_FORMAT.native);
    osbf_raise(h, "Version %d database %s has nonzero flags %d",
               MY_FORMAT.unique_id, classname, image->header.db_flags);
  }

  memset(&uni, 0, sizeof(uni));
  uni.db_version      = image->header.version;
  uni.db_id           = OSBF_DB_ID;
  uni.db_flags        = image->header.db_flags;
  uni.buckets_start   = image->header.buckets_start;
  uni.num_buckets     = image->header.num_buckets;
  uni.learnings       = image->header.learnings;
  uni.false_negatives = image->header.mistakes;
  uni.false_positives = 0;  /* redundant, but clearer */
  uni.classifications = image->header.classifications;
  uni.extra_learnings = image->header.extra_learnings;

  osbf_native_header_of_universal(xxxheader, &uni);

}


static unsigned upconvert_bucket(OSBF_UNIVERSAL_BUCKET *dst, void *src);

/* all this goo is meant to be evaluated at compile time; hence the macros */

#define FIELD_OFFSET(P, f) ((char *)&(P)->f - (char *)(P))
#define FIELDS_EQ(P1, P2, f) \
  sizeof((P1)->f) == sizeof((P2)->f) && FIELD_OFFSET(P1, f) == FIELD_OFFSET(P2, f)

static void 
copy_buckets(OSBF_BUCKET_STRUCT *buckets, void *p,
             CLASS_STRUCT *class, OSBF_HANDLER *h) {
  MY_DISK_IMAGE *image = p;
  OSBF_UNIVERSAL_BUCKET uni;

  if (sizeof(uni) == sizeof(*buckets) && FIELDS_EQ(buckets, &uni, hash1) &&
      FIELDS_EQ(buckets, &uni, hash2) && FIELDS_EQ(buckets, &uni, count)) {
    /* everything matches */
    memcpy(buckets, (OSBF_BUCKET_STRUCT *)image + image->header.buckets_start,
           image->header.num_buckets * sizeof(*buckets));
  } else {
    osbf_raise(h, "bucket format has changed; upconverter in osbf_read5.c needs "
               "to be checked");
    osbf_native_buckets_of_universal(buckets,
            (OSBF_BUCKET_STRUCT *)image + image->header.buckets_start,
                                     upconvert_bucket, image->header.num_buckets);
  }
  (void)class; /* not otherwise used */
}

static unsigned upconvert_bucket(OSBF_UNIVERSAL_BUCKET *dst, void *src) {
  MY_BUCKET_STRUCT *bucket = src;
  dst->hash1 = bucket->hash1;
  dst->hash2 = bucket->hash2;
  dst->count = bucket->count;
  return sizeof(*bucket);
}
