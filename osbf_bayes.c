/*
 * osbf_bayes.c
 * 
 * See Copyright Notice in osbflua.h
 *
 */

#include <stdio.h>
#include <ctype.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <math.h>
#include <sys/mman.h>
#include <inttypes.h>
#include <errno.h>

#define DEBUG 0  /* usefully 0, 1, 2, or > 2 */

/*  OSBF structures */
#include "osbflib.h"

struct token_search
{
  unsigned char *ptok;
  unsigned char *ptok_max;
  uint32_t toklen;
  uint32_t hash;
  const char *delims;
};

#define TMPBUFFSIZE 512
char tempbuf[TMPBUFFSIZE + 2];

extern uint32_t microgroom_displacement_trigger;
uint32_t max_token_size = OSBF_MAX_TOKEN_SIZE;
uint32_t max_long_tokens = OSBF_MAX_LONG_TOKENS;
uint32_t limit_token_size = 0;
enum a_priori_options a_priori = LEARNINGS;

/*
 *   the hash coefficient tables should be full of relatively prime numbers,
 *   and preferably superincreasing, though both of those are not strict
 *   requirements. The two tables must not have a common prime.
 */
static uint32_t hctable1[] = { 1, 3, 5, 11, 23, 47, 97, 197, 397, 797 };
static uint32_t hctable2[] =
  { 7, 13, 29, 51, 101, 203, 407, 817, 1637, 3277 };

/* constants used in the CF formula */
double K1 = 0.25, K2 = 12, K3 = 8;

/* maps strings to a_priori_options enum */
const char *a_priori_strings[] = {
  "LEARNINGS",
  "INSTANCES",
  "CLASSIFICATIONS",
  "MISTAKES",
  NULL
};

/*****************************************************************/
/* experimental code */
#if (0)
static double
lnfact (uint32_t n)
{
  static double lnfact_table[1001];

  if (n <= 1)
    return 0.0;
  if (n <= 1000)
    return lnfact_table[n] ?
      lnfact_table[n] : (lnfact_table[n] = lgamma (n + 1.0));
  else
    return lgamma (n + 1.0);
}

static double
conf_factor (uint32_t n, uint32_t k, double interval)
{
  uint32_t i, j, start, end;
  double b, sum;

  j = floor (0.5 + interval * n);

  if (j > k)
    start = 0;
  else
    start = k - j;

  if (j + k <= n)
    end = j + k;
  else
    end = n;

  sum = 0;
  for (i = start; i <= end; i++)
    {
      b = exp (lnfact (n) - lnfact (i) - lnfact (n - i) - n * log (2));
      if (sum + b < 1)
	sum += b;
    }

  return 1 - sum;
}
#endif

/*****************************************************************/

static unsigned char *
get_next_token (unsigned char *p_text, unsigned char *max_p,
		const char *delims, uint32_t * p_toklen)
{
  unsigned char *p_ini;  /* will be set to start of the next token */
  unsigned char *lim;    /* place beyond which we must not look;
                            normally max_p unless limit_token_size != 0 */

#if 0
  /* this code is in the inner loop, and we guarantee delims != NULL elsewhere */
  if (delims == NULL)
    return NULL;
#endif

#define DELIMP(P) (!isgraph((int) *(P)) || strchr (delims, (int) *(P)))

  /* find nongraph delimited token */
  while (p_text < max_p && DELIMP(p_text))
    p_text++;
  p_ini = p_text;

  if (limit_token_size) {
    /* limit the tokens to max_token_size */
    lim = p_ini + max_token_size;
    if (lim > max_p)
      lim = max_p;
  } else {
    lim = max_p;
  }
  while (p_text < lim && !DELIMP(p_text))
    p_text++;

  *p_toklen = p_text - p_ini;

if (0)
  {
    uint32_t i = 0;
    while (i < *p_toklen)
      fputc (p_ini[i++], stderr);
    fprintf (stderr, " - toklen: %" PRIu32
	     ", max_token_len: %" PRIu32
	     ", max_long_tokens: %" PRIu32 "\n",
	     *p_toklen, max_token_size, max_long_tokens);
  }


  return p_ini;
}

/*****************************************************************/

static uint32_t
get_next_hash (struct token_search *pts)
{
  uint32_t hash_acc = 0;
  uint32_t count_long_tokens = 0;
  int error = 0;

  pts->ptok += pts->toklen;
  pts->ptok = get_next_token (pts->ptok, pts->ptok_max,
			      pts->delims, &(pts->toklen));

#ifdef OSBF_MAX_TOKEN_SIZE
  /* long tokens, probably encoded lines */
  while (pts->toklen >= max_token_size && count_long_tokens < max_long_tokens)
    {
      count_long_tokens++;
      /* XOR new hash with previous one */
      hash_acc ^= strnhash (pts->ptok, pts->toklen);
      /* fprintf(stderr, " %0lX +\n ", hash_acc); */
      /* advance the pointer and get next token */
      pts->ptok += pts->toklen;
      pts->ptok = get_next_token (pts->ptok, pts->ptok_max,
				  pts->delims, &(pts->toklen));
    }


#endif

  if (pts->toklen > 0 || count_long_tokens > 0)
    {
      hash_acc ^= strnhash (pts->ptok, pts->toklen);
      pts->hash = hash_acc;
      /* fprintf(stderr, " %0lX %lu\n", hash_acc, pts->toklen); */
    }
  else
    {
      /* no more hashes */
      /* fprintf(stderr, "End of text %0lX %lu\n", hash_acc, pts->toklen); */
      error = 1;
    }

  return (error);
}

/******************************************************************/
/* Train the specified class with the text pointed to by "p_text" */
/******************************************************************/
void osbf_bayes_train (const unsigned char *p_text,	/* pointer to text */
		       unsigned long text_len,  /* length of text */
                       const char *delims,      /* token delimiters */
                       CLASS_STRUCT *class,    /* database to be trained */
                       int sense,       /* 1 => learn;  -1 => unlearn */
                       enum learn_flags flags,  /* flags */
                       OSBF_HANDLER *h)
{
  uint32_t window_idx;
  int32_t learn_error;
  int32_t i;
  uint32_t hashpipe[OSB_BAYES_WINDOW_LEN + 1];

    /* on 5000 msgs from trec06, average number of tokens (including
       sentinels at ends) is 150; 2/3 of msgs are under 150; 80% are
       under 200; 90% are under 300.  99% are under 1000.  So if one
       were to make a copy rather than pipelining, 200 would seem to
       be a good starting length */

  int32_t num_hash_paddings;
  int microgroom;
  struct token_search ts;

  /* fprintf(stderr, "Starting learning...\n"); */

  osbf_raise_unless(delims != NULL, h, "NULL delimiters; use empty string instead");

  ts.ptok = (unsigned char *) p_text;
  ts.ptok_max = (unsigned char *) (p_text + text_len);
  ts.toklen = 0;
  ts.hash = 0;
  ts.delims = delims;

  if (class->state == OSBF_CLOSED)
    osbf_raise(h, "Trying to train a closed class\n");
  if (class->usage != OSBF_WRITE_ALL)
    osbf_raise(h, "Trying to train class %s without opening for write",
               class->classname);

  microgroom = (flags & NO_MICROGROOM) == 0;
  memset(class->bflags, 0, class->header->num_buckets * sizeof(unsigned char));
    
  /*   init the hashpipe with 0xDEADBEEF  */
  for (i = 0; i < OSB_BAYES_WINDOW_LEN; i++)
    hashpipe[i] = 0xDEADBEEF;

  learn_error = 0;
  /* experimental code - set num_hash_paddings = 0 to disable */
  /* num_hash_paddings = OSB_BAYES_WINDOW_LEN - 1; */
  num_hash_paddings = OSB_BAYES_WINDOW_LEN - 1;
  while (learn_error == 0 && ts.ptok <= ts.ptok_max)
    {

      if (get_next_hash (&ts) != 0)
	{
	  /* after eof, insert fake tokens until the last real */
	  /* token comes out at the other end of the hashpipe */
	  if (num_hash_paddings-- > 0)
	    ts.hash = 0xDEADBEEF;
	  else
	    break;
	}

      /*  Shift the hash pipe down one and insert new hash */
      for (i = OSB_BAYES_WINDOW_LEN - 1; i > 0; i--)
	hashpipe[i] = hashpipe[i - 1];
      hashpipe[0] = ts.hash;

#if (DEBUG > 2)
      {
	fprintf (stderr, "  Hashpipe contents: ");
	for (h = 0; h < OSB_BAYES_WINDOW_LEN; h++)
	  fprintf (stderr, " %" PRIu32, hashpipe[h]);
	fprintf (stderr, "\n");
      }
#endif

      {
	uint32_t hindex, bindex;
	uint32_t h1, h2;

	for (window_idx = 1; window_idx < OSB_BAYES_WINDOW_LEN; window_idx++)
	  {

	    h1 =
	      hashpipe[0] * hctable1[0] +
	      hashpipe[window_idx] * hctable1[window_idx];
#ifdef CRM114_COMPATIBILITY
	    h2 = hashpipe[0] * hctable2[0] +
	      hashpipe[window_idx] * hctable2[window_idx - 1];
#else
	    h2 = hashpipe[0] * hctable2[0] +
	      hashpipe[window_idx] * hctable2[window_idx];
#endif
	    hindex = h1 % class->header->num_buckets;

#if (DEBUG > 2)
	    fprintf (stderr,
		     "Polynomial %" PRIu32 " has h1:%" PRIu32 "  h2: %"
		     PRIu32 "\n", window_idx, h1, h2);
#endif

	    bindex = FAST_FIND_BUCKET (class, h1, h2);
	    if (bindex < class->header->num_buckets)
	      {
		if (BUCKET_IN_CHAIN (class, bindex))
		  {
		    if (!BUCKET_IS_LOCKED (class, bindex))
		      osbf_update_bucket (class, bindex, sense);
		  }
		else if (sense > 0)
		  {
		    osbf_insert_bucket (class, bindex, h1, h2, sense);
		  }
	      }
	    else
	      {
                char errmsg[100];
                snprintf(errmsg, sizeof(errmsg), ".cfc file %s is full!",
                         class->classname);
                osbf_close_class(class, h);
                osbf_raise(h, "%s", errmsg);
		return;
	      }
	  }
      }
    }				/*   end the while k==0 */


    if (sense > 0)
      {
        /* extra learnings are all those done with the  */
        /* same document, after the first learning */
        if (flags & EXTRA_LEARNING)
          {
            /* increment extra learnings counter */
            class->header->extra_learnings += 1;
          }
        else
          {
            /* increment normal learnings counter */

            /* old code disabled because the databases are disjoint and
               this correction should be applied to both simultaneously

               class->header->learnings += 1;
               if (class->header->learnings >= OSBF_MAX_BUCKET_VALUE)
               {
               uint32_t i;

               class->header->learnings >>= 1;
               for (i = 0; i < NUM_BUCKETS (class); i++)
               BUCKET_VALUE (class, i) = BUCKET_VALUE (class, i) >> 1;
               }
             */

            if (class->header->learnings < OSBF_MAX_BUCKET_VALUE)
              {
                class->header->learnings += 1;
              }

            /* increment false negative counter */
            if (flags & FALSE_NEGATIVE)
              {
                class->header->false_negatives += 1;
              }
          }
      }
    else
      {
        if (flags & EXTRA_LEARNING)
          {
            /* decrement extra learnings counter */
            if (class->header->extra_learnings > 0)
              class->header->extra_learnings -= 1;
          }
        else
          {
            /* decrement learnings counter */
            if (class->header->learnings > 0)
              class->header->learnings -= 1;
            /* decrement false negative counter */
            if ((flags & FALSE_NEGATIVE) && class->header->false_negatives > 0)
              class->header->false_negatives -= 1;
          }
      }

#if 0
    { 
      unsigned n = 40;
      unsigned j;
    fprintf(stderr, "### %u nonzero buckets after training =", n);
    for (j = 0; j < NUM_BUCKETS(class); j++)
      if (BUCKET_IN_CHAIN(class, j)) {
        fprintf(stderr, " %u", j);
        if (--n == 0) break;
      }
    fprintf(stderr, "\n");
    }
#endif

}

/**********************************************************/
/* Given the text pointed to by "p_text", for each class  */
/* in the array "classes", find the probability that the  */
/* text belongs to that class                             */
/**********************************************************/
void
osbf_bayes_classify (const unsigned char *p_text,       /* pointer to text */
                     unsigned long text_len,    /* length of text */
                     const char *delims,        /* token delimiters */
                     CLASS_STRUCT *classes[],   /* hash file names */
                     unsigned num_classes,
                     uint32_t flags,    /* flags */
                     double min_pmax_pmin_ratio,
                     /* returned values */
                     double ptc[],      /* class probs */
                     uint32_t ptt[],    /* number trainings per class */
                     OSBF_HANDLER *h    /* error handler */
  )
{
  int32_t window_idx;
  unsigned class_idx;
  CLASS_STRUCT **class_lim = classes + num_classes;
  CLASS_STRUCT **pclass;
  int32_t i;                    /* we use i for our hashpipe counter, as needed. */

  double renorm = 0.0;
  uint32_t hashpipe[OSB_BAYES_WINDOW_LEN + 1];

  double a_priori_prob;         /* inverse of the number of classes: 1/num_classes */
  uint32_t total_learnings = 0;
  uint32_t totalfeatures;       /* total features */

  /* empirical weights: (5 - d) ^ (5 - d) */
  /* where d = number of skipped tokens in the sparse bigram */
  double feature_weight[] = { 0, 3125, 256, 27, 4, 1 };
  double exponent;
  double confidence_factor;
  int asymmetric = 0;           /* break local p loop early if asymmetric on */
  int voodoo = 1;               /* turn on the "voodoo" CF formula - default */
  double a_priori_counter[OSBF_MAX_CLASSES];
  double total_a_priori;

  struct token_search ts;

  osbf_raise_unless((flags & COUNT_CLASSIFICATIONS) == 0, h,
                    "Asked to count classifications, but this must now be "
                    "done as a separate operation");

  osbf_raise_unless(delims != NULL, h, "NULL delimiters; use empty string instead");

  ts.ptok = (unsigned char *) p_text;
  ts.ptok_max = (unsigned char *) (p_text + text_len);
  ts.toklen = 0;
  ts.hash = 0;
  ts.delims = delims;

  /* fprintf(stderr, "Starting classification...\n"); */

  osbf_raise_unless (text_len > 0, h, "Attempt to classify an empty text.");
  osbf_raise_unless(num_classes > 0, h, "At least one class must be given.");

  if (flags & NO_EDDC)
    voodoo = 0;

  total_a_priori = 0;
  for (pclass = classes; pclass < class_lim; pclass++) {
    CLASS_STRUCT *class = *pclass;
    osbf_raise_unless(class->state != OSBF_CLOSED, h,
                      "class number %d is closed", pclass - classes);

    memset(class->bflags, 0, class->header->num_buckets * sizeof(unsigned char));
    ptt[pclass-classes] = class->learnings = class->header->learnings;
      /*  avoid division by 0 */
    if (class->learnings == 0)
      class->learnings++;

    /* update total learnings */
    total_learnings += class->learnings;

    /* select type of estimate for a-priori */
#if (DEBUG > 0)
        fprintf (stderr, "Using %s for a-priori estimate\n", a_priori_strings[a_priori]);
#endif
    switch (a_priori) {
      case LEARNINGS: 
        a_priori_counter[pclass-classes] = class->header->learnings;
        break;
      case INSTANCES: 
        if (class->header->db_version >= OSBF_DB_FP_FN_VERSION)
          a_priori_counter[pclass-classes] =
            class->header->classifications + class->header->false_negatives -
            class->header->false_positives;
        else
          osbf_raise(h, "Database version %s doesn't support 'INSTANCES' for a priori estimation. Try 'CLASSIFICATIONS' instead.", class->header->db_version);
        break;
      case CLASSIFICATIONS: 
        a_priori_counter[pclass-classes] = class->header->classifications;
        break;
      case MISTAKES: 
        a_priori_counter[pclass-classes] = class->header->false_negatives;
        break;
      default:
        osbf_raise(h, "Given a-priori option (%d) is out of range [%d, %d]",
                   a_priori, 0, A_PRIORI_UPPER_LIMIT-1);
        break;
    }

     /* avoid division by zero */
     if (a_priori_counter[pclass-classes] < 1) 
       a_priori_counter[pclass-classes] = 1;
     total_a_priori += a_priori_counter[pclass-classes]; 
  }


  /* a-priori, zero-knowledge, class probability */
  a_priori_prob = 1.0 / (double) num_classes;

  exponent = pow (total_learnings * 3, 0.2);
  if (exponent < 5) {
    feature_weight[1] = pow (exponent, exponent);
    feature_weight[2] = pow (exponent * 4.0 / 5.0, exponent * 4.0 / 5.0);
    feature_weight[3] = pow (exponent * 3.0 / 5.0, exponent * 3.0 / 5.0);
    feature_weight[4] = pow (exponent * 2.0 / 5.0, exponent * 2.0 / 5.0);
  }

  for (pclass = classes; pclass < class_lim; pclass++) {
    CLASS_STRUCT *class = *pclass;
    /*  initialize our arrays for N .cfc files */
    class->hits = 0.0;  /* absolute hit counts */
    class->totalhits = 0;       /* absolute hit counts */
    class->uniquefeatures = 0;  /* features counted per class */
    class->missedfeatures = 0;  /* missed features per class */
    /* estimate class a-priori probability */
    ptc[pclass-classes] = a_priori_counter[pclass-classes] / total_a_priori;

#if 0
    { 
      unsigned n = 40;
      unsigned j;
    fprintf(stderr, "### Class %s %u nonzero buckets before classification =",
            class->classname, n);
    for (j = 0; j < NUM_BUCKETS(class); j++)
      if (BUCKET_IN_CHAIN(class, j)) {
        fprintf(stderr, " %u", j);
        if (--n == 0) break;
      }
    fprintf(stderr, "\n");
    }
#endif
  }

  /*   now all of the files are mmapped into memory, */
  /*   and we can do the polynomials and add up points. */

  /* init the hashpipe with 0xDEADBEEF  */
  /* XXX last element is uninitialized.  consider NELEMS */
  for (i = 0; i < OSB_BAYES_WINDOW_LEN; i++)
    hashpipe[i] = 0xDEADBEEF;

  totalfeatures = 0;

  while (ts.ptok <= ts.ptok_max && get_next_hash(&ts) == 0) {

    double htf;                   /* hits this feature got. */

    /* Shift the hash pipe down one and insert new hash */
    memmove(hashpipe+1, hashpipe, sizeof(hashpipe) - sizeof(hashpipe[0]));
    hashpipe[0] = ts.hash;
    ts.hash = 0;  /* clean hash */

    {
      uint32_t hindex;
      uint32_t h1, h2;
      /* remember indexes of classes with min and max local probabilities */
      int i_min_p, i_max_p;
      /* remember min and max local probabilities of a feature */
      double min_local_p, max_local_p;
      /* flag for already seen features */
      int already_seen;

      for (window_idx = 1; window_idx < OSB_BAYES_WINDOW_LEN; window_idx++) {
        h1 = hashpipe[0] * hctable1[0] + hashpipe[window_idx] * hctable1[window_idx];
#ifdef CRM114_COMPATIBILITY
        h2 = hashpipe[0] * hctable2[0] + hashpipe[window_idx] * hctable2[window_idx-1];
#else
        h2 = hashpipe[0] * hctable2[0] + hashpipe[window_idx] * hctable2[window_idx];
#endif

        hindex = h1;

#if (DEBUG > 2)
        fprintf (stderr, "Polynomial %" PRIu32 " has h1:%i" PRIu32 "  h2: %"
                 PRIu32 "\n", window_idx, h1, h2);
#endif

        htf = 0;  /* number of classes in which this feature is hit */
        totalfeatures++;

        min_local_p = 1.0;
        max_local_p = 0;
        i_min_p = i_max_p = 0;
        already_seen = 0;
        for (pclass = classes; pclass < class_lim; pclass++) {
          CLASS_STRUCT *class = *pclass;
          uint32_t lh, lh0;
          double p_feat = 0;

          lh = HASH_INDEX (class, hindex);
          lh0 = lh;
          class->hits = 0;

          /* look for feature with hashes h1 and h2 */
          lh = FAST_FIND_BUCKET (class, h1, h2);

          /* the bucket is valid if its index is valid. if the     */
          /* index "lh" is >= the number of buckets, it means that */
          /* the .cfc file is full and the bucket wasn't found     */
          if (VALID_BUCKET (class, lh) && BUCKET_FLAGS(class, lh) == 0
              && BUCKET_IN_CHAIN (class, lh))
          {
            /* only not previously seen features are considered */
            class->bflags[lh] = 1;          /* mark the feature as seen */
            class->uniquefeatures += 1;     /* count unique features used */
            class->hits = BUCKET_VALUE (class, lh);
            class->totalhits += class->hits; /* remember totalhits */
            htf += class->hits; /* and hits-this-feature */
            p_feat = class->hits / class->learnings;

            /* set i_{min,max}_p to classes with {minimum,maxmum} P(F) */
            if (p_feat <= min_local_p) {
              i_min_p = pclass - classes;
              min_local_p = p_feat;
            }
            if (p_feat >= max_local_p) {
              i_max_p = pclass - classes;
              max_local_p = p_feat;
            }
          } else if (!VALID_BUCKET(class, lh) || BUCKET_FLAGS(class, lh) == 0) {
              /* either bucket is invalid or it is not in a chain */
              /* invalid bucket is treated like feature not found */
               /*
                * a feature that wasn't found can't be marked as
                * already seen in the doc because the index lh
                * doesn't refer to it, but to the first empty bucket
                * after the chain, which is common to all not-found
                * features in the same chain. This is not a problem
                * though, because if the feature is found in another
                * class, it'll be marked as seen on that class,
                * which is enough to mark it as seen. If it's not
                * found in any class, it will have zero count on
                * all classes and will be ignored as well. So, only
                * found features are marked as seen.
                */
               i_min_p = pclass - classes;
               min_local_p = p_feat = 0;
               /* for statistics only (for now...) */
               class->missedfeatures += 1;
          } else { /* bucket is valid, flags not zero */
            already_seen = 1;
            if (asymmetric != 0)
              break;
          }

        }





            /*=======================================================
             * Update the probabilities using Bayes:
             *
             *                      P(F|S) P(S)
             *     P(S|F) = -------------------------------
             *               P(F|S) P(S) +  P(F|H) P(H)
             *
             * S = class spam; H = class ham; F = feature
             *
             * Here we adopt a different method for estimating
             * P(F|S). Instead of estimating P(F|S) as (hits[S][F] /
             * (hits[S][F] + hits[H][F])), like in the original
             * code, we use (hits[S][F] / learnings[S]) which is the
             * ratio between the number of messages of the class S
             * where the feature F was observed during learnings and
             * the total number of learnings of that class. Both
             * values are kept in the respective .cfc file, the
             * number of learnings in the header and the number of
             * occurrences of the feature F as the value of its
             * feature bucket.
             *
             * It's worth noting another important difference here:
             * as we want to estimate the *number of messages* of a
             * given class where a certain feature F occurs, we
             * count only the first occurrence of each feature in a
             * message (repetitions are ignored), both when learning
             * and when classifying.
             * 
             * Advantages of this method, compared to the original:
             *
             * - First of all, and the most important: accuracy is
             * really much better, at about the same speed! With
             * this higher accuracy, it's also possible to increase
             * the speed, at the cost of a low decrease in accuracy,
             * using smaller .cfc files;
             *
             * - It is not affected by different sized classes
             * because the numerator and the denominator belong to
             * the same class;
             *
             * - It allows a simple and fast pruning method that
             * seems to introduce little noise: just zero features
             * with lower count in a overflowed chain, zeroing first
             * those in their right places, to increase the chances
             * of deleting older ones.
             *
             * Disadvantages:
             *
             * - It breaks compatibility with previous .css file
             * format because of different header structure and
             * meaning of the counts.
             *
             * Confidence factors
             *
             * The motivation for confidence factors is to reduce
             * the noise introduced by features with small counts
             * and/or low significance. This is an attempt to mimic
             * what we do when inspecting a message to tell if it is
             * spam or not. We intuitively consider only a few
             * tokens, those which carry strong indications,
             * according to what we've learned and remember, and
             * discard the ones that may occur (approximately)
             * equally in both classes.
             *
             * Once P(Feature|Class) is estimated as above, the
             * calculated value is adjusted using the following
             * formula:
             *
             *  CP(Feature|Class) = 1/num_classes + 
             *     CF(Feature) * (P(Feature|Class) - 1/num_classes)
             *
             * Where CF(Feature) is the confidence factor and
             * CP(Feature|Class) is the adjusted estimate for the
             * probability.
             *
             * CF(Feature) is calculated taking into account the
             * weight, the max and the min frequency of the feature
             * over the classes, using the empirical formula:
             *
             *     (((Hmax - Hmin)^2 + Hmax*Hmin - K1/SH) / SH^2) ^ K2
             * CF(Feature) = ------------------------------------------
             *                    1 +  K3 / (SH * Weight)
             *
             * Hmax  - Number of documents with the feature "F" on
             * the class with max local probability;
             * Hmin  - Number of documents with the feature "F" on
             * the class with min local probability;
             * SH - Sum of Hmax and Hmin
             * K1, K2, K3 - Empirical constants
             *
             * OBS: - Hmax and Hmin are normalized to the max number
             *  of learnings of the 2 classes involved.
             *  - Besides modulating the estimated P(Feature|Class),
             *  reducing the noise, 0 <= CF < 1 is also used to
             *  restrict the probability range, avoiding the
             *  certainty falsely implied by a 0 count for a given
             *  class.
             *
             * -- Fidelis Assis
             *=======================================================*/

            /* ignore already seen features */
            /* ignore less significant features (CF = 0) */
            if ((already_seen != 0) || ((max_local_p - min_local_p) < 1E-6))
              continue;
            if ((min_local_p > 0)
                && ((max_local_p / min_local_p) < min_pmax_pmin_ratio))
              continue;

            /* code under testing... */
            /* calculate confidence_factor */
            {
              uint32_t hits_max_p, hits_min_p, sum_hits;
              int32_t diff_hits;
              double cfx = 1;
              /* constants used in the CF formula */
              /* K1 = 0.25; K2 = 10; K3 = 8;      */
              /* const double K1 = 0.25, K2 = 10, K3 = 8; */

              hits_min_p = classes[i_min_p]->hits;
              hits_max_p = classes[i_max_p]->hits;

              /* normalize hits to max learnings */
              if (classes[i_min_p]->learnings < classes[i_max_p]->learnings)
                hits_min_p *=
                  (double) classes[i_max_p]->learnings /
                  (double) classes[i_min_p]->learnings;
              else
                hits_max_p *=
                  (double) classes[i_min_p]->learnings /
                  (double) classes[i_max_p]->learnings;

              sum_hits = hits_max_p + hits_min_p;
              diff_hits = hits_max_p - hits_min_p;
              if (diff_hits < 0)
                diff_hits = -diff_hits;

              /* calculate confidence factor (CF) */
              if (voodoo == 0)  /* || min_local_p > 0 ) */
                confidence_factor = 1 - OSBF_DBL_MIN;
              else
#define EDDC_VARIANT 3
#if   (EDDC_VARIANT == 1)
                confidence_factor =
                  pow ((diff_hits * diff_hits +
                        hits_max_p * hits_min_p -
                        K1 / sum_hits) / (sum_hits * sum_hits),
                       K2) / (1.0 +
                              K3 / (sum_hits * feature_weight[window_idx]));
#elif (EDDC_VARIANT == 2)
                confidence_factor =
                  pow ((diff_hits * diff_hits - K1 / sum_hits) /
                       (sum_hits * sum_hits), K2) / (1.0 +
                                                     K3 / (sum_hits *
                                                           feature_weight
                                                           [window_idx]));
#elif (EDDC_VARIANT == 3)
                cfx =
                  0.8 + (classes[i_min_p]->header->learnings +
                         classes[i_max_p]->header->learnings) / 20.0;
              if (cfx > 1)
                cfx = 1;
              confidence_factor = cfx *
                pow ((diff_hits * diff_hits - K1 /
                      (classes[i_max_p]->hits + classes[i_min_p]->hits)) /
                     (sum_hits * sum_hits), 2) /
                (1.0 +
                 K3 / ((classes[i_max_p]->hits + classes[i_min_p]->hits) *
                       feature_weight[window_idx]));
#elif (EDDC_VARIANT == 4)
                confidence_factor =
                  conf_factor (sum_hits, diff_hits, 0.1) / (1.0 +
                                                            K3 / (sum_hits *
                                                                  feature_weight
                                                                  [window_idx]));
#endif

#if (DEBUG > 1)
              fprintf
                (stderr,
                 "CF: %.4f, max_hits = %3" PRIu32 ", min_hits = %3" PRIu32
                 ", " "weight: %5.1f\n", confidence_factor, hits_max_p,
                 hits_min_p, feature_weight[window_idx]);
#endif
            }

            /* calculate the numerators - P(F|C) * P(C) */
            renorm = 0.0;
            for (class_idx = 0; class_idx < num_classes; class_idx++)
              {
                /*
                 * P(C) = learnings[k] / total_learnings
                 * P(F|C) = hits[k]/learnings[k], adjusted by the
                 * confidence factor.
                 */
                if (0)
                  fprintf(stderr, "## %g hits for class %s\n",
                          classes[class_idx]->hits, classes[class_idx]->classname);

                ptc[class_idx] = ptc[class_idx] *
                  (a_priori_prob + confidence_factor *
                   (classes[class_idx]->hits / classes[class_idx]->learnings -
                    a_priori_prob));

                if (ptc[class_idx] < OSBF_SMALLP)
                  ptc[class_idx] = OSBF_SMALLP;
                renorm += ptc[class_idx];
#if (DEBUG > 1)
                fprintf (stderr, "CF: %.4f, classes[k]->totalhits: %" PRIu32 ", "
                         "missedfeatures[k]: %" PRIu32
                         ", uniquefeatures[k]: %" PRIu32 ", "
                         "totalfeatures: %" PRIu32 ", weight: %5.1f\n",
                         confidence_factor, classes[class_idx]->totalhits,
                         classes[class_idx]->missedfeatures,
                         classes[class_idx]->uniquefeatures, totalfeatures,
                         feature_weight[window_idx]);
#endif

              }

            /* renormalize probabilities */
            for (class_idx = 0; class_idx < num_classes; class_idx++)
              ptc[class_idx] = ptc[class_idx] / renorm;

#if (DEBUG > 2)
            {
              for (class_idx = 0; class_idx < num_classes; class_idx++)
                {
                  fprintf (stderr,
                           " poly: %" PRIu32 "  filenum: %" PRIu32
                           ", HTF: %7.0f, " "learnings: %7" PRIu32
                           ", hits: %7.0f, " "Pc: %6.4e\n",
                           window_idx, class_idx, htf,
                           classes[class_idx]->header->learnings,
                           classes[class_idx]->hits, ptc[class_idx]);
                }
            }
#endif
    }
      }
    }

  if (renorm == 0.0) { /* could happen if we get, say, a one-word message
                          like 'gurgle:' -- code above is not reached */
    /* renormalize probabilities */
if(0)
fprintf(stderr, "## NO SIGNIFICANT HITS FOR ANY CLASS!!!\n## (text is %.50s...)\n", p_text);
    for (class_idx = 0; class_idx < num_classes; class_idx++)
        renorm += ptc[class_idx];

    for (class_idx = 0; class_idx < num_classes; class_idx++)
      ptc[class_idx] = ptc[class_idx] / renorm;
  }
    

#if (DEBUG > 0)
  {
    for (class_idx = 0; class_idx < num_classes; class_idx++)
      fprintf (stderr,
               "Probability of match for file %" PRIu32 ": %f\n",
               class_idx, ptc[class_idx]);
  }
#endif

}
