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

static FILE *create_file_if_absent(const char *filename, char *err_buf);
  /* opens filename for binary write, provided file does not already exist.
     Returns open file descriptor or NULL on any error.  Error message
     is written to *err_buf. */

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

int
osbf_create_cfcfile (const char *cfcfile, uint32_t num_buckets,
		     uint32_t db_id, enum db_version db_version, uint32_t db_flags,
                     char *err_buf)
{
  FILE *f;
  uint32_t i_aux;
  OSBF_DISK_IMAGE image;
  OSBF_BUCKET_STRUCT bucket = { 0, 0, 0 };
  
  f = create_file_if_absent(cfcfile, err_buf);
  if (f == NULL) return -1;

  /* zero all fields in header and buckets */
  memset(&image, 0, sizeof(image));

  /* Set the header. */
  image.headers[0].db_id      = db_id;
  image.headers[0].db_version = (uint32_t) db_version;
  image.headers[0].db_flags   = db_flags;
  image.headers[0].num_buckets   = num_buckets;

  /* Write header */
  CHECKF (fwrite (&image, sizeof (image), 1, f) == 1, -1, 
          "Couldn't write the file header: '%s'", cfcfile);

  /*  Initialize CFC hashes - zero all buckets */
  for (i_aux = 0; i_aux < num_buckets; i_aux++) {
    CHECKF (fwrite (&bucket, sizeof (bucket), 1, f) == 1, -1,
            "Couldn't write to: '%s'", cfcfile);
  }
  CHECK(ftell(f) == image_size(&image.headers[0]), -2,
        "Internal fault: bad size calculation");
  fclose (f);
  return 0;
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

static int set_header(OSBF_HEADER_STRUCT *header, void *image, char *err_buf);


/*****************************************************************/

int
osbf_open_class (const char *classname, int flags, CLASS_STRUCT * class,
		 char *err_buf)
{
  int prot;
  off_t fsize;
  OSBF_DISK_IMAGE *image;

  /* clear class structure */
  class->fd = -1;
  class->flags = O_RDONLY;
  class->classname = NULL;
  class->header = NULL;
  class->buckets = NULL;
  class->bflags = NULL;

  fsize = check_file (classname);
  CHECKF(fsize >= 0, -1, "Couldn't open the file %s.", classname);

  /* open the class to be trained and mmap it into memory */
  class->fd = open (classname, flags);
  CHECKF(class->fd >= 0, -1, "Couldn't open the file %s.", classname);

  if (flags == O_RDWR)
    {
      class->flags = O_RDWR;
      prot = PROT_READ + PROT_WRITE;

      if (USE_LOCKING) {
        if (osbf_lock_file (class->fd, 0, 0) != 0) {
	  fprintf (stderr, "Couldn't lock the file %s.", classname);
	  close (class->fd);
	  snprintf (err_buf, OSBF_ERROR_MESSAGE_LEN,
		    "Couldn't lock the file %s.", classname);
	  return -3;
	}
      }
    }
  else
    {
      class->flags = O_RDONLY;
      prot = PROT_READ;
    }

  image = (OSBF_DISK_IMAGE *) mmap (NULL, fsize, prot, MAP_SHARED, class->fd, 0);
  CHECKF(image != MAP_FAILED, -4,
         (close(class->fd), "Couldn't mmap %s."), classname);
 
  if (image->headers[0].db_version == OSBF_DB_FP_FN_VERSION) {
    /* check db id and version */
    CHECKF(good_image(image), -5,
           "%s is not an OSBF_Bayes-spectrum file with false positives and negatives.",
            classname);

    class->header = &image->headers[0];
    class->mmapped = 1;

    CHECK(image_size(class->header) == fsize, -7,
          "Internally inconsistent size calculation");

    class->bflags = calloc (class->header->num_buckets, sizeof (unsigned char));
    if (!class->bflags) {
      close (class->fd);
      munmap (image, fsize);
      CHECK(0, -6, "Couldn't allocate memory for seen features array.");
    }

    class->classname = classname;
    class->buckets = image_buckets(image);
    CHECK(class->buckets, -10, "This can't happen: failed to find buckets in image");
  } else {
    uint32_t version = image->headers[0].db_version;
#define CLEANUP close(class->fd), munmap(image, fsize)
    CHECKF(version < NELEMS(can_cvt) && can_cvt[version],
           (CLEANUP, -1),
           "Cannot read %s database format",
           version < NELEMS(db_version_names)
             ? db_version_names[version]
             : "unknown (version number out of range)");

    { char *c = malloc(strlen(classname)+1);
      CHECK(c != NULL, -10, "Could not allocate memory for class name");
      strcpy(c, classname);
      class->classname = c;
    }

    class->header = malloc(sizeof(*class->header));
    CHECK(class->header != NULL, -7, "Could not allocate memory for header");
    CHECK(set_header(class->header, image, err_buf), -8, err_buf);

    class->buckets = malloc(class->header->num_buckets * sizeof(*class->buckets));
    CHECK(class->buckets != NULL, -8, "Could not allocate memory for buckets");
    {
      OSBF_BUCKET_STRUCT *ibuckets = image_buckets(image);
      CHECK(ibuckets != NULL, -9, "This can't happen: failed find buckets to convert");
      memcpy(class->buckets, ibuckets, class->header->num_buckets * sizeof(*ibuckets));
      CLEANUP;
      class->mmapped = 0;
      class->fd = -1;
    }

    class->bflags = calloc (class->header->num_buckets, sizeof (unsigned char));
    if (!class->bflags) {
      free(class->header);
      free(class->buckets);
      class->header = NULL;
      class->buckets = NULL;
      CHECK(0, -6, "Couldn't allocate memory for seen features array.");
    }

  }
  return 0;
}
#undef CLEANUP


/*****************************************************************/

int
osbf_close_class (CLASS_STRUCT * class, char *err_buf)
{
  int err = 0;

  if (class->header) {
    if (class->mmapped) {
      munmap (class->header, image_size(class->header));
      class->header = NULL;
      class->buckets = NULL;
    } else {
#define CLEANUP free(class->header), free(class->buckets)
      FILE *fp = fopen(class->classname, "wb");
      CHECKF(fp != NULL, (CLEANUP, -1),
             "Could not open class file %s for writing", class->classname);
      CHECKF(fwrite(class->header, sizeof(*class->header), 1, fp) == 1,
             (CLEANUP, -1),
             "Could not write header to class file %s", class->classname);
      CHECKF(fwrite(class->buckets, sizeof(*class->buckets),
                    class->header->num_buckets, fp) == class->header->num_buckets,
             (CLEANUP, remove(class->classname), -1), /* salvage is impossible */
             "Could not write buckets to class file %s", class->classname);
      CLEANUP;
#undef CLEANUP
    }
  }

  if (class->bflags) {
    free (class->bflags);
    class->bflags = NULL;
  }

  if (class->fd >= 0) {
      if (class->flags == O_RDWR)
	{
          /* XXX what does this do exactly? why not use utime(2)? */
	  /* "touch" the file */
	  OSBF_HEADER_STRUCT foo;
	  read (class->fd, &foo, sizeof (foo));
	  lseek (class->fd, 0, SEEK_SET);
	  write (class->fd, &foo, sizeof (foo));

          if (USE_LOCKING) {
            if (osbf_unlock_file (class->fd, 0, 0) != 0)
              {
                snprintf (err_buf, OSBF_ERROR_MESSAGE_LEN,
                          "Couldn't unlock file: %s", class->classname);
                err = -1;
              }
          }
	}
      close (class->fd);
      class->fd = -1;
    }

  return err;
}

/*****************************************************************/

int
osbf_lock_file (int fd, uint32_t start, uint32_t len)
{
  struct flock fl;
  int max_lock_attempts = 20;
  int errsv = 0;

  fl.l_type = F_WRLCK;		/* write lock */
  fl.l_whence = SEEK_SET;
  fl.l_start = start;
  fl.l_len = len;

  while (max_lock_attempts > 0)
    {
      errsv = 0;
      if (fcntl (fd, F_SETLK, &fl) < 0)
	{
	  errsv = errno;
	  if (errsv == EAGAIN || errsv == EACCES)
	    {
	      max_lock_attempts--;
	      sleep (1);
	    }
	  else
	    break;
	}
      else
	break;
    }
  return errsv;
}

/*****************************************************************/

int
osbf_unlock_file (int fd, uint32_t start, uint32_t len)
{
  struct flock fl;

  fl.l_type = F_UNLCK;
  fl.l_whence = SEEK_SET;
  fl.l_start = start;
  fl.l_len = len;
  if (fcntl (fd, F_SETLK, &fl) == -1)
    return -1;
  else
    return 0;
}


/*****************************************************************/

/* XXX why doesn't this use osbf_open_class and osbf_close_class? */

int
osbf_dump (const char *cfcfile, const char *csvfile, char *err_buf)
{
  FILE *fp_cfc, *fp_csv;
  OSBF_DISK_IMAGE image;
  OSBF_BUCKET_STRUCT buckets[5000];
  int32_t buckets_read;

  fp_cfc = fopen (cfcfile, "rb");
  CHECKF(fp_cfc != NULL, -1, "Can't open cfc file %s", cfcfile);
  CHECKF(fread(&image, sizeof(image), 1, fp_cfc) == 1, -1,
         "Error reading cfc file %s", cfcfile);
  fp_csv = fopen (csvfile, "w");
  CHECKF(fp_csv != NULL, -1, (fclose(fp_cfc), "Can't open csv file %s"), csvfile);

  fprintf(fp_csv,
          "%" SCNu32 ";%" SCNu32 "\n%" SCNu32 ";%" SCNu32 "\n",
          image.headers[0].db_id, image.headers[0].db_flags,
          image.headers[0].num_buckets, image.headers[0].learnings);

  do { 
    int i;
    buckets_read = fread (buckets, sizeof (*buckets), NELEMS(buckets), fp_cfc);
    for (i = 0; i < buckets_read; i++)
      fprintf (fp_csv, "%" PRIu32 ";%" PRIu32 ";%" PRIu32 "\n",
               buckets[i].hash, buckets[i].key, buckets[i].value);
  } while (buckets_read > 0);
  fclose (fp_cfc);
  fclose (fp_csv);
  return 0;
}

/*****************************************************************/

static int read_bucket(OSBF_BUCKET_STRUCT *bucket, FILE *fp) {
  return 3 == fscanf (fp, "%" SCNu32 ";%" SCNu32 ";%" SCNu32 "\n",
                      &bucket->hash, &bucket->key, &bucket->value);
}

/* XXX if you ask me this should all be replaced with conversion to/from Lua */

int
osbf_restore (const char *cfcfile, const char *csvfile, char *err_buf)
{
  FILE *fp_cfc, *fp_csv;
  OSBF_DISK_IMAGE image;
  OSBF_BUCKET_STRUCT bucket;
  uint32_t i;

  /* CHECK(check_file(cfcfile) < 0, 1, "The .cfc file already exists!") */

  fp_csv = fopen (csvfile, "r");
  CHECKF(fp_csv != NULL, 1, "Cannot open csv file %s", csvfile);
  /* read header */
  memset(&image, 0, sizeof(image));
  CHECK(4 ==
	  fscanf (fp_csv,
		  "%" SCNu32 ";%" SCNu32 "\n%" SCNu32 ";%" SCNu32 "\n",
                  &image.headers[0].db_id, &image.headers[0].db_flags,
		  &image.headers[0].num_buckets, &image.headers[0].learnings),
        1,
        (fclose (fp_csv), remove (cfcfile), "csv file doesn't have a valid header"));

  fp_cfc = fopen (cfcfile, "wb");
  CHECKF(fp_cfc != NULL, 1, (fclose(fp_csv), "could not open %s for write"), cfcfile);
  CHECK(read_bucket(&bucket, fp_csv), 1,
           (fclose(fp_csv), fclose(fp_cfc), remove(cfcfile), "Problem reading csv"));
  CHECK(1 == fwrite(&image, sizeof(image), 1, fp_cfc), 1,
           (fclose(fp_csv), fclose(fp_cfc), remove(cfcfile), "Problem writing cfc"));
  for (i = 0; i <= image.headers[0].num_buckets; i++) {
    CHECK(read_bucket(&bucket, fp_csv), 1,
           (fclose(fp_csv), fclose(fp_cfc), remove(cfcfile), "Problem reading csv"));
    CHECK(1 == fwrite(&bucket, sizeof(bucket), 1, fp_cfc), 1,
           (fclose(fp_csv), fclose(fp_cfc), remove(cfcfile), "Problem writing cfc"));
  }
  CHECK(feof(fp_csv), 1,
        (fclose(fp_csv), fclose(fp_cfc), remove(cfcfile),
         "Leftover text at end of csv file"));

  return 0;
}

/*****************************************************************/

int
osbf_stats (const char *cfcfile, STATS_STRUCT * stats,
	    char *err_buf, int verbose)
{

  uint32_t i = 0;

  uint32_t used_buckets = 0, unreachable = 0;
  uint32_t max_chain = 0, num_chains = 0;
  uint32_t max_value = 0, first_chain_len = 0;
  uint32_t max_displacement = 0, chain_len_sum = 0;

  uint32_t chain_len = 0, value;

  CLASS_STRUCT class;
  OSBF_BUCKET_STRUCT *buckets;

  CHECK(osbf_open_class(cfcfile, O_RDONLY, &class, err_buf) == 0, 1, err_buf);

  if (verbose == 1) {
    buckets = class.buckets;
    for (i = 0; i <= class.header->num_buckets; i++) {
      if ((value = buckets[i].value) != 0) {
        uint32_t distance, right_position;
        uint32_t real_position, rp;

        used_buckets++;
        chain_len++;
        if (value > max_value)
          max_value = value;

        /* calculate max displacement */
        right_position = buckets[i].hash % class.header->num_buckets;
	real_position = i;
	if (right_position <= real_position)
	  distance = real_position - right_position;
	else
	  distance = class.header->num_buckets + real_position -
	    right_position;
	if (distance > max_displacement)
	  max_displacement = distance;

	/* check if the bucket is unreachable */
	for (rp = right_position; rp != real_position; rp++)
	  {
	    if (rp >= class.header->num_buckets)
	      {
	        rp = 0;
	        if (rp == real_position)
	          break;
	      }
	    if (buckets[rp].value == 0)
	      break;
	  }
	if (rp != real_position)
	  {
	    unreachable++;
	  }
	
	if (chain_len > 0)
	  {
	    if (chain_len > max_chain)
	      max_chain = chain_len;
	    chain_len_sum += chain_len;
	    num_chains++;
	    chain_len = 0;
	    /* check if the first chain starts */
	    /* at the the first bucket */
	    if (i == 0 && num_chains == 1 && buckets[0].value != 0)
	      first_chain_len = chain_len;
          }

      }
    }
    
    /* check if last and first chains are the same */
    /* not sure this makes sense any longer XXX */
    if (chain_len > 0)
      {
        if (first_chain_len == 0)
          num_chains++;
        else
          chain_len += first_chain_len;
        chain_len_sum += chain_len;
        if (chain_len > max_chain)
          max_chain = chain_len;
      }
  }

  stats->db_id = class.header->db_id;
  stats->db_version = class.header->db_version;
  stats->db_flags = class.header->db_flags;
  stats->total_buckets = class.header->num_buckets;
  stats->bucket_size = sizeof(*class.buckets);
  stats->header_size = sizeof(class.header);
  stats->learnings = class.header->learnings;
  stats->extra_learnings = class.header->extra_learnings;
  stats->false_negatives = class.header->false_negatives;
  stats->false_positives = class.header->false_positives;
  stats->classifications = class.header->classifications;
  if (verbose == 1)
    {
      stats->used_buckets = used_buckets;
      stats->num_chains = num_chains;
      stats->max_chain = max_chain;
      if (num_chains > 0)
        stats->avg_chain = (double) chain_len_sum / num_chains;
      else
        stats->avg_chain = 0;
      stats->max_displacement = max_displacement;
      stats->unreachable = unreachable;
    }
  CHECK(osbf_close_class(&class, err_buf) == 0, 1, err_buf);
  return 0;
}

/*****************************************************************/

int
osbf_increment_false_positives (const char *database, int delta, char *err_buf)
{

  CLASS_STRUCT class;
  int error = 0;

  /* open the class and mmap it into memory */
  CHECK(osbf_open_class(database, O_RDWR, &class, err_buf) == 0, 1,
        (fprintf (stderr, "Couldn't open %s.", database), err_buf));

  /* add delta to false positive counter */
  if (delta >= 0 || class.header->false_positives >= (uint32_t) (-delta))
    class.header->false_positives += delta;

  CHECK(osbf_close_class(&class, err_buf) == 0, 1, err_buf);
  return error;
}

/*****************************************************************/

static FILE *create_file_if_absent(const char *filename, char *err_buf) {
  FILE *f;

  if (filename == NULL || *filename == '\0') {
      if (filename != NULL)
	snprintf (err_buf, OSBF_ERROR_MESSAGE_LEN,
		  "Invalid file name: '%s'", filename);
      else
	strncpy (err_buf, "Invalid (NULL) pointer to cfc file name",
		 OSBF_ERROR_MESSAGE_LEN);
      return NULL;
    }

  f = fopen (filename, "r");
  if (f) {
      snprintf (err_buf, OSBF_ERROR_MESSAGE_LEN,
		"File already exists: '%s'", filename);
      fclose(f);
      return NULL;
  }

  f = fopen (filename, "wb");
  if (!f) {
      snprintf (err_buf, OSBF_ERROR_MESSAGE_LEN,
		"Couldn't create the file: '%s'", filename);
      return NULL;
  }
  return f;
}

/*****************************************************************/


/* Check if a file exists. Return its length if yes and < 0 if no */
off_t
check_file (const char *file)
{
  int fd;
  off_t fsize;

  fd = open (file, O_RDONLY);
  if (fd < 0)
    return -1;
  fsize = lseek (fd, 0L, SEEK_END);
  if (fsize < 0)
    return -2;
  close (fd);

  return fsize;
}

/*****************************************************************/

static int set_header(OSBF_HEADER_STRUCT *header, void *image, char *err_buf) {
  OSBF_HEADER_STRUCT_2007_11 *oheader = image;
  CHECKF(oheader->version == OSBF_DB_2007_11_VERSION, 0,
         "Tried to convert a version other than %d", OSBF_DB_2007_11_VERSION);
  memset(header, 0, sizeof(*header));
  header->db_version	= OSBF_CURRENT_VERSION;
  header->db_id 	= OSBF_DB_ID;
  header->db_flags	= oheader->db_flags;
  header->num_buckets	= oheader->num_buckets;
  header->learnings	= oheader->learnings;
  header->false_negatives = oheader->mistakes;
  header->false_positives = 0;  /* information not easily available */
  header->classifications = oheader->classifications;
  header->extra_learnings = oheader->extra_learnings;
  return 1;
}


