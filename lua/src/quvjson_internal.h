#ifndef QUVRENA_JSON_INTERNAL_H
#define QUVRENA_JSON_INTERNAL_H

#include "lua.h"

/* Internal helpers shared by the JSON module components. */
void quvjson_pushnull(lua_State *L);
void quvjson_tagtable(lua_State *L, int index, const char *kind);
int quvjson_decode(lua_State *L);

#endif
