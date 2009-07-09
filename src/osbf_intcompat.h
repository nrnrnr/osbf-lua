#ifndef OSBF_INTCOMPAT
#define OSBF_INTCOMPAT

#include <float.h>
#include <inttypes.h>
#include <sys/types.h>

#ifndef uint64_t
#if _HAVE_LONGLONG || !defined(_NO_LONGLONG)
typedef unsigned long long uint64_t;
#else
#error Support for uint64_t is required
#endif
#endif

#endif
