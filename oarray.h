/*
 * See Copyright Notice in osbflib.h
 */

#ifndef OARRAY_H
#define OARRAY_H

#include <inttypes.h>
#include <assert.h>

#include "osbferr.h"

/* An array is a block of 'size' unsigned integers starting at 'elems'.
   Only (next-elems) integers are actually in use to hold data;
   the pointer 'next' points to the next unused byte.
   All unused integers except the last are equal to zero.
   The array is always fully aligned */

typedef struct oarray {
  uint32_t *elems;
  uint32_t *next;
  unsigned size;
} OARRAY;

#define OARRAY_APPEND(A, E, H)  \
  do { if ((A).next == NULL)    \
         osbf_raise("Tried to append to a closed array"); \
       else if (*(A).next == 0) { \
         *(A).next++ = (E);  \
       } else {              \
         oarray_grow(&(A), H);  \
         *(A).next++ = (E);  \
       }                     \
    } while(0)

extern OARRAY oarray_alloc(unsigned nelems, OSBF_HANDLER *h);
  /* create an array to hold 'nelems' integers; where 'nelems' > 0 */
extern void oarray_free(OARRAY *A, OSBF_HANDLER *h);
  /* reclaim an array's memory */
extern void oarray_grow(OARRAY *A, OSBF_HANDLER *h);
  /* make it bigger! */


#endif /* OARRAY_H */
