/*
 *  osbf_disk.c 
 *
 *  The purpose of this module is to hide the on-disk layout of the database.
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
#include <inttypes.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <errno.h>

#include "osbflib.h"

#define USE_LOCKING 1


typedef struct {
  OSBF_HEADER_STRUCT_2007_12 headers[1];
} OSBF_DISK_IMAGE_2007_12;

typedef OSBF_DISK_IMAGE_2007_12 OSBF_DISK_IMAGE;

static FILE *create_file_if_absent(const char *filename, OSBF_HANDLER *h);
  /* opens filename for binary write, provided file does not already exist.
     Returns open file descriptor; calls osbf_raise on any error. */

static long image_size(const OSBF_HEADER_STRUCT *header);
static int good_image(const OSBF_DISK_IMAGE *image);


static long image_size(const OSBF_HEADER_STRUCT *header) {
  return sizeof(OSBF_DISK_IMAGE) + header->num_buckets * sizeof(OSBF_BUCKET_STRUCT);
}

static int good_image(const OSBF_DISK_IMAGE *image) {
  return image->headers[0].db_id      == OSBF_DB_ID &&
         image->headers[0].db_version == OSBF_DB_FP_FN_VERSION &&
         image->headers[0].db_flags   == 0;
}

static OSBF_BUCKET_STRUCT *image_buckets(const OSBF_DISK_IMAGE *image) {
  switch (image->headers->db_version)
    {
    case OSBF_DB_FP_FN_VERSION:
      return (OSBF_BUCKET_STRUCT *) &image->headers[1];
    case OSBF_DB_2007_11_VERSION:
      { OSBF_HEADER_STRUCT_2007_11 *header = (OSBF_HEADER_STRUCT_2007_11 *) image;
        OSBF_BUCKET_STRUCT *buckets = (OSBF_BUCKET_STRUCT *) image;
        return buckets + header-> buckets_start;
      }
    default:
      return NULL;
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
  OSBF_DISK_IMAGE image;
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

/* Version names */
const char *db_version_names[] = {
  "OSBF-Basic",
  "Unknown",
  "Unknown",
  "Unknown",
  "OSBF-FP-FN with union header",
  "OSBF-old",
  "OSBF-FP-FN",
};

static int can_cvt [] = { 0, 0, 0, 0, 0, 1, 0 };
/* can convert from a previous version */

static void set_header(OSBF_HEADER_STRUCT *header, void *image, OSBF_HANDLER *h);


/*****************************************************************/

void
osbf_open_class (const char *classname, osbf_class_usage usage, CLASS_STRUCT * class, OSBF_HANDLER *h)
{
  static int open_flags[] = { O_RDONLY, O_RDWR, O_RDWR };
     /* map useage to flags */
  int prot;
  off_t fsize;
  OSBF_DISK_IMAGE *image;

  /* clear class structure */
  class->fd = -1;
  class->usage = usage;
  class->classname = NULL;
  class->header = NULL;
  class->buckets = NULL;
  class->bflags = NULL;

  fsize = check_file (classname);
  osbf_raise_unless(fsize >= 0, h, "File %s cannot be opened for read.", classname);

  /* open the class to be trained and mmap it into memory */
  
  osbf_raise_unless((unsigned)usage < NELEMS(open_flags), h,
                    "This can't happen: usage w/o flags");
  class->fd = open (classname, open_flags[(unsigned)usage]);
  osbf_raise_unless(class->fd >= 0, h,
                    "Couldn't open the file %s for read/write.", classname);

  class->classname = osbf_malloc(strlen(classname)+1, h, "class name");
  strcpy(class->classname, classname);

  if (usage != OSBF_READ_ONLY)
    {
      prot = PROT_READ + PROT_WRITE;

      if (USE_LOCKING) {
        if (osbf_lock_file (class->fd, 0, sizeof(*class->header)) != 0) {
	  fprintf (stderr, "Couldn't lock the file %s.", classname);
	  close (class->fd);
          free(class->classname);
          osbf_raise(h, "Couldn't lock the file %s.", classname);
	}
      }
    }
  else
    {
      prot = PROT_READ;
    }

  image = (OSBF_DISK_IMAGE *) mmap (NULL, fsize, prot, MAP_SHARED, class->fd, 0);
  UNLESS_CLEANUP_RAISE(image != MAP_FAILED, (close(class->fd), free(class->classname)),
                       (h, "Couldn't mmap %s: %s.", classname, strerror(errno)));
 
#define CLEANUP_MAP (close(class->fd), munmap(image, fsize))
#define CLEANUP (CLEANUP_MAP, free(class->classname))
 
  if (image->headers[0].db_version == OSBF_DB_FP_FN_VERSION) {
    /* check db id and version */
    osbf_raise_unless(good_image(image), h,
           "%s is not an OSBF_Bayes-spectrum file with false positives and negatives.",
            classname);

    class->header = &image->headers[0];
    class->state = OSBF_MAPPED;

    osbf_raise_unless(image_size(class->header) == fsize, h,
        "This can't happen: calculated %ld bytes but size of file %s is %ld bytes", 
        image_size(class->header), classname, fsize);

    class->buckets = image_buckets(image);
    osbf_raise_unless(class->buckets != NULL, h,
                      "This can't happen: failed to find buckets in image");
  } else {
    uint32_t version = image->headers[0].db_version;
    UNLESS_CLEANUP_RAISE(version < NELEMS(can_cvt) && can_cvt[version],
           CLEANUP,
           (h, "Cannot read %s database format",
           version < NELEMS(db_version_names)
             ? db_version_names[version]
             : "unknown (version number out of range)"));

    class->header = osbf_malloc(sizeof(*class->header), h, "header");
    set_header(class->header, image, h);

    class->buckets = osbf_malloc(class->header->num_buckets * sizeof(*class->buckets),
                                 h, "buckets");
    {
      static osbf_class_state states[] = 
        { OSBF_COPIED_R, OSBF_COPIED_RWH, OSBF_COPIED_RW };
          
      OSBF_BUCKET_STRUCT *ibuckets = image_buckets(image);
      memcpy(class->buckets, ibuckets, class->header->num_buckets * sizeof(*ibuckets));
      CLEANUP_MAP;
      osbf_raise_unless((unsigned)usage < NELEMS(states), h,
                        "This can't happen: usage value %u out of range",
                        (unsigned)usage);
      class->state = states[(unsigned)usage];
      class->fd = -1;
    }
  }
#undef CLEANUP_MAP
#undef CLEANUP

  class->bflags = calloc (class->header->num_buckets, sizeof (unsigned char));
  UNLESS_CLEANUP_RAISE (class->bflags != NULL,
      (free(class->header), free(class->buckets), free(class->classname),
       class->header = NULL, class->buckets = NULL),
                        (h, "Couldn't allocate memory for seen features array."));
}


/*****************************************************************/

static void flush_if_needed(CLASS_STRUCT * class, OSBF_HANDLER *h);
  /* flush header and buckets to disk if needed, then free 
     them and set to NULL (even on error). 
     */

static void flush_if_needed(CLASS_STRUCT * class, OSBF_HANDLER *h) {
  FILE *fp;

  /* if a new version and we are writing, write everything */
  if (class->state != OSBF_COPIED_R &&
      class->header->db_version != OSBF_CURRENT_VERSION)
    class->state = OSBF_COPIED_RW;

#define CLEANUP \
  (free(class->header), free(class->buckets), \
   class->header = NULL, class->buckets = NULL) 

  switch (class->state) {
    case OSBF_COPIED_R:
      break;  /* read-only; disk is good */
    case OSBF_COPIED_RW: 
      /* write a complete new file */
      fp = fopen(class->classname, "wb");
      UNLESS_CLEANUP_RAISE(fp != NULL, CLEANUP,
             (h, "Could not open class file %s for writing", class->classname));
      class->header->db_version = OSBF_CURRENT_VERSION;  /* what we're writing now */
      UNLESS_CLEANUP_RAISE(fwrite(class->header, sizeof(*class->header), 1, fp) == 1,
                           CLEANUP,
             (h, "Could not write header to class file %s", class->classname));
      UNLESS_CLEANUP_RAISE(fwrite(class->buckets, sizeof(*class->buckets),
                    class->header->num_buckets, fp) == class->header->num_buckets,
             (CLEANUP, remove(class->classname)), /* salvage is impossible */
             (h, "Could not write buckets to class file %s", class->classname));
      UNLESS_CLEANUP_RAISE(image_size(class->header) == ftell(fp), CLEANUP,
          (h, "Wrote %ld bytes to file %s; expected to write %ld bytes", 
           ftell(fp), class->classname, image_size(class->header)));
      break;
    case OSBF_COPIED_RWH:
      /* overwrite a new header onto the existing new file */
      fp = fopen(class->classname, "a+b");
      UNLESS_CLEANUP_RAISE(fp != NULL, CLEANUP,
             (h, "Could not open class file %s for read/write", class->classname));
      UNLESS_CLEANUP_RAISE(fseek(fp, 0, SEEK_SET) == 0, CLEANUP,
             (h, "Couldn't seek to start of class file"));
      class->header->db_version = OSBF_CURRENT_VERSION;  /* what we're writing now */
      UNLESS_CLEANUP_RAISE(fwrite(class->header, sizeof(*class->header), 1, fp) == 1,
                           CLEANUP,
             (h, "Could not write header to class file %s", class->classname));
      UNLESS_CLEANUP_RAISE(fseek(fp, 0, SEEK_END) == 0, CLEANUP,
                           (h, "Couldn't seek to end of class file"));
      UNLESS_CLEANUP_RAISE(image_size(class->header) == ftell(fp), CLEANUP,
          (h, "Image of file %s is %ld bytes; expected to write %ld bytes", 
           class->classname, ftell(fp), image_size(class->header)));
      break;
    default:
      CLEANUP;
      osbf_raise(h, "This can't happen: bad class state in flush_if_needed()");
      break;
    }
  CLEANUP;
#undef CLEANUP
}

static void touch_fd(int fd);

void
osbf_close_class (CLASS_STRUCT * class, OSBF_HANDLER *h)
{
  if (class->bflags) {
    free (class->bflags);
    class->bflags = NULL;
  }

  if (class->header) {
    switch (class->state) {
      case OSBF_CLOSED:
        osbf_raise(h, "This can't happen: close class with non-NULL header field");
        break;
      case OSBF_MAPPED:
        munmap (class->header, image_size(class->header));
        break;
      case OSBF_COPIED_R: case OSBF_COPIED_RW: case OSBF_COPIED_RWH:
        flush_if_needed(class, h);
        /* deliberate memory leak; class->classname is lost on error here */
        break;
    }
    class->header = NULL;
    class->buckets = NULL;
    class->state = OSBF_CLOSED;
  }

  if (class->classname) {
    free(class->classname);
    class->classname = NULL;
  }

  if (class->fd >= 0) {
      int unlock_succeeded = 1;
      if (class->usage != OSBF_READ_ONLY)
	{
          touch_fd(class->fd); /* workaround for snarky NFS problems; see below */

          if (USE_LOCKING)
            unlock_succeeded = (osbf_unlock_file (class->fd, 0, 0) == 0);
	}
      close (class->fd);
      class->fd = -1;
      osbf_raise_unless(unlock_succeeded, h, "Couldn't unlock file");
  }
}

/*****************************************************************/

/*****************************************************************/

static FILE *create_file_if_absent(const char *filename, OSBF_HANDLER *h) {
  FILE *f;

  osbf_raise_unless(filename != NULL, h, "Asked to create null pointer as file name");
  osbf_raise_unless(*filename != '\0', h, "Asked to create CFC file with empty name");

  f = fopen (filename, "r");
  UNLESS_CLEANUP_RAISE(f == NULL, fclose(f),
                       (h, "Cannot create file '%s'; it exists already", filename));

  f = fopen (filename, "wb");
  osbf_raise_unless(f != NULL, h, "Couldn't create the file: '%s'", filename);
  return f;
}

/*****************************************************************/

static void set_header(OSBF_HEADER_STRUCT *header, void *image, OSBF_HANDLER *h) {
  OSBF_HEADER_STRUCT_2007_11 *oheader = image;
  osbf_raise_unless(oheader->version == OSBF_DB_2007_11_VERSION, h,
         "Tried to convert a version other than %d", OSBF_DB_2007_11_VERSION);
  memset(header, 0, sizeof(*header));
  header->db_version	= oheader->version;
  header->db_id 	= OSBF_DB_ID;
  header->db_flags	= oheader->db_flags;
  header->num_buckets	= oheader->num_buckets;
  header->learnings	= oheader->learnings;
  header->false_negatives = oheader->mistakes;
  header->false_positives = 0;  /* information not easily available */
  header->classifications = oheader->classifications;
  header->extra_learnings = oheader->extra_learnings;
}

/*****************************************************************/

/* This code works around an old problem in CRM114, for some unknown
   reason to me and to the other developers there, in some OSs and
   under some conditions (NFS was one of them IIRR) the timestamp of
   mmapped files didn't change after an update.  Read/write after
   unmapping seems to do the job on *any* OS.
*/

static void touch_fd(int fd) {
  uint32_t foo;
  read (fd, &foo, sizeof (foo));
  lseek (fd, 0, SEEK_SET);
  write (fd, &foo, sizeof (foo));
}
