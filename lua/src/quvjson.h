#ifndef QUVRENA_JSON_H
#define QUVRENA_JSON_H

#include "lua.h"

/*
** Quvrena native JSON module.
**
** Public Lua name: std.json
** Implemented API follows docs/STDLIB_JSON.md.
*/
LUAMOD_API int luaopen_std_json(lua_State *L);

#endif /* QUVRENA_JSON_H */
