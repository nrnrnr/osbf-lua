/*
 * Format for database version 7.
 *
 * See Copyright Notice in osbflib.h
 */



#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include "osbflib.h"
#include "osbf_disk.h"

#include "osbfcvt.h"

static int i_recognize_image(void *image);
static off_t expected_size(void *image);
static void *find_header (void *image, CLASS_STRUCT *class, OSBF_HANDLER *h);
static void *find_buckets(void *image, CLASS_STRUCT *class, OSBF_HANDLER *h);

#define DEBUG 1

#define MY_FORMAT osbf_format_7

struct osbf_format MY_FORMAT = {
  7,  /* my unique id */
  "OSBF-MAGIC-FP-FN",
  "OSBF_Bayes-spectrum file with false negatives, false positives, and magic number",
  1,  /* I am native */
  i_recognize_image,
  expected_size,
  OSBF_FIND_FUNCTIONS(find_header, find_buckets),
};

/****************************************************************/

/* If the first four characters of the file are OSBF or FBSO, we recognize it. 
   OSBF indicates a little-endian representation of integers on disk; FBSO is 
   big-endian.  At present we punt files of the wrong endianness, but there's no
   reason we couldn't provide a non-native format to convert them.
*/

typedef OSBF_HEADER_STRUCT_2008_01 MY_DISK_IMAGE;
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
  assert(i_recognize_image(p));
  uint32_t num_buckets =
    image->magic == OSBF_LITTLE ? image->num_buckets : swap(image->num_buckets);
  return sizeof(*image) + sizeof(MY_BUCKET_STRUCT) * num_buckets;
}

off_t osbf_native_image_size  (CLASS_STRUCT *class) {
  assert(i_recognize_image(class->header));
  return expected_size(class->header);
}

static void *find_header (void *p, CLASS_STRUCT *class, OSBF_HANDLER *h) {
  MY_DISK_IMAGE *image = p;
  if (image->magic == OSBF_BIG) {
    char classname[200];
    strncpy(classname, class->classname, sizeof(classname));
    classname[sizeof(classname)-1] = '\0';
    cleanup_partial_class(image, class, MY_FORMAT.native);
    osbf_raise(h, "OSBF class file %s has its bytes swapped---may have been copied"
               " from a machine of the wrong endianness", classname);
  }
  if (image->db_version != MY_FORMAT.unique_id)
    osbf_raise(h, "Bad internal invariants for image:\n"
               "  expected unique id (database version) %d, but found %d\n",
               MY_FORMAT.unique_id, image->db_version);
  return p;
}

static void *find_buckets (void *p, CLASS_STRUCT *class, OSBF_HANDLER *h) {
  MY_DISK_IMAGE *image = p;
  (void)class; (void)h; /* not used */
  return image+1;
}

void osbf_native_write_class(CLASS_STRUCT *class, FILE *fp, OSBF_HANDLER *h) {
  char classname[200];
  strncpy(classname, class->classname, sizeof(classname));
  classname[sizeof(classname)-1] = '\0';
  
  if (class->header->db_version != MY_FORMAT.unique_id)
    osbf_raise(h, "Version %d format asked to write version %d database as native\n",
               MY_FORMAT.unique_id, class->header->db_version);

  if (!i_recognize_image(class->header))
    osbf_raise(h, "Tried to write class without suitable magic number in header");

  if (DEBUG) {
    unsigned j;
    fprintf(stderr, "Writing native class with header");
    for (j = 0; j < sizeof(*class->header) / sizeof(unsigned); j++)
      fprintf(stderr, " %u", ((uint32_t *)class->header)[j]);
    fprintf(stderr, "\n");
  }

  if (fwrite(class->header, sizeof(*class->header), 1, fp) != 1) {
    cleanup_partial_class(class->header, class, 1);
    osbf_raise(h, "%s", "Could not write header to class file %s", classname);
  }
  if (fwrite(class->buckets, sizeof(*class->buckets), class->header->num_buckets, fp)
      != class->header->num_buckets) {
    cleanup_partial_class(class->header, class, 1);
    remove(classname); /* salvage is impossible */
    osbf_raise(h, "Could not write buckets to class file %s", classname);
  }
  if (expected_size(class->header) != ftell(fp)) {
    long size = expected_size(class->header);
    cleanup_partial_class(class->header, class, 1);
    osbf_raise(h, "Wrote %ld bytes to file %s; expected to write %ld bytes", 
               ftell(fp), classname, size);
  }
}

void osbf_native_write_header(CLASS_STRUCT *class, FILE *fp, OSBF_HANDLER *h) {
  if (class->header->db_version != MY_FORMAT.unique_id)
    osbf_raise(h, "Version %d format asked to write version %d database as native\n",
               MY_FORMAT.unique_id, class->header->db_version);

  if (!i_recognize_image(class->header))
    osbf_raise(h, "Tried to write class without suitable magic number in header");

  if (DEBUG) {
    unsigned j;
    fprintf(stderr, "Writing native header");
    for (j = 0; j < sizeof(*class->header) / sizeof(unsigned); j++)
      fprintf(stderr, " %u", ((unsigned *)class->header)[j]);
    fprintf(stderr, "\n");
  }

  if (fwrite(class->header, sizeof(*class->header), 1, fp) != 1) {
    char classname[200];
    strncpy(classname, class->classname, sizeof(classname));
    classname[sizeof(classname)-1] = '\0';
    cleanup_partial_class(class->header, class, 1);
    osbf_raise(h, "Could not write header to class file %s", class->classname);
  }
}



/*****************************************************************/

void
osbf_create_cfcfile (const char *cfcfile, uint32_t num_buckets, OSBF_HANDLER *h)
{
  FILE *f;
  uint32_t i_aux;
  MY_DISK_IMAGE image;
  OSBF_BUCKET_STRUCT bucket = { 0, 0, 0 };
  
  f = create_file_if_absent(cfcfile, h);

  /* zero all fields in header and buckets */
  memset(&image, 0, sizeof(image));

  /* Set the header. */
  image.magic       = OSBF_LITTLE;
  image.db_version  = MY_FORMAT.unique_id;
  image.num_buckets = num_buckets;

  /* Write header */
  osbf_raise_unless (fwrite (&image, sizeof (image), 1, f) == 1, h,
                     "Couldn't write the file header: '%s'", cfcfile);

  /*  Initialize CFC hashes - zero all buckets */
  for (i_aux = 0; i_aux < num_buckets; i_aux++)
    if (fwrite (&bucket, sizeof (bucket), 1, f) != 1)
      osbf_raise(h, "Couldn't write to: '%s'", cfcfile);

  osbf_raise_unless(ftell(f) == expected_size(&image), h,
                    "Internal fault: bad size calculation");
  fclose (f);
}

void osbf_native_header_of_universal(OSBF_HEADER_STRUCT *dst,
                                     const OSBF_UNIVERSAL_HEADER *src) {
  dst->magic           = OSBF_LITTLE;
  dst->db_version      = src->db_version;
  dst->num_buckets     = src->num_buckets;
  dst->learnings       = src->learnings;
  dst->false_negatives = src->false_negatives;
  dst->false_positives = src->false_positives;
  dst->classifications = src->classifications;
  dst->extra_learnings = src->extra_learnings;
} 
