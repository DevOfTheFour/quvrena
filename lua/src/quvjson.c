/*
** Quvrena JSON module
**
** Public API: docs/STDLIB_JSON.md
*/

#define LUA_LIB

#include "lua.h"
#include "lauxlib.h"
#include "quvjson.h"

/*
** Private registry keys.
** Their addresses identify state-local registry entries.
*/
static const char json_tags_key = 0;
static const char json_null_key = 0;


/*
** Check argument count.
*/
static void json_checkarity (lua_State *L,
                            int minimum,
                            int maximum) {
  int count = lua_gettop(L);

  if (count < minimum || count > maximum)
    luaL_error(L, "invalid number of arguments");
}


/*
** Get the private table of JSON container tags.
**
** The table has weak keys:
**
**   [Lua table] = "array" | "object"
**
** Therefore, tagging a table does not prevent GC.
*/
static void json_pushtags (lua_State *L) {
  lua_rawgetp(L, LUA_REGISTRYINDEX, &json_tags_key);

  if (!lua_isnil(L, -1))
    return;

  lua_pop(L, 1);

  /* Create private tag map. */
  lua_newtable(L);

  /* Configure weak keys. */
  lua_newtable(L);
  lua_pushliteral(L, "k");
  lua_setfield(L, -2, "__mode");
  lua_setmetatable(L, -2);

  /* Store tag map in the registry. */
  lua_pushvalue(L, -1);
  lua_rawsetp(L, LUA_REGISTRYINDEX, &json_tags_key);
}


/*
** Mark an existing table, or create an empty one.
**
** No user metatable is changed.
*/
static int json_tag (lua_State *L, const char *kind) {
  json_checkarity(L, 0, 1);

  if (lua_gettop(L) == 0)
    lua_newtable(L);
  else {
    luaL_checktype(L, 1, LUA_TTABLE);
    lua_settop(L, 1);
  }

  json_pushtags(L);     /* [table, tags] */

  lua_pushvalue(L, 1);  /* key: original table */
  lua_pushstring(L, kind);

  lua_rawset(L, -3);    /* tags[table] = kind */

  lua_pop(L, 1);        /* remove tag map */

  return 1;             /* return original table */
}


/*
** json.array([table])
*/
static int json_array (lua_State *L) {
  return json_tag(L, "array");
}


/*
** json.object([table])
*/
static int json_object (lua_State *L) {
  return json_tag(L, "object");
}


/*
** json.kind(value)
**
** Return only an explicit tag.
** Never infer kind from table contents.
*/
static int json_kind (lua_State *L) {
  json_checkarity(L, 1, 1);

  if (!lua_istable(L, 1)) {
    lua_pushnil(L);
    return 1;
  }

  json_pushtags(L);     /* [value, tags] */

  lua_pushvalue(L, 1);
  lua_rawget(L, -2);    /* tags[value] */

  return 1;
}


/*
** Human-readable representation of JSON null.
*/
static int json_null_tostring (lua_State *L) {
  (void)L;

  lua_pushliteral(L, "json.null");
  return 1;
}


/*
** Push the unique JSON null singleton for this state.
**
** It is a full userdata, not nil or light userdata.
** The registry keeps the singleton alive.
*/
static void json_pushnull (lua_State *L) {
  lua_rawgetp(L, LUA_REGISTRYINDEX, &json_null_key);

  if (!lua_isnil(L, -1))
    return;

  lua_pop(L, 1);

  /* Allocate a private full userdata object. */
  (void)lua_newuserdatauv(L, 1, 0);

  /* Protected metatable for the singleton. */
  lua_newtable(L);

  lua_pushliteral(L, "std.json.null");
  lua_setfield(L, -2, "__name");

  lua_pushliteral(L, "std.json.null");
  lua_setfield(L, -2, "__metatable");

  lua_pushcfunction(L, json_null_tostring);
  lua_setfield(L, -2, "__tostring");

  lua_setmetatable(L, -2);

  /* Keep a strong registry reference. */
  lua_pushvalue(L, -1);
  lua_rawsetp(L, LUA_REGISTRYINDEX, &json_null_key);
}


static const luaL_Reg jsonlib[] = {
  {"array", json_array},
  {"object", json_object},
  {"kind", json_kind},
  {NULL, NULL}
};


/*
** Lua module entry point:
**
**   require("std.json")
*/
LUAMOD_API int luaopen_std_json(lua_State *L) {
  luaL_newlib(L, jsonlib);

  json_pushnull(L);
  lua_setfield(L, -2, "null");

  return 1;
}
