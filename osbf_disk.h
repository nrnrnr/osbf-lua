#ifndef OSBF_DISK_H
#define OSBF_DISK_H 1


#include <stdio.h>

#include "osbflib.h"


typedef struct osbf_reader {
  const uint32_t unique_id;    /* unique integer identifying the format */
  const char *name;            /* short, human-readable name of the format */
  const char *longname;        /* a longer, more explanatory name */
  const int native;            /* nonzero if image can be used directly */
  int (*i_recognize_image)(void *image);
                         /* given a pointer to an mmap'ed disk image,
                            returns nonzero if this image is recognized.
                            A nonzero return is a promise that the copy
                            functions will work. */
  off_t (*expected_size)(void *image);
                         /* the size the reader expects the image to be */
  union {
    void (*copy) (OSBF_HEADER_STRUCT *header, void *image, CLASS_STRUCT *class, OSBF_HANDLER *h);
    void *(*find) (void *image, CLASS_STRUCT *class, OSBF_HANDLER *h);
  } header;
  union {
    void (*copy)(OSBF_BUCKET_STRUCT *buckets, void *image, CLASS_STRUCT *class, OSBF_HANDLER *h);
    void *(*find) (void *image, CLASS_STRUCT *class, OSBF_HANDLER *h);
  } buckets;
} OSBF_READER;

extern void cleanup_partial_class(void *image, CLASS_STRUCT *class, int native);
  /* if anything goes wrong, unmaps image and frees any malloc'd memory */

/* native images are 'found'; non-native images are 'copied' */

#define MIN_NATIVE_READERS 1
#define MAX_NATIVE_READERS 1


extern OSBF_READER *osbf_image_readers[];
  /* array terminated by NULL pointer */

extern void  osbf_native_write_class (CLASS_STRUCT *class, FILE *fp, OSBF_HANDLER *h);
extern void  osbf_native_write_header(CLASS_STRUCT *class, FILE *fp, OSBF_HANDLER *h);
extern off_t osbf_native_image_size  (CLASS_STRUCT *class);

extern FILE *create_file_if_absent(const char *filename, OSBF_HANDLER *h);
  /* if file cannot be opened for read, attempt fopen(filename, "wb")
     and return the result or raise an error.  Result if returned is
     guaranteed non-NULL. */



#endif


#if 0
  void (*check_image)(void *image, OSBF_HANDLER *h);
                         /* internal consistency check; called on recognized images
                            before doing any copying */
#endif
