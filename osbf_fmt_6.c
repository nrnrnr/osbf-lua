/* reader for database version 6 */

#include <string.h>

#include "osbflib.h"
#include "osbf_disk.h"
#include "osbfcvt.h"

typedef struct {
  OSBF_HEADER_STRUCT_2007_12 headers[1];
} MY_DISK_IMAGE;

static int i_recognize_image(void *image);
static off_t expected_size(void *image);
static void *find_header (void *image, CLASS_STRUCT *class, OSBF_HANDLER *h);
static void *find_buckets(void *image, CLASS_STRUCT *class, OSBF_HANDLER *h);

#define MY_READER osbf_reader_6

struct osbf_reader MY_READER = {
  6,  /* my unique id */
  "OSBF-FP-FN",
  "OSBF_Bayes-spectrum file with false positives and negatives",
  1,  /* I am native */
  i_recognize_image,
  expected_size,
  { (void (*)(OSBF_HEADER_STRUCT *, void *, CLASS_STRUCT *, OSBF_HANDLER *))
    find_header },
  { (void (*)(OSBF_BUCKET_STRUCT *, void *, CLASS_STRUCT *, OSBF_HANDLER *))
    find_buckets },
};



static long image_size(const OSBF_HEADER_STRUCT *header);
static long image_size(const OSBF_HEADER_STRUCT *header) {
  return sizeof(MY_DISK_IMAGE) + header->num_buckets * sizeof(OSBF_BUCKET_STRUCT);
}

off_t osbf_native_image_size  (CLASS_STRUCT *class) {
  return image_size(class->header);
}


static int i_recognize_image(void *p) {
  MY_DISK_IMAGE *image = p;
  return (image->headers[0].db_version == MY_READER.unique_id);
}

static off_t expected_size(void *p) {
  MY_DISK_IMAGE *image = p;
  return image_size(&image->headers[0]);
}

static int good_image(const MY_DISK_IMAGE *image) {
  return image->headers[0].db_id      == OSBF_DB_ID &&
         image->headers[0].db_version == MY_READER.unique_id &&
         image->headers[0].db_flags   == 0;
}

static void *find_header (void *p, CLASS_STRUCT *class, OSBF_HANDLER *h) {
  MY_DISK_IMAGE *image = p;
  if (!good_image(p))
    osbf_raise(h, "Bad internal invariants for image:\n"
                  "  expected id %d (found %d)\n"
                  "  expected version %d (found %d)\n"
                  "  expected flags 0 (found %d)\n",
               OSBF_DB_ID, image->headers[0].db_id,
               MY_READER.unique_id, image->headers[0].db_version,
               image->headers[0].db_flags);
  (void)class; /* not used */
  return p;
}

static void *find_buckets (void *p, CLASS_STRUCT *class, OSBF_HANDLER *h) {
  MY_DISK_IMAGE *image = p;
  if (!good_image(p))
    osbf_raise(h, "This can't happen: bad image not detected earlier");
  (void)class; /* not used */
  return &image->headers[1];
}

void osbf_native_write_class(CLASS_STRUCT *class, FILE *fp, OSBF_HANDLER *h) {
  char classname[200];
  strncpy(classname, class->classname, sizeof(classname));
  classname[sizeof(classname)-1] = '\0';
  
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
  if (image_size(class->header) != ftell(fp)) {
    long size = image_size(class->header);
    cleanup_partial_class(class->header, class, 1);
    osbf_raise(h, "Wrote %ld bytes to file %s; expected to write %ld bytes", 
               ftell(fp), classname, size);
  }
}

void osbf_native_write_header(CLASS_STRUCT *class, FILE *fp, OSBF_HANDLER *h) {
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
osbf_create_cfcfile (const char *cfcfile, uint32_t num_buckets,
		     uint32_t db_id, enum db_version db_version, uint32_t db_flags,
                     OSBF_HANDLER *h)
{
  FILE *f;
  uint32_t i_aux;
  MY_DISK_IMAGE image;
  OSBF_BUCKET_STRUCT bucket = { 0, 0, 0 };
  
  f = create_file_if_absent(cfcfile, h);

  /* zero all fields in header and buckets */
  memset(&image, 0, sizeof(image));

  /* Set the header. */
  image.headers[0].db_id      = db_id;
  image.headers[0].db_version = (uint32_t) db_version;
  image.headers[0].db_flags   = db_flags;
  image.headers[0].num_buckets   = num_buckets;

  /* Write header */
  osbf_raise_unless (fwrite (&image, sizeof (image), 1, f) == 1, h,
                     "Couldn't write the file header: '%s'", cfcfile);

  /*  Initialize CFC hashes - zero all buckets */
  for (i_aux = 0; i_aux < num_buckets; i_aux++) {
    osbf_raise_unless(fwrite (&bucket, sizeof (bucket), 1, f) == 1, h,
                      "Couldn't write to: '%s'", cfcfile);
  }
  osbf_raise_unless(ftell(f) == image_size(&image.headers[0]), h,
                    "Internal fault: bad size calculation");
  fclose (f);
}

void osbf_native_header_of_universal(OSBF_HEADER_STRUCT *dst,
                                     const OSBF_UNIVERSAL_HEADER *src) {
  dst->db_version      = src->db_version;
  dst->db_id           = src->db_id;
  dst->db_flags        = src->db_flags;
  dst->num_buckets     = src->num_buckets;
  dst->learnings       = src->learnings;
  dst->false_negatives = src->false_negatives;
  dst->false_positives = src->false_positives;
  dst->classifications = src->classifications;
  dst->extra_learnings = src->extra_learnings;
} 
