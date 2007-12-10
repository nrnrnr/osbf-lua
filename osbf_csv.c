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

int
osbf_dump (const char *cfcfile, const char *csvfile, char *err_buf)
{
  CLASS_STRUCT class;
  uint32_t i, num_buckets;
  OSBF_BUCKET_STRUCT *buckets;
  FILE *fp_csv;

  CHECK(osbf_open_class(cfcfile, OSBF_READ_ONLY, &class, err_buf) == 0, -1,
        err_buf);
  fp_csv = fopen (csvfile, "w");
  CHECKF(fp_csv != NULL, (osbf_close_class(&class, err_buf), -1),
         "Can't open csv file %s", csvfile);

  fprintf(fp_csv,
          "%" SCNu32 ";%" SCNu32 "\n%" SCNu32 ";%" SCNu32 "\n",
          class.header->db_id, class.header->db_flags,
          class.header->num_buckets, class.header->learnings);

  
  num_buckets = class.header->num_buckets;
  buckets = class.buckets;
  for (i = 0; i < num_buckets; i++)
    fprintf (fp_csv, "%" PRIu32 ";%" PRIu32 ";%" PRIu32 "\n",
               buckets[i].hash, buckets[i].key, buckets[i].value);
  fclose (fp_csv);
  CHECK(osbf_close_class(&class, err_buf) != -1, -1, err_buf);
  return 0;
}

static int read_bucket(OSBF_BUCKET_STRUCT *bucket, FILE *fp) {
  return 3 == fscanf (fp, "%" SCNu32 ";%" SCNu32 ";%" SCNu32 "\n",
                      &bucket->hash, &bucket->key, &bucket->value);
}

int
osbf_restore (const char *cfcfile, const char *csvfile, char *err_buf)
{
  FILE *fp_csv;
  CLASS_STRUCT class;
  OSBF_BUCKET_STRUCT *buckets;
  uint32_t i;

  memset(&class, 0, sizeof(class));
  class.classname = cfcfile;
  class.header = calloc(1, sizeof(*class.header));
  CHECK(class.header != NULL, -1, "Cannot allocate space for header");
  class.state = OSBF_COPIED_RW;
  class.bflags = NULL;
  class.usage = OSBF_WRITE_ALL;

  fp_csv = fopen (csvfile, "r");
  CHECKF(fp_csv != NULL, 1, "Cannot open csv file %s", csvfile);
  /* read header */
  CHECK(4 ==
	  fscanf (fp_csv,
		  "%" SCNu32 ";%" SCNu32 "\n%" SCNu32 ";%" SCNu32 "\n",
                  &class.header->db_id, &class.header->db_flags,
		  &class.header->num_buckets, &class.header->learnings),
        (fclose (fp_csv), 1),
        "csv file doesn't have a valid header");

  class.buckets = buckets = malloc(class.header->num_buckets * sizeof(*class.buckets));
  CHECK(buckets != NULL, (free(class.header), 1), "No space for buckets");
  for (i = 0; i <= class.header->num_buckets; i++) {
    CHECK(read_bucket(buckets+i, fp_csv), 
          (fclose(fp_csv), free(class.header), free(class.buckets), 1),
          "Problem reading csv");
  }
  CHECK(feof(fp_csv),
        (fclose(fp_csv), free(class.header), free(class.buckets), 1),
        "Leftover text at end of csv file");
  return osbf_close_class(&class, err_buf);
}

