/*
 *  osbf_csv.c 
 *
 *  The purpose of this module is to hide the human-readable layout
 *  of the CSV interchange format.
 *  
 *  See Copyright Notice in osbflib.h
 *
 */


#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "osbflib.h"
#include "osbfcvt.h"

void
osbf_dump (const CLASS_STRUCT *class, const char *csvfile, OSBF_HANDLER *h)
{
  uint32_t i, num_buckets;
  OSBF_BUCKET_STRUCT *buckets;
  FILE *fp_csv;

  if (class->state == OSBF_CLOSED)
    osbf_raise(h, "Cannot dump a closed class");
  fp_csv = fopen (csvfile, "w");
  if (fp_csv == NULL)
    osbf_raise(h, "Can't open csv file %s", csvfile);

  fprintf(fp_csv,
          "%" SCNu32 ";%" SCNu32 "\n%" SCNu32 ";%" SCNu32 "\n"
          "%" SCNu32 ";%" SCNu32 "\n"
          "%" SCNu64 ";%" SCNu32 "\n",
          class->header->db_version, 0,
          class->header->num_buckets, class->header->learnings,
          class->header->false_negatives, class->header->false_positives,
          class->header->classifications, class->header->extra_learnings);
  
  num_buckets = class->header->num_buckets;
  buckets = class->buckets;
  for (i = 0; i < num_buckets; i++)
    fprintf (fp_csv, "%" PRIu32 ";%" PRIu32 ";%" PRIu32 "\n",
               buckets[i].hash1, buckets[i].hash2, buckets[i].count);
  fclose (fp_csv);
}

static int read_bucket(OSBF_BUCKET_STRUCT *bucket, FILE *fp) {
  return 3 == fscanf (fp, "%" SCNu32 ";%" SCNu32 ";%" SCNu32 "\n",
                      &bucket->hash1, &bucket->hash2, &bucket->count);
}

void
osbf_restore (const char *cfcfile, const char *csvfile, OSBF_HANDLER *h)
{
  FILE *fp_csv;
  CLASS_STRUCT class;
  OSBF_BUCKET_STRUCT *buckets;
  uint32_t i;
  uint32_t garbage; /* placeholder for flags in legacy formats */
  OSBF_UNIVERSAL_HEADER uheader;

  memset(&class, 0, sizeof(class));
  memset(&uheader, 0, sizeof(uheader));
  class.classname = osbf_malloc(strlen(cfcfile)+1, h, "class name");
  strcpy(class.classname, cfcfile);
  class.state = OSBF_COPIED;
  class.bflags = NULL;
  class.fd = -1;
  class.usage = OSBF_WRITE_ALL;

  fp_csv = fopen (csvfile, "r");
  osbf_raise_unless(fp_csv != NULL, h, "Cannot open csv file %s", csvfile);
  /* read header */
  UNLESS_CLEANUP_RAISE(
     8 == fscanf (fp_csv,
		  "%" SCNu32 ";%" SCNu32 "\n%" SCNu32 ";%" SCNu32 "\n"
                  "%" SCNu32 ";%" SCNu32 "\n"
                  "%" SCNu64 ";%" SCNu32 "\n",
                  &uheader.db_version, &garbage,
		  &uheader.num_buckets, &uheader.learnings,
                  &uheader.false_negatives, &uheader.false_positives,
                  &uheader.classifications, &uheader.extra_learnings),
     fclose (fp_csv),
     (h, "csv file %s doesn't have a valid header", csvfile));

  class.buckets = buckets =
    osbf_malloc(uheader.num_buckets * sizeof(*class.buckets), h, "buckets");
  for (i = 0; i < uheader.num_buckets; i++) {
    UNLESS_CLEANUP_RAISE(read_bucket(buckets+i, fp_csv), 
          (fclose(fp_csv), free(class.buckets)),
          (h, "Problem reading csv file %s", csvfile));
  }
  class.header = osbf_calloc(1, sizeof(*class.header), h, "header");
  osbf_native_header_of_universal(class.header, &uheader);

  UNLESS_CLEANUP_RAISE(feof(fp_csv),
        (fclose(fp_csv), free(class.header), free(class.buckets)),
        (h, "Leftover text at end of csv file %s", csvfile));
  osbf_close_class(&class, h);
}

