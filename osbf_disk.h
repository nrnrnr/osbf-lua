#ifndef OSBF_DISK_H
#define OSBF_DISK_H 1


#include <stdio.h>

#include "osbflib.h"

/* A 'format' provides the capability of reading a legacy database 
   and converting to the current native format.  Each format gets its
   own unique integer, which will normally be stored *somewhere* in
   the on-disk representation, although it is not a requirement.

   Unique identifiers 0 through 4 are reserved for non-OSBF
   classification methods implemented in CRM 114.  Unique ID 5
   identifies the format used in CRM 114 and in OSBF-Lua through
   version 2.0.4.   This format was a flexible format which kept space
   in the headers for the addition of new fields.  Unique ID 6
   identifies a transitional format.  Unique IDs 7 and above will be
   associated with formats whose on-disk representation begins with
   the letters OSBF.

   Formats come in two flavors: native and non-native.

     * A native format uses an on-disk representation that is
       identical to the in-memory representation of a class header.
       Native-format files can therefore be memory-mapped.
   
     * A non-native format uses an on-disk representation that is
       *not* identical to the in-memory representation of a class
       header.  Typically these are legacy formats or formats imported
       from another tool such as CRM 114.

   All formats have a name, a long name, and a unique identifier.
   In addition, every format provides a predicate called
   i_recognize_image, which is given a pointer to a disk image and
   returns nonzero if the disk image is in the given format.
   If i_recognize_image returns nonzero, the following additional
   functions may be called:

      expected_size  - Gives the expected size of the image, as a
                       sanity check.  If this is different from the
                       actual size, there is a bug somewhere.

   (For native formats only):

      header.find    - Is given a pointer to an image and returns a
                       pointer to the native header structure within
                       that image.

      buckets.find   - Is given a pointer to an image and returns a
                       pointer to the array of buckets within that image.

   (For non-native formats only):

      header.copy    - Is given a pointer to an empty header and a
                       pointer to an image.  Uses data from the image
                       to fill in as many fields of the empty header
                       as possible.

      buckets.copy   - Is given a pointer to available memory and a
                       pointer to an image.  Copies the array of
                       buckets from the image into the available memory.

*/

     
/* We want to make it easily to initialize formats statically, 
   and this means casting function types, so we name the types */

typedef void *(*osbf_find_header_fn)
                              (void *image, CLASS_STRUCT *class, OSBF_HANDLER *h);

typedef void *(*osbf_find_buckets_fn)
                              (void *image, CLASS_STRUCT *class, OSBF_HANDLER *h);

typedef void (*osbf_copy_header_fn)
  (OSBF_HEADER_STRUCT *header, void *image, CLASS_STRUCT *class, OSBF_HANDLER *h);

typedef void (*osbf_copy_buckets_fn)
  (OSBF_BUCKET_STRUCT *buckets, void *image, CLASS_STRUCT *class, OSBF_HANDLER *h);


typedef struct osbf_format {
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
                         /* the size the format expects the image to be */
  union {
    osbf_copy_header_fn copy;
    osbf_find_header_fn find;
  } header;
  union {
    osbf_copy_buckets_fn copy;
    osbf_find_buckets_fn find;
  } buckets;
} OSBF_FORMAT;

/* some macros to help with static initializers for the header and buckets unions */

#define OSBF_COPY_FUNCTIONS(h, b) { h }, { b }
#define OSBF_FIND_FUNCTIONS(h, b) \
   { (osbf_copy_header_fn)(h) }, { (osbf_copy_buckets_fn)(b) }



extern void cleanup_partial_class(void *image, CLASS_STRUCT *class, int native);
  /* if anything goes wrong, unmaps image and frees any malloc'd memory */

/* native images are 'found'; non-native images are 'copied' */

#define MIN_NATIVE_FORMATS 1
#define MAX_NATIVE_FORMATS 1


extern OSBF_FORMAT *osbf_image_formats[];
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
