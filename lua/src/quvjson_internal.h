#ifndef QUVRENA_JSON_INTERNAL_H
#define QUVRENA_JSON_INTERNAL_H

#include "lua.h"

/* Internal-only helpers shared by Foundation, decoder and encoder. */
void quvjson_pushnull(lua_State *L);
void quvjson_tagtable(lua_State *L, int index, const char *kind);
int quvjson_isnull(lua_State *L, int index);
/* Returns 0=unmarked, 1=array, 2=object. */
int quvjson_getkind(lua_State *L, int index);

int quvjson_decode(lua_State *L);
int quvjson_encode(lua_State *L);

#endif /* QUVRENA_JSON_INTERNAL_H */
