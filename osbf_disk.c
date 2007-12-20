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
#include "osbf_disk.h"

#define DEBUG 0

/* fail if two readers claim the same unique id or if the number
   of native readers is unacceptable */

static void check_reader_uniqueness(OSBF_HANDLER *h) {
  OSBF_READER **preader, **r;
  static int already_checked = 0;
  int native_readers = 0;
  if (already_checked) return;
  for (preader = osbf_image_readers; *preader; preader++)
    {
      OSBF_READER *reader = *preader;
      if (reader->native)
        native_readers++;
      for (r = preader + 1; *r; r++)
        if (reader->unique_id == (*r)->unique_id)
          osbf_raise(h, "OSBF is gravely misconfigured: multiple readers "
                     " share 'unique' id %d,\n  which they call '%s' and '%s'.",
                     (int)(*r)->unique_id, reader->name, (*r)->name);
    }
  if (native_readers < MIN_NATIVE_READERS)
    osbf_raise(h, "OSBF is misconfigured; it has only %d native readers but requires"
               " at least %d", native_readers, MIN_NATIVE_READERS);
  if (native_readers > MAX_NATIVE_READERS)
    osbf_raise(h, "OSBF is misconfigured; it has %d native readers but expects"
               " at most %d", native_readers, MAX_NATIVE_READERS);
  already_checked = 1;
}
                                   
#define USE_LOCKING 1







/*****************************************************************/

void
osbf_open_class (const char *classname, osbf_class_usage usage,
                 CLASS_STRUCT * class, OSBF_HANDLER *h)
{
  static int open_flags[] = { O_RDONLY, O_RDWR, O_RDWR };
     /* map useage to flags */
  static osbf_class_state states[] = 
    { OSBF_COPIED_R, OSBF_COPIED_RWH, OSBF_COPIED_RW };
    /* map usage to states (for non-native formats only); */
  int prot, mmap_flags;
  void *image;
  OSBF_READER **preader;
  int native = 0;

  check_reader_uniqueness(h);

  /* initialize class structure */
  class->fd = -1;
  class->usage = usage;
  class->classname = NULL;
  class->fmt_name  = "Unknown";
  class->header    = NULL;
  class->buckets   = NULL;
  class->bflags    = NULL;
  if ((unsigned) usage >= NELEMS(states))
    osbf_raise(h, "This can't happen: usage value %d out of range", (int)usage);
  class->state = states[(unsigned)usage];

  class->fsize = check_file (classname);
  osbf_raise_unless(class->fsize >= 0,
                    h, "File %s cannot be opened for read.", classname);

  /* open the class and mmap it into memory */
  
  osbf_raise_unless((unsigned)usage < NELEMS(open_flags), h,
                    "This can't happen: usage w/o flags");
  class->fd = open (classname, open_flags[(unsigned)usage]);
  osbf_raise_unless(class->fd >= 0, h,
                    "Couldn't open the file %s for read/write.", classname);

  class->classname = osbf_malloc(strlen(classname)+1, h, "class name");
  strcpy(class->classname, classname);

  if (usage != OSBF_READ_ONLY && USE_LOCKING) {
    if (osbf_lock_file (class->fd, 0, sizeof(*class->header)) != 0) {
      fprintf (stderr, "Couldn't lock the file %s.", classname);
      close (class->fd);
      free(class->classname);
      osbf_raise(h, "Couldn't lock the file %s.", classname);
    }
  }

  prot  = (usage == OSBF_READ_ONLY) ? PROT_READ : PROT_READ + PROT_WRITE;
  mmap_flags = prot & PROT_WRITE ? MAP_PRIVATE : MAP_SHARED;
  image = mmap (NULL, class->fsize, prot, MAP_PRIVATE, class->fd, 0);
  UNLESS_CLEANUP_RAISE(image != MAP_FAILED, (close(class->fd), free(class->classname)),
                       (h, "Couldn't mmap %s: %s.", classname, strerror(errno)));
 
  if (DEBUG) {
    unsigned j;
    fprintf(stderr, "Scanning image");
    for (j = 0; j < sizeof(*class->header) / sizeof(uint32_t); j++)
      fprintf(stderr, " %u", ((uint32_t *)image)[j]);
    fprintf(stderr, "\n");
  }

  for (preader = osbf_image_readers; *preader; preader++)
    {
      OSBF_READER *reader = *preader;
      if (reader->i_recognize_image(image)) {
        if (DEBUG)
          fprintf(stderr, "Recognized file %s as %s\n", classname, reader->longname);
        if (reader->expected_size(image) != class->fsize)
          osbf_raise(h, "This can't happen: "
                     "expected %d-byte image but size of file %s is %d bytes", 
                      (int) reader->expected_size(image), classname,
                     (int) class->fsize);
        class->fmt_name = reader->name;
        if (reader->native) {
          class->header  = reader->header.find(image, class, h);
          class->buckets = reader->buckets.find(image, class, h);
          class->state = OSBF_MAPPED;
        } else {
          class->header = osbf_malloc(sizeof(*class->header), h, "header");
          reader->header.copy(class->header, image, class, h);
          class->buckets =
            osbf_malloc(class->header->num_buckets * sizeof(*class->buckets),
                        h, "buckets");
          reader->buckets.copy(class->buckets, image, class, h);
          close(class->fd);
          class->fd = -1;
          munmap(image, class->fsize);
          class->fsize = 0;
        }
        native = reader->native;
        break;
      }
    }

  if (class->header == NULL)
    osbf_raise(h, "File %s is not in a format that OSBF understands\n", classname);

  class->bflags = calloc (class->header->num_buckets, sizeof (unsigned char));
  if (class->bflags == NULL) {
    if (!native) { free(class->header); free(class->buckets); }
    free(class->classname);
    class->header = NULL;
    class->buckets = NULL;
    class->classname = NULL;
    osbf_raise(h, "Couldn't allocate memory for seen features array.");
  }

  if (class->buckets == NULL || class->header == NULL || class->bflags == NULL)
    osbf_raise(h, "This can't happen: class not fully initialized");
}

void cleanup_partial_class(void *image, CLASS_STRUCT *class, int native) {
  if (class->classname) {
    free(class->classname);
    class->classname = NULL;
  }
  munmap(image, class->fsize);
  if (class->fd >= 0) {
    close(class->fd);
    class->fd = -1;
  }
  if (!native) {
    free (class->header);  /* OK to free(NULL) */
    free (class->buckets);
  }
  class->header = NULL;
  class->buckets = NULL;
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
      osbf_native_write_class(class, fp, h);
      break;
    case OSBF_COPIED_RWH:
      /* overwrite a new header onto the existing new file */
      fp = fopen(class->classname, "a+b");
      UNLESS_CLEANUP_RAISE(fp != NULL, CLEANUP,
             (h, "Could not open class file %s for read/write", class->classname));
      UNLESS_CLEANUP_RAISE(fseek(fp, 0, SEEK_SET) == 0, CLEANUP,
             (h, "Couldn't seek to start of class file"));
      class->header->db_version = OSBF_CURRENT_VERSION;  /* what we're writing now */
      osbf_native_write_header(class, fp, h);
      UNLESS_CLEANUP_RAISE(fseek(fp, 0, SEEK_END) == 0, CLEANUP,
                           (h, "Couldn't seek to end of class file"));
      UNLESS_CLEANUP_RAISE(osbf_native_image_size(class) == ftell(fp), CLEANUP,
          (h, "Image of file %s is %d bytes; expected to write %d bytes", 
           class->classname, (int) ftell(fp),
           (int) osbf_native_image_size(class)));
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

    if (DEBUG) {
      unsigned j;
      fprintf(stderr, "Writing image");
      for (j = 0; j < sizeof(*class->header) / sizeof(unsigned); j++)
        fprintf(stderr, " %u", ((unsigned *)class->header)[j]);
      fprintf(stderr, "\n");
    }

    switch (class->state) {
      case OSBF_CLOSED:
        osbf_raise(h, "This can't happen: close class with non-NULL header field");
        break;
      case OSBF_MAPPED:
        if (class->fsize != osbf_native_image_size(class))
          osbf_raise(h, "This can't happen: native-mapped class has the wrong size");
        if (class->usage != OSBF_READ_ONLY) {
          if (lseek(class->fd, 0, SEEK_SET) == (off_t)-1)
            osbf_raise(h, "This can't happen: failed to seek to beginning of file");
          write(class->fd, class->header, class->fsize);

          if (DEBUG) {
            unsigned j;
            fprintf(stderr, "Wrote MAPPED image");
            for (j = 0; j < sizeof(*class->header) / sizeof(unsigned); j++)
              fprintf(stderr, " %u", ((unsigned *)class->header)[j]);
            fprintf(stderr, "\n");
          }
        }

        munmap (class->header, class->fsize);
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
      int unlock_failed = 0;
      if (class->usage != OSBF_READ_ONLY)
	{
          touch_fd(class->fd); /* workaround for snarky NFS problems; see below */

          if (USE_LOCKING)
            unlock_failed = (osbf_unlock_file (class->fd, 0, 0) != 0);
	}
      close (class->fd);
      class->fd = -1;
      if (unlock_failed)
        osbf_raise(h, "Couldn't unlock file");
  }
}

/*****************************************************************/

/*****************************************************************/

extern FILE *create_file_if_absent(const char *filename, OSBF_HANDLER *h) {
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

/* This code works around an old problem in CRM114, for some unknown
   reason to me and to the other developers there, in some OSs and
   under some conditions (NFS was one of them IIRR) the timestamp of
   mmapped files didn't change after an update.  Read/write after
   unmapping seems to do the job on *any* OS.
*/

static void touch_fd(int fd) {
  uint32_t foo;
  lseek (fd, 0, SEEK_SET);
  read (fd, &foo, sizeof (foo));
  lseek (fd, 0, SEEK_SET);
  write (fd, &foo, sizeof (foo));
}



/****************************************************************/

/* when more readers are added, they should be added here as well */

extern OSBF_READER osbf_reader_5, osbf_reader_6, osbf_reader_7;

OSBF_READER *osbf_image_readers[] = {
  &osbf_reader_7,
  &osbf_reader_6,
  &osbf_reader_5,
  NULL
};
