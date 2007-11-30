#include "lua.h"

#include "lauxlib.h"
#include "lualib.h"

extern int lua_interp(int argc, char **argv, void (*)(lua_State*));
extern int luaopen_osbf3_core(lua_State *);

static void open_osbf(lua_State *L) {
  int top = lua_gettop(L);
  lua_pushstring(L, "osbf3.core");
  (void)luaopen_osbf3_core(L);
  lua_settop(L, top);
}

int main(int argc, char **argv) {
  return lua_interp(argc, argv, open_osbf);
}

