/*
 *  osbfcvt.h 
 * 
 * This file defines data structures and functions that enable OSBF 
 * to read legacy file formats.  The goal is that every format supported
 * from November 2007 onward will always be readable and convertible to the
 * preferred current format defined in osbflib.h.
 *
 * See Copyright Notice in osbflib.h
 */

#ifndef OSBF_CVT_H
#define OSBF_CVT_H 1

#include "osbflib.h"

/* the key idea is to use 'universal' data structures which have the following 
   property:
     1. Any format can be read into a universal representation with no loss
        of information, although some fields in the universal rep may be filled
        in with default or nonsense values.

     2. The universal rep can always be downconverted into the preferred native rep
*/

typedef OSBF_BUCKET_STRUCT OSBF_UNIVERSAL_BUCKET;
typedef struct osbf_uni_header {
  uint32_t db_version;		/* database version as it was on disk */
  uint32_t db_id;		/* database identification -- which is what, exactly?*/
  uint32_t db_flags;		/* for future use */
  uint32_t num_buckets;		/* number of buckets in the file */
  uint32_t buckets_start;       /* where the buckets start */
  uint32_t learnings;		/* number of trainings done */
  uint32_t false_negatives;	/* number of false not classifications as this class */
  uint32_t false_positives;	/* number of false classifications as this class */
  uint64_t classifications;	/* number of classifications */
  uint32_t extra_learnings;	/* number of extra trainings done */
} OSBF_UNIVERSAL_HEADER;

void osbf_native_header_of_universal(OSBF_HEADER_STRUCT *dst,
                                     const OSBF_UNIVERSAL_HEADER *src);
  /* initialize a native header from the fields of a universal header */


typedef unsigned (*osbf_bucket_upconverter)(OSBF_UNIVERSAL_BUCKET *dst, void *src);
  /* take a single bucket in any format and upconvert it to the universal
     format */

void osbf_native_buckets_of_universal(OSBF_BUCKET_STRUCT *dst,
                                      const void *src,
                                      osbf_bucket_upconverter cvt,
                                      unsigned num_buckets);
  /* Initialize a native array of buckets from a pointer an array of non-native
     buckets.  The upconverter writes a universal bucket from a non-native bucket,
     then returns the size in bytes of the non-native bucket.
     Nobody will call this function until the bucket format changes */

/* Database version */
enum osbf_database_ids {  
  OSBF_DB_ID = 5 /* Obsolete ID related to CRM 114 */
};

#endif

