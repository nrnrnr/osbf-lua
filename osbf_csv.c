/*
 *  osbf_csv.c 
 *
 *  The purpose of this module is to hide the human-readable layout
 *  of the CSV interchange format.
 *  
 *  This software is licensed to the public under the Free Software
 *  Foundation's GNU GPL, version 2.  You may obtain a copy of the
 *  GPL by visiting the Free Software Foundations web site at
 *  www.fsf.org, and a copy is included in this distribution.  
 *
 * Copyright 2005, 2006, 2007 Fidelis Assis, all rights reserved.
 * Copyright 2007 Norman Ramsey, all rights reserved.
 * Copyright 2005, 2006, 2007 Williams Yerazunis, all rights reserved.
 *
 * Read the HISTORY_AND_AGREEMENT for details.
 */


#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "osbflib.h"

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
          "%" SCNu32 ";%" SCNu32 "\n%" SCNu32 ";%" SCNu32 "\n",
          class->header->db_id, class->header->db_flags,
          class->header->num_buckets, class->header->learnings);

  
  num_buckets = class->header->num_buckets;
  buckets = class->buckets;
  for (i = 0; i < num_buckets; i++)
    fprintf (fp_csv, "%" PRIu32 ";%" PRIu32 ";%" PRIu32 "\n",
               buckets[i].hash, buckets[i].key, buckets[i].value);
  fclose (fp_csv);
}

static int read_bucket(OSBF_BUCKET_STRUCT *bucket, FILE *fp) {
  return 3 == fscanf (fp, "%" SCNu32 ";%" SCNu32 ";%" SCNu32 "\n",
                      &bucket->hash, &bucket->key, &bucket->value);
}

void
osbf_restore (const char *cfcfile, const char *csvfile, OSBF_HANDLER *h)
{
  FILE *fp_csv;
  CLASS_STRUCT class;
  OSBF_BUCKET_STRUCT *buckets;
  uint32_t i;

  memset(&class, 0, sizeof(class));
  class.classname = osbf_malloc(strlen(cfcfile)+1, h, "class name");
  strcpy(class.classname, cfcfile);
  class.header = osbf_calloc(1, sizeof(*class.header), h, "header");
  class.state = OSBF_COPIED_RW;
  class.bflags = NULL;
  class.usage = OSBF_WRITE_ALL;

  fp_csv = fopen (csvfile, "r");
  osbf_raise_unless(fp_csv != NULL, h, "Cannot open csv file %s", csvfile);
  /* read header */
  UNLESS_CLEANUP_RAISE(
     4 == fscanf (fp_csv,
		  "%" SCNu32 ";%" SCNu32 "\n%" SCNu32 ";%" SCNu32 "\n",
                  &class.header->db_id, &class.header->db_flags,
		  &class.header->num_buckets, &class.header->learnings),
     fclose (fp_csv),
     (h, "csv file %s doesn't have a valid header", csvfile));

  class.buckets = buckets =
    osbf_malloc(class.header->num_buckets * sizeof(*class.buckets), h, "buckets");
  for (i = 0; i <= class.header->num_buckets; i++) {
    UNLESS_CLEANUP_RAISE(read_bucket(buckets+i, fp_csv), 
          (fclose(fp_csv), free(class.header), free(class.buckets), 1),
          (h, "Problem reading csv file %s", csvfile));
  }
  UNLESS_CLEANUP_RAISE(feof(fp_csv),
        (fclose(fp_csv), free(class.header), free(class.buckets), 1),
        (h, "Leftover text at end of csv file %s", csvfile));
  osbf_close_class(&class, h);
}

