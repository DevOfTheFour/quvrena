#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

int main(void)
{
    lua_State *L = luaL_newstate();

    if (L == NULL)
        return 1;

    luaL_openlibs(L);

    int status = luaL_dostring(L, "return 6 * 7");

    int success =
        status == LUA_OK &&
        lua_isinteger(L, -1) &&
        lua_tointeger(L, -1) == 42;

    lua_close(L);

    return success ? 0 : 1;
}
