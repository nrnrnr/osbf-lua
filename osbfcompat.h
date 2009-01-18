#include "osbflib.h"

#ifdef CRM114_COMPATIBILITY
typedef int32_t hval_t; /* signed */
#define H2_COMPAT_INDEX(WI) ((WI)-1)

#else
typedef uint32_t hval_t; /* signed */
#define H2_COMPAT_INDEX(WI) (WI)

#endif

