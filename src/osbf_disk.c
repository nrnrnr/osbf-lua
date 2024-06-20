/*
 *  osbf_disk.c 
 *
 *  The purpose of this module is to hide the on-disk layout of the database.
 *  
 *  See Copyright Notice in osbflib.h
 *
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
#include "osbf_lockfile.h"

#define DEBUG 0
#define USE_LOCKING 1


/* fail if two formats claim the same unique id or if the number
   of native formats is unacceptable */

static void check_format_uniqueness(OSBF_HANDLER *h) {
  OSBF_FORMAT **pformat, **r;
  static int already_checked = 0;
  int native_formats = 0;
  if (already_checked) return;
  for (pformat = osbf_image_formats; *pformat; pformat++)
    {
      OSBF_FORMAT *format = *pformat;
      if (format->native)
        native_formats++;
      for (r = pformat + 1; *r; r++)
        if (format->unique_id == (*r)->unique_id)
          osbf_raise(h, "OSBF is gravely misconfigured: multiple formats "
                     " share 'unique' id %d,\n  which they call '%s' and '%s'.",
                     (int)(*r)->unique_id, format->name, (*r)->name);
    }
  if (native_formats < MIN_NATIVE_FORMATS)
    osbf_raise(h, "OSBF is misconfigured; it has only %d native formats but requires"
               " at least %d", native_formats, MIN_NATIVE_FORMATS);
  if (native_formats > MAX_NATIVE_FORMATS)
    osbf_raise(h, "OSBF is misconfigured; it has %d native formats but expects"
               " at most %d", native_formats, MAX_NATIVE_FORMATS);
  already_checked = 1;
}
                                   


/*****************************************************************/

void
osbf_open_class(const char *classname, osbf_class_usage usage,
                CLASS_STRUCT * class, OSBF_HANDLER *h)
{
  static int open_flags[] = { O_RDONLY, O_RDWR, O_RDWR }; /* map usage to flags */
  int prot, mmap_flags;
  void *image;
  OSBF_FORMAT **pformat;
  int native = 0;

  check_format_uniqueness(h);

  /* initialize class structure */
  class->fd = -1;
  class->usage = usage;
  class->classname = NULL;
  class->fmt_name  = "Unknown";
  class->header    = NULL;
  class->buckets   = NULL;
  class->bflags    = NULL;
  class->state     = OSBF_COPIED;
                         /* the default unless overwritten by a native format */

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

  if ((usage != OSBF_READ_ONLY) && USE_LOCKING) {
    /* if (osbf_lock_file (class->fd, 0, sizeof(*class->header)) != 0) { */
    if (osbf_lock_class (class, 0, sizeof(*class->header)) != 0) {
      close (class->fd);
      class->fd = -1;
      free(class->classname);
      class->classname = NULL;
      osbf_raise(h, "Couldn't lock the file %s.", classname);
    }
  }

  prot  = (usage == OSBF_READ_ONLY) ? PROT_READ : PROT_READ + PROT_WRITE;
  mmap_flags = prot & PROT_WRITE ? MAP_PRIVATE : MAP_SHARED;
  (void) mmap_flags; // not sure why unused
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

  for (pformat = osbf_image_formats; *pformat; pformat++)
    {
      OSBF_FORMAT *format = *pformat;
      if (format->i_recognize_image(image)) {
        if (DEBUG)
          fprintf(stderr, "Recognized file %s as %s (uid %d: %s)\n",
                  classname, format->name, format->unique_id, format->longname);
        if (format->expected_size(image) != class->fsize)
          osbf_raise(h, "This can't happen: "
                     "expected %d-byte image but size of file %s is %d bytes", 
                      (int) format->expected_size(image), classname,
                     (int) class->fsize);
        class->fmt_name = format->name;
        if (format->native) {
          class->header  = format->header.find(image, class, h);
          class->buckets = format->buckets.find(image, class, h);
          class->state = OSBF_MAPPED;
        } else {
          class->header = osbf_malloc(sizeof(*class->header), h, "header");
          format->header.copy(class->header, image, class, h);
          class->buckets =
            osbf_malloc(class->header->num_buckets * sizeof(*class->buckets),
                        h, "buckets");
          format->buckets.copy(class->buckets, image, class, h);
          close(class->fd);
          class->fd = -1;
          munmap(image, class->fsize);
          class->fsize = 0;
        }
        native = format->native;
        break;
      }
    }

  if (class->header == NULL)
    osbf_raise(h, "File %s is not in a format that OSBF understands\n", classname);

  class->bflags = malloc (class->header->num_buckets * sizeof (unsigned char));
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
     them and set to NULL (even on error).  May be called only
     if (class->state == OSBF_COPIED).
     */

static void flush_if_needed(CLASS_STRUCT * class, OSBF_HANDLER *h) {
  FILE *fp;

  /* if a new version and we are writing, write everything */
  if (class->usage != OSBF_READ_ONLY &&
      class->header->db_version != OSBF_CURRENT_VERSION)
    class->usage = OSBF_WRITE_ALL;

#define CLEANUP \
  (free(class->header), free(class->buckets), \
   class->header = NULL, class->buckets = NULL) 

  switch (class->usage) {
    case OSBF_READ_ONLY:
      break;  /* read-only; disk is good */
    case OSBF_WRITE_ALL: 
      /* write a complete new file */
      fp = fopen(class->classname, "wb");
      UNLESS_CLEANUP_RAISE(fp != NULL, CLEANUP,
             (h, "Could not open class file %s for writing", class->classname));
      class->header->db_version = OSBF_CURRENT_VERSION;  /* what we're writing now */
      osbf_native_write_class(class, fp, h);
      break;
    case OSBF_WRITE_HEADER:
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
      osbf_raise(h, "This can't happen: bad class usage in flush_if_needed()");
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

        munmap ((void *)class->header, class->fsize);
          /* cast should be redundant but on solaris it is not */
        break;
      case OSBF_COPIED:
        flush_if_needed(class, h);
        /* deliberate memory leak; class->classname is lost on error here */
        break;
    }
    class->header = NULL;
    class->buckets = NULL;
    class->state = OSBF_CLOSED;
  }

  if (class->fd >= 0) {
      int unlock_failed = 0;
      if (class->usage != OSBF_READ_ONLY)
	{
          touch_fd(class->fd); /* workaround for snarky NFS problems; see below */

          if (USE_LOCKING) {
            /* unlock_failed = (osbf_unlock_file (class->fd, 0, 0) != 0); */
            unlock_failed = (osbf_unlock_class (class, 0, sizeof(*class->header)) != 0);
            if (unlock_failed)
              osbf_raise(h, "Couldn't unlock file");
          }
	}

      close (class->fd);
      class->fd = -1;
  }

  if (class->classname) {
    free(class->classname);
    class->classname = NULL;
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

/* when more formats are added, they should be added here as well */

extern OSBF_FORMAT osbf_format_5, osbf_format_6, osbf_format_7;

OSBF_FORMAT *osbf_image_formats[] = {
  &osbf_format_7,
  &osbf_format_6,
  &osbf_format_5,
  NULL
};
