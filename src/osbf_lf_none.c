#include "osbf_lockfile.h"

int osbf_lock_class(CLASS_STRUCT *class, uint32_t start, uint32_t len) {
  (void)class, (void)start, (void)len; /* keep compiler quiet */
  return 0;
}

int osbf_unlock_class (CLASS_STRUCT *class, uint32_t start, uint32_t len) {
  (void)class, (void)start, (void)len; /* keep compiler quiet */
  return 0;
}
