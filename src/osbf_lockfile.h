#include "osbflib.h"

/* use a (system-dependent) facility to acquire exclusive access to a class file */

extern int osbf_lock_class   (CLASS_STRUCT *class, uint32_t start, uint32_t len);
extern int osbf_unlock_class (CLASS_STRUCT *class, uint32_t start, uint32_t len);
  /* class is class to be locked/unlocked, which includes file name 
     start and len are the region within the file to be locked (ignored
     by some locking methods) */
