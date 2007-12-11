#include <setjmp.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdio.h>


#include <lua.h>
#include <lauxlib.h>

#define osbf_error_handler lua_State

#include "osbferr.h"

const char *osbf_pcall(osbf_error_fun f, void *data) {
  (void)f, (void)data;
  return "Lua-aware code called osbf_pcall instead of using Lua protected calls";
}

int osbf_raise(OSBF_HANDLER *L, const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  lua_pushvfstring (L, fmt, args);
  va_end(args);
  return lua_error(L);
}

int osbf_raise_unless(int p, OSBF_HANDLER *L, const char *fmt, ...) {
  if (!p) {
    va_list args;
    va_start(args, fmt);
    lua_pushvfstring (L, fmt, args);
    va_end(args);
    return lua_error(L);
  }
  return 0;
}
