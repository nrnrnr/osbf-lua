/*
 * See Copyright Notice in osbflua.h
 */

#include <stdlib.h>
#include <string.h>

#include "oarray.h"

OARRAY oarray_alloc(unsigned n, OSBF_HANDLER *h) {
  OARRAY result;
  result.elems = calloc(n, sizeof(result.elems[0]));
  if (n == 0)
    osbf_raise(h, "Cannot allocate empty arrays");
  if (result.elems == NULL)
    osbf_raise(h, "Cannot allocate space for array of %u integers", n);
  result.elems[n-1] = ~0;
  result.next = result.elems;
  result.size = n;
  return result;
}

void oarray_grow(OARRAY *a, OSBF_HANDLER *h) {
  unsigned newsize;
  uint32_t *new_elems;
  
  if (a->elems == NULL)
    osbf_raise(h, "Growing closed array at %p", a);
  else {
    newsize = (unsigned)((double)(a->size) * 1.6);
    if (newsize <= a->size)
      newsize = a->size + 10;
    new_elems = realloc(a->elems, newsize);
    if (new_elems == NULL)
      osbf_raise(h, "Cannot enlarge array from %u to %u elements", a->size, newsize);
    a->next  = new_elems + (a->next - a->elems);
    a->elems = new_elems;
    a->size  = newsize;
    memset(a->next, 0, (newsize - (a->next - a->elems)) * sizeof(a->elems[0]));
    a->elems[newsize-1] = ~0;
  }
}

void oarray_free(OARRAY *a, OSBF_HANDLER *h) {
  if (a->elems == NULL)
    osbf_raise(h, "Closing already closed array at %p", a);
  else {
    free(a->elems);
    a->elems = a->next = NULL;
    a->size = 0;
  }
}
