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

    int extensions_status = luaL_dostring(L,
        "local t = {1, 2, 3}; "
        "table.clear(t); "
        "assert(next(t) == nil)"
    );

    if (extensions_status != LUA_OK) {
        lua_close(L);
        return 1;
    }

    int string_status = luaL_dostring(L,
        "local s, n = string.replace('a-a', 'a', 'b'); "
        "assert(s == 'b-b' and n == 2); "
        "assert(string.trim(' hello ') == 'hello')"
    );

    if (string_status != LUA_OK) {
        lua_close(L);
        return 1;
    }

    if (luaL_dostring(L,
        "assert(math.clamp(15, 0, 10) == 10); "
        "assert(math.round(-2.5) == -3); "
        "assert(math.sign(-5) == -1); "
        "assert(math.lerp(0, 100, 0.5) == 50); "
        "assert(math.mapRange(5, 0, 10, 0, 100) == 50)"
    ) != LUA_OK) {
        success = 0;
    }

    lua_close(L);

    return success ? 0 : 1;
}
