/*
 * Format for database version 6
 *
 * See Copyright Notice in osbflib.h
 */



#include <string.h>

#include "osbflib.h"
#include "osbf_disk.h"
#include "osbfcvt.h"

#define DEBUG 0

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

typedef OSBF_HEADER_STRUCT_2007_12 MY_HEADER_STRUCT;
typedef OSBF_BUCKET_STRUCT MY_BUCKET_STRUCT;

typedef struct {
  OSBF_HEADER_STRUCT_2007_12 headers[1];
} MY_DISK_IMAGE;

static int i_recognize_image(void *image);
static off_t expected_size(void *image);
static void copy_header (OSBF_HEADER_STRUCT *header, void *image,
                         CLASS_STRUCT *class, OSBF_HANDLER *h);
static void copy_buckets(OSBF_BUCKET_STRUCT *buckets, void *image,
                          CLASS_STRUCT *class, OSBF_HANDLER *h);

#define MY_FORMAT osbf_format_6

struct osbf_format MY_FORMAT = {
  6,  /* my unique id */
  "OSBF-FP-FN",
  "OSBF_Bayes-spectrum file with false positives and negatives",
  0,  /* I am not native */
  i_recognize_image,
  expected_size,
  OSBF_COPY_FUNCTIONS(copy_header, copy_buckets),
};



static long image_size(const MY_HEADER_STRUCT *header);
static long image_size(const MY_HEADER_STRUCT *header) {
  return sizeof(MY_DISK_IMAGE) + header->num_buckets * sizeof(OSBF_BUCKET_STRUCT);
}

static int i_recognize_image(void *p) {
  MY_DISK_IMAGE *image = p;
  return (image->headers[0].db_version == MY_FORMAT.unique_id);
}

static off_t expected_size(void *p) {
  MY_DISK_IMAGE *image = p;
  return image_size(&image->headers[0]);
}

static void
copy_header (OSBF_HEADER_STRUCT *xxxheader, void *p,
             CLASS_STRUCT *class, OSBF_HANDLER *h) 
{
  MY_DISK_IMAGE *image = p;
  OSBF_UNIVERSAL_HEADER uni;

  char classname[200];
  strncpy(classname, class->classname, sizeof(classname));
  classname[sizeof(classname)-1] = '\0';

  if (image->headers[0].db_version != MY_FORMAT.unique_id)
    osbf_raise(h, "This can't happen: format for id %d sees "
                  "file %s with database version %d",
               MY_FORMAT.unique_id, class->classname, image->headers[0].db_version);

  memset(&uni, 0, sizeof(uni));
  uni.db_version      = image->headers[0].db_version;
  uni.db_id           = image->headers[0].db_id;
  uni.db_flags        = image->headers[0].db_flags;
  uni.buckets_start   = (OSBF_BUCKET_STRUCT *) &image->headers[1] -
                        (OSBF_BUCKET_STRUCT *) &image->headers[0];
  uni.num_buckets     = image->headers[0].num_buckets;
  uni.learnings       = image->headers[0].learnings;
  uni.false_negatives = image->headers[0].false_negatives;
  uni.false_positives = image->headers[0].false_positives;
  uni.classifications = image->headers[0].classifications;
  uni.extra_learnings = image->headers[0].extra_learnings;

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
    memcpy(buckets, (OSBF_BUCKET_STRUCT *)(image + 1),
           image->headers[0].num_buckets * sizeof(*buckets));
  } else {
    osbf_raise(h, "bucket format has changed; upconverter in osbf_fmt_6.c needs "
               "to be checked");
    osbf_native_buckets_of_universal(buckets, (OSBF_BUCKET_STRUCT *)(image + 1),
                                     upconvert_bucket, image->headers[0].num_buckets);
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
