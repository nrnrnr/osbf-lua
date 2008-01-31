/*
 *  osbf_aux.c 
 *  
 * See Copyright Notice in osbflua.h
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

#ifndef DEBUG_packchain
#define DEBUG_packchain 0
#endif

static void
osbf_packchain (CLASS_STRUCT * dbclass, uint32_t packstart, uint32_t packlen);

static uint32_t osbf_microgroom (CLASS_STRUCT * dbclass, uint32_t bindex);

static uint32_t osbf_last_in_chain  (CLASS_STRUCT * dbclass, uint32_t bindex);





#define BUCKET_BUFFER_SIZE 5000

uint32_t microgroom_displacement_trigger = OSBF_MICROGROOM_DISPLACEMENT_TRIGGER;
uint32_t microgroom_stop_after = OSBF_MICROGROOM_STOP_AFTER;

/*****************************************************************/

/*
 * Pack a chain moving buckets to a place closer to their
 * right positions whenever possible, using the buckets marked as free.
 * At the end, all buckets still marked as free are zeroed.
 */
static void
osbf_packchain(CLASS_STRUCT * class, uint32_t packstart, uint32_t packlen)
{
  uint32_t packend, ifrom, ito, free_start;
  uint32_t thash;

  packend = packstart + packlen;
  if (packend >= NUM_BUCKETS(class))
    packend -= NUM_BUCKETS(class);

  if (DEBUG_packchain) {
    uint32_t i, rp, d, h;
    fprintf(stderr, "Before packing\n");
    for (i = packstart; i != packend; i = NEXT_BUCKET(class, i)) {
      h = BUCKET_HASH(class, i);
      rp = HASH_INDEX(class, h);
      if (i >= rp)
        d = i - rp;
      else
        d = NUM_BUCKETS(class) + i - rp;
      fprintf(stderr, " i: %5" PRIu32 " d: %3" PRIu32 " value: %" PRIu32
              " h: %08X flags: %02X\n", i, d, BUCKET_VALUE(class, i),
              h, BUCKET_FLAGS(class, i));
    }
  }


  /* search the first marked-free bucket */
  for (free_start = packstart;
       free_start != packend; free_start = NEXT_BUCKET(class, free_start))
    if (MARKED_FREE(class, free_start))
      break;

  if (free_start != packend) {
    for (ifrom = NEXT_BUCKET(class, free_start);
         ifrom != packend; ifrom = NEXT_BUCKET(class, ifrom)) {
      if (!MARKED_FREE(class, ifrom)) {
        /* see if there's a free bucket closer to its right place */
        thash = BUCKET_HASH(class, ifrom);
        ito = HASH_INDEX(class, thash);

        while (ito != ifrom && !MARKED_FREE(class, ito))
          ito = NEXT_BUCKET(class, ito);

        /* if found a marked-free bucket, use it */
        if (MARKED_FREE(class, ito)) {
          /* copy bucket and flags */
          BUCKET_HASH(class, ito) = thash;
          BUCKET_KEY(class, ito) = BUCKET_KEY(class, ifrom);
          BUCKET_VALUE(class, ito) = BUCKET_VALUE(class, ifrom);
          BUCKET_FLAGS(class, ito) = BUCKET_FLAGS(class, ifrom);
          /* mark the from bucket as free */
          MARK_IT_FREE(class, ifrom);
        }
      }
    }
  }

  if (DEBUG_packchain) {
    uint32_t i, rp, d, h;
    fprintf(stderr, "Before zeroing\n");
    for (i = packstart; i != packend; i = NEXT_BUCKET(class, i)) {
      h = BUCKET_HASH(class, i);
      rp = HASH_INDEX(class, h);
      if (i >= rp)
        d = i - rp;
      else
        d = NUM_BUCKETS(class) + i - rp;
      fprintf(stderr, " i: %5" PRIu32 " d: %3" PRIu32 " value: %" PRIu32
              " h: %08X flags: %02X\n", i, d, BUCKET_VALUE(class, i),
              h, BUCKET_FLAGS(class, i));
    }
  }

  for (ito = packstart; ito != packend; ito = NEXT_BUCKET(class, ito))
    if (MARKED_FREE(class, ito)) {
      BUCKET_VALUE(class, ito) = 0;
      UNMARK_IT_FREE(class, ito);
    }

  if (DEBUG_packchain) {
    uint32_t i, rp, d, h;
    fprintf(stderr, "After packing\n");
    for (i = packstart; i != packend; i = NEXT_BUCKET(class, i)) {
      h = BUCKET_HASH(class, i);
      rp = HASH_INDEX(class, h);
      if (i >= rp)
        d = i - rp;
      else
        d = NUM_BUCKETS(class) + i - rp;
      fprintf(stderr, " i: %5" PRIu32 " d: %3" PRIu32 " value: %" PRIu32
              " h: %08X flags: %02X\n", i, d, BUCKET_VALUE(class, i),
              h, BUCKET_FLAGS(class, i));
    }
  }

}
/*****************************************************************/

/*
 * Prune and pack a chain in a class database
 * Returns the number of freed (zeroed) buckets
 */
static uint32_t osbf_microgroom(CLASS_STRUCT * class, uint32_t bindex)
{
  uint32_t i_aux, j_aux, right_position;
  static uint32_t microgroom_count = 0;
  uint32_t packstart, packlen;
  uint32_t zeroed_countdown, min_value, min_value_any;
  uint32_t distance, max_distance;
  uint32_t groom_locked = OSBF_MICROGROOM_LOCKED;

  j_aux = 0;
  zeroed_countdown = microgroom_stop_after;

  i_aux = j_aux = 0;
  microgroom_count++;

  /*  move to start of chain that overflowed,
   *  then prune just that chain.
   */
  min_value = OSBF_MAX_BUCKET_VALUE;
  i_aux = j_aux = HASH_INDEX(class, bindex);
  min_value_any = BUCKET_VALUE(class, i_aux);

  if (!BUCKET_IN_CHAIN(class, i_aux))
    return 0;                   /* initial bucket not in a chain! */

  while (BUCKET_IN_CHAIN(class, i_aux)) {
    if (BUCKET_VALUE(class, i_aux) < min_value_any)
      min_value_any = BUCKET_VALUE(class, i_aux);
    if (BUCKET_VALUE(class, i_aux) < min_value &&
        !BUCKET_IS_LOCKED(class, i_aux))
      min_value = BUCKET_VALUE(class, i_aux);
    i_aux = PREV_BUCKET(class, i_aux);
    if (i_aux == j_aux)
      break;                    /* don't hang if we have a 100% full .css file */
    /* fprintf (stderr, "-"); */
  }

  /*  now, move the index to the first bucket in this chain. */
  i_aux = NEXT_BUCKET(class, i_aux);
  packstart = i_aux;
  /* find the end of the chain */
  while (BUCKET_IN_CHAIN(class, i_aux)) {
    i_aux = NEXT_BUCKET(class, i_aux);
    if (i_aux == packstart)
      break;                    /* don't hang if we have a 100% full .cfc file */
  }
  /*  now, the index is right after the last bucket in this chain. */

  /* only >, not >= in this case, otherwise the packlen would be 0
   * instead of NUM_BUCKETS (class).
   */
  if (i_aux > packstart)
    packlen = i_aux - packstart;
  else                          /* if i_aux == packstart, packlen = header->buckets */
    packlen = NUM_BUCKETS(class) + i_aux - packstart;

  /* if no unlocked bucket can be zeroed, zero any */
  if (groom_locked > 0 || min_value == OSBF_MAX_BUCKET_VALUE) {
    groom_locked = 1;
    min_value = min_value_any;
  } else
    groom_locked = 0;

/*
 *   This pruning method zeroes buckets with minimum count in the chain.
 *   It tries first buckets with minimum distance to their right position,
 *   to increase the chance of zeroing older buckets first. If none with
 *   distance 0 is found, the distance is increased until at least one
 *   bucket is zeroed.
 *
 *   We keep track of how many buckets we've marked to be zeroed and we
 *   stop marking additional buckets after that point. That messes up
 *   the tail length, and if we don't repack the tail, then features in
 *   the tail can become permanently inaccessible! Therefore, we really
 *   can't stop in the middle of the tail (well, we could stop marking,
 *   but we need to pass the full length of the tail in).
 * 
 *   This is a statistics report of microgroomings for 4147 messages
 *   of the SpamAssassin corpus. It shows that 77% is done in a single
 *   pass, 95.2% in 1 or 2 passes and 99% in at most 3 passes.
 *
 *   # microgrommings   passes   %    accum. %
 *        232584           1    76.6   76.6
 *         56396           2    18.6   95.2
 *         11172           3     3.7   98.9
 *          2502           4     0.8   99.7
 *           726           5     0.2   99.9
 *           ...
 *   -----------
 *        303773
 *
 *   If we consider only the last 100 microgroomings, when the cfc
 *   file is full, we'll have the following numbers showing that most
 *   microgroomings (61%) are still done in a single pass, almost 90%
 *   is done in 1 or 2 passes and 97% are done in at most 3 passes:
 *
 *   # microgrommings   passes   %    accum. %
 *          61             1    61      61
 *          27             2    27      88
 *           9             3     9      97
 *           3             4     3     100
 *         ---
 *         100
 *
 *   So, it's not so slow. Anyway, a better algorithm could be
 *   implemented using 2 additional arrays, with MICROGROOM_STOP_AFTER
 *   positions each, to store the indexes of the candidate buckets
 *   found with distance equal to 1 or 2 while we scan for distance 0.
 *   Those with distance 0 are zeroed immediatelly. If none with
 *   distance 0 is found, we'll zero the indexes stored in the first
 *   array. Again, if none is found in the first array, we'll try the
 *   second one. Finally, if none is found in both arrays, the loop
 *   will continue until one bucket is zeroed.
 *
 *   But now comes the question: do the numbers above justify the
 *   additional code/work? I'll try to find out the answer
 *   implementing it :), but this has low priority for now.
 *
 */


  /* try features in their right place first */
  max_distance = 1;
  /* fprintf(stderr, "packstart: %ld,  packlen: %ld, max_zeroed_buckets: %ld\n",
     packstart, packlen, microgroom_stop_after); */

  /* while no bucket is zeroed...  */
  while (zeroed_countdown == microgroom_stop_after) {
    /*
       fprintf(stderr, "Start: %lu, stop_after: %u, max_distance: %lu,
       min_value: %lu\n", packstart,
       microgroom_stop_after, max_distance, min_value);
     */
    i_aux = packstart;
    while (BUCKET_IN_CHAIN(class, i_aux) && zeroed_countdown > 0) {
      /* check if it's a candidate */
      if ((BUCKET_VALUE(class, i_aux) == min_value) &&
          (!BUCKET_IS_LOCKED(class, i_aux) || (groom_locked != 0))) {
        /* if it is, check the distance */
        right_position = HASH_INDEX(class, BUCKET_HASH(class, i_aux));
        if (right_position <= i_aux)
          distance = i_aux - right_position;
        else
          distance = NUM_BUCKETS(class) + i_aux - right_position;
        if (distance < max_distance) {
          MARK_IT_FREE(class, i_aux);
          zeroed_countdown--;
        }
      }
      i_aux++;
      if (i_aux >= NUM_BUCKETS(class))
        i_aux = 0;
    }

    /*  if none was zeroed, increase the allowed distance between the */
    /*  candidade's position and its right place. */
    if (zeroed_countdown == microgroom_stop_after)
      max_distance++;
  }

  /*
     fprintf (stderr,
     "Leaving microgroom: %ld buckets with value %ld zeroed at distance %ld\n",
     microgroom_stop_after - zeroed_countdown, h[i].value, max_distance - 1);
   */

  /* now we pack the chains */
  osbf_packchain(class, packstart, packlen);

  /* return the number of zeroed buckets */
  return (microgroom_stop_after - zeroed_countdown);
}

/*****************************************************************/

/* get the index of the last bucket in a chain */
static uint32_t
osbf_last_in_chain (CLASS_STRUCT * class, uint32_t bindex)
{
  uint32_t wraparound;

  /* if the bucket is not in a chain, return an index */
  /* out of the buckets space, equal to the number of */
  /* buckets in the file to indicate an empty chain */
  if (!BUCKET_IN_CHAIN (class, bindex))
    return NUM_BUCKETS (class);

  wraparound = bindex;
  while (BUCKET_IN_CHAIN (class, bindex))
    {
      bindex++;
      if (bindex >= NUM_BUCKETS (class))
	bindex = 0;

      /* if .cfc file is full return an index out of */
      /* the buckets space, equal to number of buckets */
      /* in the file, plus one */
      if (bindex == wraparound)
	return NUM_BUCKETS (class) + 1;
    }

  if (bindex == 0)
    bindex = NUM_BUCKETS (class) - 1;
  else
    bindex--;

  return bindex;
}

/*****************************************************************/

uint32_t
osbf_find_bucket (CLASS_STRUCT * class, uint32_t hash, uint32_t key)
{
  uint32_t bindex, start;

  bindex = start = HASH_INDEX (class, hash);
  while (BUCKET_IN_CHAIN (class, bindex) &&
	 !BUCKET_HASH_COMPARE (class, bindex, hash, key))
    {
      bindex = NEXT_BUCKET (class, bindex);

      /* if .cfc file is completely full return an index */
      /* out of the buckets space, equal to number of buckets */
      /* in the file, plus one */
      if (bindex == start)
	return NUM_BUCKETS (class) + 1;
    }

  /* return the index of the found bucket or, if not found,
   * the index of a free bucket where it could be put
   */
  return bindex;
}


uint32_t
osbf_slow_find_bucket (CLASS_STRUCT * class, uint32_t start, uint32_t hash, uint32_t key)
{

  /* precondition: !BUCKET_HASH_COMPARE(class, start, hash, key)
     && BUCKET_IN_CHAIN(cd, start) */

  uint32_t bindex = start;
  do {
    bindex = NEXT_BUCKET (class, bindex);

    /* if .cfc file is completely full return an index */
    /* out of the buckets space, equal to number of buckets */
    /* in the file, plus one */
    if (bindex == start)
      return NUM_BUCKETS (class) + 1;
  } while (!BUCKET_HASH_COMPARE (class, bindex, hash, key) &&
           BUCKET_IN_CHAIN (class, bindex));

  /* return the index of the found bucket or, if not found,
   * the index of a free bucket where it could be put
   */
  return bindex;
}

/*****************************************************************/

void
osbf_update_bucket (CLASS_STRUCT * class, uint32_t bindex, int delta)
{

  /*
   * fprintf (stderr, "Bucket updated at %lu, hash: %lu, key: %lu, value: %d\n",
   *       bindex, hashes[bindex].hash, hashes[bindex].key, delta);
   */

  if (delta > 0 &&
      BUCKET_VALUE (class, bindex) + delta >= OSBF_MAX_BUCKET_VALUE)
    {
      BUCKET_VALUE (class, bindex) = OSBF_MAX_BUCKET_VALUE;
      LOCK_BUCKET(class, bindex);
    }
  else if (delta < 0 && BUCKET_VALUE (class, bindex) <= (uint32_t) (-delta))
    {
      if (BUCKET_VALUE (class, bindex) != 0)
	{
	  uint32_t i, packlen;

	  MARK_IT_FREE (class, bindex);

	  /* pack chain */
	  i = osbf_last_in_chain (class, bindex);
	  if (i >= bindex)
	    packlen = i - bindex + 1;
	  else
	    packlen = NUM_BUCKETS (class) - (bindex - i) + 1;
/*
	    fprintf (stderr, "packing: %" PRIu32 ", %" PRIu32 "\n", i,
		     bindex);
*/
	  osbf_packchain (class, bindex, packlen);
	}
    }
  else
    {
      BUCKET_VALUE (class, bindex) = BUCKET_VALUE (class, bindex) + delta;
      LOCK_BUCKET (class, bindex);
    }
}


/*****************************************************************/

void
osbf_insert_bucket (CLASS_STRUCT * class,
		    uint32_t bindex, uint32_t hash, uint32_t key, int value)
{
  uint32_t right_index, displacement;
  int microgroom = 1;

  /* "right" bucket index */
  right_index = HASH_INDEX (class, hash);
  /* displacement from right position to free position */
  displacement = (bindex >= right_index) ? bindex - right_index :
    NUM_BUCKETS (class) - (right_index - bindex);

  /* if not specified, max chain len is automatically specified */
  if (microgroom_displacement_trigger == 0)
    {
      /* from experimental values */
      microgroom_displacement_trigger = 14.85 + 1.5E-4 * NUM_BUCKETS (class);
      /* not less than 29 */
      if (microgroom_displacement_trigger < 29)
	microgroom_displacement_trigger = 29;
    }

  if (microgroom && (value > 0))
    while (displacement > microgroom_displacement_trigger)
      {
	/*
	 * fprintf (stderr, "hindex: %lu, bindex: %lu, displacement: %lu\n",
	 *          hindex, bindex, displacement);
	 */
	osbf_microgroom (class, PREV_BUCKET (class, bindex));
	/* get new free bucket index */
	bindex = osbf_find_bucket (class, hash, key);
	displacement = (bindex >= right_index) ? bindex - right_index :
	  NUM_BUCKETS (class) - (right_index - bindex);
      }

  /*
   *   fprintf (stderr,
   *   "new bucket at %lu, hash: %lu, key: %lu, displacement: %lu\n",
   *         bindex, hash, key, displacement);
   */

  BUCKET_VALUE (class, bindex) = value;
  BUCKET_HASH (class, bindex) = hash;
  BUCKET_KEY (class, bindex) = key;
  LOCK_BUCKET(class, bindex);
}

/*****************************************************************/

uint32_t
strnhash (unsigned char *str, uint32_t len)
{
  uint32_t i;
#ifdef CRM114_COMPATIBILITY
  int32_t hval;			/* signed int for CRM114 compatibility */
#else
  uint32_t hval;
#endif
  uint32_t tmp;

  /* initialize hval */
  hval = len;

  /*  for each character in the incoming text: */
  for (i = 0; i < len; i++)
    {
      /*
       *  xor in the current byte against each byte of hval
       *  (which alone gaurantees that every bit of input will have
       *  an effect on the output)
       */

      tmp = str[i];
      tmp = tmp | (tmp << 8) | (tmp << 16) | (tmp << 24);
      hval ^= tmp;

      /*    add some bits out of the middle as low order bits. */
      hval = hval + ((hval >> 12) & 0x0000ffff);

      /*     swap most and min significative bytes */
      tmp = (hval << 24) | ((hval >> 24) & 0xff);
      hval &= 0x00ffff00;	/* zero most and least significative bytes of hval */
      hval |= tmp;		/* OR with swapped bytes */

      /*    rotate hval 3 bits to the left (thereby making the */
      /*    3rd msb of the above mess the hsb of the output hash) */
      hval = (hval << 3) + (hval >> 29);
    }
  return (uint32_t) hval;
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

void
osbf_import (CLASS_STRUCT *class_to, const CLASS_STRUCT *class_from, OSBF_HANDLER *h)
{
  uint32_t i;

  if (class_to->state == OSBF_CLOSED || class_to->usage < OSBF_WRITE_ALL)
    osbf_raise(h, "Destination class %s is not open for full write",
               class_to->classname == NULL ? "(name unknown)" : class_to->classname);

  if (class_from->state == OSBF_CLOSED)
    osbf_raise(h, "Source class %s is not open",
               class_from->classname == NULL
                 ? "(name unknown)"
                 : class_from->classname);

  class_to->header->learnings       += class_from->header->learnings;
  class_to->header->extra_learnings += class_from->header->extra_learnings;
  class_to->header->classifications += class_from->header->classifications;
  class_to->header->false_negatives += class_from->header->false_negatives;
  class_to->header->false_positives += class_from->header->false_positives;

  memset(class_to->bflags, 0, class_to->header->num_buckets * sizeof(unsigned char));
          /* make sure that the microgroomer is not confused by leftover bflags info */

  for (i = 0; i < class_from->header->num_buckets; i++)
    {
      uint32_t bindex;

      if (class_from->buckets[i].count == 0)
        continue;

      bindex = osbf_find_bucket (class_to,
      			   class_from->buckets[i].hash1,
      			   class_from->buckets[i].hash2);
      if (bindex < class_to->header->num_buckets) {
        if (BUCKET_IN_CHAIN (class_to, bindex)) {
          osbf_update_bucket (class_to, bindex,
                              class_from->buckets[i].count);
        } else {
          osbf_insert_bucket (class_to, bindex,
                              class_from->buckets[i].hash1,
                              class_from->buckets[i].hash2,
                              class_from->buckets[i].count);
        }
      } else {
        osbf_raise(h, ".cfc file %s is full!",
                   class_to->classname == NULL
                     ? "(name unknown)"
                     : class_to->classname);
        return;
      }
    }

}

/****************************************************************/
void append_error_message(char *err1, const char *err2) {
  int n = strlen(err1);
  strncat(err1+n, err2, OSBF_ERROR_MESSAGE_LEN - n - 1);
}

/****************************************************************/
void *osbf_malloc(size_t size, OSBF_HANDLER *h, const char *what) {
  void *p = malloc(size);
  if (p == NULL) osbf_raise(h, "Could not allocate memory for %s", what);
  return p;
}

void *osbf_calloc(size_t nmemb, size_t size, OSBF_HANDLER *h, const char *what) {
  void *p = calloc(nmemb, size);
  if (p == NULL) osbf_raise(h, "Could not allocate memory for %s", what);
  return p;
}

