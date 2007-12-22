/* format for database version 7 */

#include <stdlib.h>
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

#define MY_FORMAT osbf_format_7

struct osbf_format MY_FORMAT = {
  7,  /* my unique id */
  "OSBF-MAGIC-FP-FN",
  "OSBF_Bayes-spectrum file with false negatives, false positives, and magic number",
  0,  /* I am not native */
  i_recognize_image,
  expected_size,
  OSBF_COPY_FUNCTIONS(copy_header, copy_buckets),
};

/****************************************************************/

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
} OSBF_HEADER_STRUCT_2007_12_13;

/* If the first four characters of the file are OSBF or FBSO, we recognize it. 
   OSBF indicates a little-endian representation of integers on disk; FBSO is 
   big-endian.  At present we punt files of the wrong endianness, but there's no
   reason we couldn't provide a non-native format to convert them.
*/

typedef OSBF_HEADER_STRUCT_2007_12_13 MY_DISK_IMAGE;
typedef OSBF_BUCKET_STRUCT MY_BUCKET_STRUCT;

#define U(c) ((unsigned char)(c))
#define MK_BIG_ENDIAN(A, B, C, D) (U(D) | (U(C) << 8) | (U(B) << 16) | (U(A) << 24))

enum magic {
  OSBF_BIG    = MK_BIG_ENDIAN('O', 'S', 'B', 'F'),
  OSBF_LITTLE = MK_BIG_ENDIAN('F', 'B', 'S', 'O')
};

static uint32_t swap(uint32_t n);

static uint32_t swap(uint32_t n) {
  return MK_BIG_ENDIAN(n & 0xff, n >> 8 & 0xff, n >> 16 & 0xff, n >> 24 & 0xff);
}
  
static int i_recognize_image(void *p) {
  MY_DISK_IMAGE *image = p;
  if (swap(OSBF_BIG) != OSBF_LITTLE) abort();
  return image->magic == OSBF_LITTLE || image->magic == OSBF_BIG;
}

static off_t expected_size(void *p) {
  MY_DISK_IMAGE *image = p;
  unsigned num_buckets =
    image->magic == OSBF_LITTLE ? image->num_buckets : swap(image->num_buckets);
  return sizeof(*image) + sizeof(MY_BUCKET_STRUCT) * num_buckets;
}

static void
copy_header (OSBF_HEADER_STRUCT *xxxheader, void *p,
             CLASS_STRUCT *class, OSBF_HANDLER *h) 
{
  MY_DISK_IMAGE *image = p;
  OSBF_UNIVERSAL_HEADER uni;

  char classname[200];
  strncpy(classname, class->classname, sizeof(classname));
  classname[sizeof(*classname)] = '\0';

  if (image->db_version != MY_FORMAT.unique_id)
    osbf_raise(h, "This can't happen: format for id %d sees "
                  "file %s with database version %d",
               MY_FORMAT.unique_id, class->classname, image->db_version);

  if (image->magic == OSBF_BIG) {
    cleanup_partial_class(image, class, MY_FORMAT.native);
    osbf_raise(h, "OSBF class file %s has its bytes swapped---may have been copied"
               " from a machine of the wrong endianness", classname);
  }

  memset(&uni, 0, sizeof(uni));
  uni.db_version      = image->db_version;
  uni.db_id           = OSBF_DB_ID;
  uni.buckets_start   = (OSBF_BUCKET_STRUCT *)(image+1) - (OSBF_BUCKET_STRUCT *)image;
  uni.num_buckets     = image->num_buckets;
  uni.learnings       = image->learnings;
  uni.false_negatives = image->false_negatives;
  uni.false_positives = image->false_positives;
  uni.classifications = image->classifications;
  uni.extra_learnings = image->extra_learnings;

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

  if (sizeof(uni) == sizeof(*buckets) && FIELDS_EQ(buckets, &uni, hash) &&
      FIELDS_EQ(buckets, &uni, key) && FIELDS_EQ(buckets, &uni, value)) {
    /* everything matches */
    memcpy(buckets, (OSBF_BUCKET_STRUCT *)(image + 1),
           image->num_buckets * sizeof(*buckets));
  } else {
    osbf_raise(h, "bucket format has changed; upconverter in osbf_fmt_7.c needs "
               "to be checked");
    osbf_native_buckets_of_universal(buckets, (OSBF_BUCKET_STRUCT *)(image + 1),
                                     upconvert_bucket, image->num_buckets);
  }
  (void)class; /* not otherwise used */
}

static unsigned upconvert_bucket(OSBF_UNIVERSAL_BUCKET *dst, void *src) {
  MY_BUCKET_STRUCT *bucket = src;
  dst->hash  = bucket->hash;
  dst->key   = bucket->key;
  dst->value = bucket->value;
  return sizeof(*bucket);
}
