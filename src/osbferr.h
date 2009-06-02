/*
 * See Copyright Notice in osbflib.h
 */

#ifndef OSBF_ERR
#define OSBF_ERR 1

/* error handling for OSBF */

typedef struct osbf_error_handler OSBF_HANDLER;  /* abstract type */
int osbf_raise(OSBF_HANDLER *h, const char *fmt, ...);
  /* like fprintf, but raises an error that is caught by osbf_pcall.
     Return type is int so it can be used in int-returning functions
     to avoid compiler warnings. */

int osbf_raise_unless(int p, OSBF_HANDLER *h, const char *fmt, ...);
  /* a safe version of assert(p): calls osbf_raise unless p is nonzero */
  

typedef void (*osbf_error_fun)(OSBF_HANDLER *h, void *data);

const char *osbf_pcall(osbf_error_fun f, void *data);
/* creates a handler h and calls f(h, data). 
   If f terminates normally, osbf_pcall returns NULL.
   If f terminates by a call to osbf_raise, returns a
   pointer to an error message.  The client must call free()
   on the pointer to reclaim the memory. */


/* This interface is intended to have multiple potential implementations.
   If the library is linked to Lua, OSBF_HANDLER will be equivalent to lua_State;
   osbf_raise will be equivalent to luaL_error; and osbf_pcall will not be
   implemented.  */


#endif
