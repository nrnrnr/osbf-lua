#include "lua.h"

#include "lauxlib.h"
#include "lualib.h"
#include "osbf-modname.h"

extern int lua_interp(int argc, char **argv, void (*)(lua_State*));
extern int OPENFUN(lua_State *);
extern int luaopen_fastmime(lua_State *);

static void open_osbf(lua_State *L) {
  int top = lua_gettop(L);
  lua_pushstring(L, QUOTE(OSBF_MODNAME)".core");
  (void)OPENFUN(L);
  lua_pushstring(L, "fastmime");
  (void)luaopen_fastmime(L);
  lua_settop(L, top);
}

int main(int argc, char **argv) {
  return lua_interp(argc, argv, open_osbf);
}

