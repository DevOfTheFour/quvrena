/* Quvrena std.json - bounded RFC 8259 encoder */

#include <limits.h>
#include <locale.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "quvjson_internal.h"

#define JSON_DEFAULT_MAX_BYTES 67108864u
#define JSON_RECURSION_CEILING 256
#define JSON_PATH_CAPACITY 4096u
#define JSON_OUTPUT_CHUNK 4096u
#define JSON_SAFE_INTEGER 9007199254740991LL

#define JSON_KIND_NONE 0
#define JSON_KIND_ARRAY 1
#define JSON_KIND_OBJECT 2

typedef struct JsonWriter {
  lua_State *L;
  /* Lua-managed string fragments: safe while the C API uses the stack. */
  int chunks;  /* absolute stack index of the fragments table */
  lua_Integer chunk_count;
  char chunk[JSON_OUTPUT_CHUNK];
  size_t chunk_used;
  size_t bytes;
  size_t max_bytes;
  lua_Integer max_depth;
  lua_Integer max_values;
  lua_Integer values;
  lua_Integer depth;
  int pretty;
  int indent;
  int sort_keys;
  int ensure_ascii;
  int safe_integers;
  int active;  /* absolute Lua stack index of active recursion set */

  char path[JSON_PATH_CAPACITY];
  size_t path_length;
  int path_valid;

  const char *error_code;
  const char *error_message;
  char error_path[JSON_PATH_CAPACITY];
  size_t error_path_length;
  int error_path_valid;
} JsonWriter;

typedef struct JsonKey {
  const char *bytes;
  size_t length;
} JsonKey;


static int jw_fail (JsonWriter *w, const char *code, const char *message) {
  if (w->error_code == NULL) {
    w->error_code = code;
    w->error_message = message;
    w->error_path_valid = w->path_valid;
    w->error_path_length = w->path_length;
    if (w->path_valid)
      memcpy(w->error_path, w->path, w->path_length);
  }
  return 0;
}


/*
** Flush a complete or final output chunk into a Lua-managed table.
** This operation leaves the Lua stack exactly as it found it.
** It is safe to call inside lua_next and other recursive stack work.
*/
static void jw_flush (JsonWriter *w) {
  if (w->chunk_used != 0) {
    lua_pushlstring(w->L, w->chunk, w->chunk_used);
    lua_rawseti(w->L, w->chunks, ++w->chunk_count);
    w->chunk_used = 0;
  }
}


/* Check the output limit before recording any bytes. */
static int jw_add (JsonWriter *w, const char *data, size_t size) {
  if (size > w->max_bytes - w->bytes)
    return jw_fail(w, "size_limit", "maximum output bytes exceeded");
  w->bytes += size;
  while (size != 0) {
    size_t free_bytes = JSON_OUTPUT_CHUNK - w->chunk_used;
    size_t take = size < free_bytes ? size : free_bytes;
    memcpy(w->chunk + w->chunk_used, data, take);
    w->chunk_used += take;
    data += take;
    size -= take;
    if (w->chunk_used == JSON_OUTPUT_CHUNK)
      jw_flush(w);
  }
  return 1;
}


/*
** Assemble the final Lua string only after recursive encoding is finished.
** luaL_Buffer is safe here: its stack slot stays at the top; luaL_addvalue
** explicitly supports a single string value above that slot.
*/
static void jw_pushresult (JsonWriter *w) {
  lua_State *L = w->L;
  luaL_Buffer buffer;
  lua_Integer i;
  jw_flush(w);
  luaL_buffinit(L, &buffer);
  for (i = 1; i <= w->chunk_count; ++i) {
    lua_rawgeti(L, w->chunks, i);
    luaL_addvalue(&buffer);
  }
  luaL_pushresult(&buffer);
}


static int jw_char (JsonWriter *w, char c) {
  return jw_add(w, &c, 1);
}


static void jw_path_byte (JsonWriter *w, char c) {
  if (!w->path_valid) return;
  if (w->path_length >= JSON_PATH_CAPACITY - 1) {
    w->path_valid = 0;
    return;
  }
  w->path[w->path_length++] = c;
}


static void jw_path_key (JsonWriter *w, const char *key, size_t length) {
  size_t i;
  jw_path_byte(w, '/');
  for (i = 0; i < length && w->path_valid; i++) {
    if (key[i] == '~') {
      jw_path_byte(w, '~');
      jw_path_byte(w, '0');
    }
    else if (key[i] == '/') {
      jw_path_byte(w, '~');
      jw_path_byte(w, '1');
    }
    else jw_path_byte(w, key[i]);
  }
}


static void jw_path_index (JsonWriter *w, lua_Integer index) {
  char number[32];
  int len = snprintf(number, sizeof(number), "%llu",
                     (unsigned long long)(index - 1));
  if (len < 0 || (size_t)len >= sizeof(number)) {
    w->path_valid = 0;
    return;
  }
  jw_path_key(w, number, (size_t)len);
}


/* RFC 3629 UTF-8 validation and scalar width, without normalization. */
static int jw_utf8_width (const char *s, size_t remaining) {
  unsigned char a, b, c, d;
  if (!remaining) return 0;
  a = (unsigned char)s[0];
  if (a < 0x80) return 1;
  if (remaining < 2) return 0;
  b = (unsigned char)s[1];
  if (b < 0x80 || b > 0xbf) return 0;
  if (a >= 0xc2 && a <= 0xdf) return 2;
  if (remaining < 3) return 0;
  c = (unsigned char)s[2];
  if (c < 0x80 || c > 0xbf) return 0;
  if (a == 0xe0 && b >= 0xa0) return 3;
  if (a >= 0xe1 && a <= 0xec) return 3;
  if (a == 0xed && b <= 0x9f) return 3;
  if (a >= 0xee && a <= 0xef) return 3;
  if (remaining < 4) return 0;
  d = (unsigned char)s[3];
  if (d < 0x80 || d > 0xbf) return 0;
  if (a == 0xf0 && b >= 0x90) return 4;
  if (a >= 0xf1 && a <= 0xf3) return 4;
  if (a == 0xf4 && b <= 0x8f) return 4;
  return 0;
}


static unsigned jw_codepoint (const unsigned char *s, int width) {
  if (width == 2)
    return ((unsigned)(s[0] & 0x1f) << 6) | (unsigned)(s[1] & 0x3f);
  if (width == 3)
    return ((unsigned)(s[0] & 0x0f) << 12) |
           ((unsigned)(s[1] & 0x3f) << 6) | (unsigned)(s[2] & 0x3f);
  return ((unsigned)(s[0] & 0x07) << 18) |
         ((unsigned)(s[1] & 0x3f) << 12) |
         ((unsigned)(s[2] & 0x3f) << 6) | (unsigned)(s[3] & 0x3f);
}


static int jw_u4 (JsonWriter *w, unsigned cp) {
  static const char hex[] = "0123456789abcdef";
  char out[6];
  out[0] = '\\'; out[1] = 'u';
  out[2] = hex[(cp >> 12) & 15];
  out[3] = hex[(cp >> 8) & 15];
  out[4] = hex[(cp >> 4) & 15];
  out[5] = hex[cp & 15];
  return jw_add(w, out, sizeof(out));
}


static int jw_string (JsonWriter *w, const char *s, size_t length) {
  static const char hex[] = "0123456789abcdef";
  size_t i;
  if (!jw_char(w, '"')) return 0;
  for (i = 0; i < length;) {
    unsigned char c = (unsigned char)s[i];
    if (c < 0x20) {
      const char *esc = NULL;
      if (c == '\b') esc = "\\b";
      else if (c == '\f') esc = "\\f";
      else if (c == '\n') esc = "\\n";
      else if (c == '\r') esc = "\\r";
      else if (c == '\t') esc = "\\t";
      if (esc) {
        if (!jw_add(w, esc, 2)) return 0;
      }
      else {
        char out[6] = {'\\', 'u', '0', '0', hex[c >> 4], hex[c & 15]};
        if (!jw_add(w, out, sizeof(out))) return 0;
      }
      i++;
    }
    else if (c == '"' || c == '\\') {
      char out[2] = {'\\', (char)c};
      if (!jw_add(w, out, 2)) return 0;
      i++;
    }
    else if (c < 0x80) {
      if (!jw_char(w, (char)c)) return 0;
      i++;
    }
    else {
      int width = jw_utf8_width(s + i, length - i);
      if (!width)
        return jw_fail(w, "invalid_utf8", "invalid UTF-8 sequence");
      if (!w->ensure_ascii) {
        if (!jw_add(w, s + i, (size_t)width)) return 0;
      }
      else {
        unsigned cp = jw_codepoint((const unsigned char *)s + i, width);
        if (cp <= 0xffff) {
          if (!jw_u4(w, cp)) return 0;
        }
        else {
          unsigned u = cp - 0x10000;
          if (!jw_u4(w, 0xd800u + (u >> 10))) return 0;
          if (!jw_u4(w, 0xdc00u + (u & 0x3ffu))) return 0;
        }
      }
      i += (size_t)width;
    }
  }
  return jw_char(w, '"');
}


static int jw_number (JsonWriter *w, int index) {
  lua_State *L = w->L;
  size_t len, i;
  const char *text;
  char decimal;
  index = lua_absindex(L, index);
  if (lua_isinteger(L, index)) {
    lua_Integer n = lua_tointeger(L, index);
    if (w->safe_integers &&
        (n < -(lua_Integer)JSON_SAFE_INTEGER ||
         n > (lua_Integer)JSON_SAFE_INTEGER))
      return jw_fail(w, "invalid_number", "integer exceeds safe JSON range");
  }
  else if (!isfinite(lua_tonumber(L, index)))
    return jw_fail(w, "invalid_number", "non-finite number");

  /* Lua 5.5.1 already emits enough digits for float round-trip,
     and keeps the floating subtype via a decimal dot or exponent. */
  lua_pushvalue(L, index);
  text = lua_tolstring(L, -1, &len);
  decimal = localeconv()->decimal_point[0];
  if (decimal == '\0') decimal = '.';
  for (i = 0; i < len; i++) {
    char c = text[i];
    if (c == decimal && decimal != '.') c = '.';
    if (!jw_char(w, c)) {
      lua_pop(L, 1);
      return 0;
    }
  }
  lua_pop(L, 1);
  return 1;
}


static int jw_indent (JsonWriter *w, lua_Integer depth) {
  static const char spaces[] = "        ";
  lua_Integer i;
  if (!w->pretty) return 1;
  if (!jw_char(w, '\n')) return 0;
  for (i = 0; i < depth; i++) {
    if (!jw_add(w, spaces, (size_t)w->indent)) return 0;
  }
  return 1;
}


static int jw_value (JsonWriter *w, int index);


static int jw_array (JsonWriter *w, int index, lua_Integer count) {
  lua_Integer i;
  lua_State *L = w->L;
  if (!jw_char(w, '[')) return 0;
  for (i = 1; i <= count; i++) {
    size_t saved = w->path_length;
    int valid = w->path_valid;
    if (i > 1 && !jw_char(w, ',')) return 0;
    if (!jw_indent(w, w->depth)) return 0;
    lua_rawgeti(L, index, i);
    jw_path_index(w, i);
    if (!jw_value(w, -1)) return 0;
    w->path_length = saved;
    w->path_valid = valid;
    lua_pop(L, 1);
  }
  if (count > 0 && !jw_indent(w, w->depth - 1)) return 0;
  return jw_char(w, ']');
}


static int jw_pair (JsonWriter *w, int value_index,
                   const char *key, size_t keylen, int first) {
  size_t saved = w->path_length;
  int valid = w->path_valid;
  value_index = lua_absindex(w->L, value_index);
  if (!first && !jw_char(w, ',')) return 0;
  if (!jw_indent(w, w->depth)) return 0;
  jw_path_key(w, key, keylen);
  if (!jw_string(w, key, keylen)) return 0;
  if (!jw_char(w, ':')) return 0;
  if (w->pretty && !jw_char(w, ' ')) return 0;
  if (!jw_value(w, value_index)) return 0;
  w->path_length = saved;
  w->path_valid = valid;
  return 1;
}


static int jw_object_unsorted (JsonWriter *w, int index, size_t count) {
  lua_State *L = w->L;
  int first = 1;
  if (!jw_char(w, '{')) return 0;
  lua_pushnil(L);
  while (lua_next(L, index) != 0) {
    size_t keylen;
    const char *key = lua_tolstring(L, -2, &keylen);
    if (!jw_pair(w, -1, key, keylen, first)) return 0;
    first = 0;
    lua_pop(L, 1);
  }
  if (count > 0 && !jw_indent(w, w->depth - 1)) return 0;
  return jw_char(w, '}');
}


static int jw_key_compare (const void *a, const void *b) {
  const JsonKey *x = (const JsonKey *)a;
  const JsonKey *y = (const JsonKey *)b;
  size_t n = x->length < y->length ? x->length : y->length;
  int c = memcmp(x->bytes, y->bytes, n);
  if (c != 0) return c;
  return (x->length > y->length) - (x->length < y->length);
}


static int jw_object_sorted (JsonWriter *w, int index, size_t count) {
  lua_State *L = w->L;
  JsonKey *keys;
  size_t i = 0;
  if (!jw_char(w, '{')) return 0;
  if (count == 0) return jw_char(w, '}');
  if (count > (size_t)-1 / sizeof(JsonKey))
    return jw_fail(w, "value_limit", "too many JSON object members");
  /* Lua-owned temporary storage: safe across Lua allocations/longjmps. */
  keys = (JsonKey *)lua_newuserdatauv(L, count * sizeof(JsonKey), 0);
  lua_pushnil(L);
  while (lua_next(L, index) != 0) {
    keys[i].bytes = lua_tolstring(L, -2, &keys[i].length);
    i++;
    lua_pop(L, 1);
  }
  qsort(keys, count, sizeof(JsonKey), jw_key_compare);
  for (i = 0; i < count; i++) {
    lua_pushlstring(L, keys[i].bytes, keys[i].length);
    lua_rawget(L, index);
    if (!jw_pair(w, -1, keys[i].bytes, keys[i].length, i == 0))
      return 0;
    lua_pop(L, 1);
  }
  lua_pop(L, 1); /* sorted key buffer */
  if (!jw_indent(w, w->depth - 1)) return 0;
  return jw_char(w, '}');
}


static int jw_table (JsonWriter *w, int index) {
  lua_State *L = w->L;
  size_t count = 0;
  lua_Integer max_index = 0;
  int strings = 0, integers = 0;
  int kind;
  index = lua_absindex(L, index);
  if (w->depth >= w->max_depth || w->depth >= JSON_RECURSION_CEILING)
    return jw_fail(w, "depth_limit", "maximum container depth exceeded");
  luaL_checkstack(L, 12, "JSON encoder stack");

  lua_pushvalue(L, index);
  lua_rawget(L, w->active);
  if (lua_toboolean(L, -1)) {
    lua_pop(L, 1);
    return jw_fail(w, "circular_reference", "circular table reference");
  }
  lua_pop(L, 1);

  kind = quvjson_getkind(L, index);
  /* Inspect all raw keys once; do not use #table for sparse data. */
  lua_pushnil(L);
  while (lua_next(L, index) != 0) {
    int type = lua_type(L, -2);
    count++;
    if (count > (size_t)(w->max_values - w->values)) {
      lua_pop(L, 1);
      return jw_fail(w, "value_limit", "maximum JSON values exceeded");
    }
    if (type == LUA_TSTRING) strings = 1;
    else if (type == LUA_TNUMBER && lua_isinteger(L, -2) &&
             lua_tointeger(L, -2) > 0) {
      lua_Integer k = lua_tointeger(L, -2);
      integers = 1;
      if (k > max_index) max_index = k;
    }
    else {
      lua_pop(L, 1);
      return jw_fail(w, "invalid_table", "unsupported JSON table key");
    }
    lua_pop(L, 1);
  }

  if (kind == JSON_KIND_NONE) {
    if (count == 0 || (strings && !integers)) kind = JSON_KIND_OBJECT;
    else if (integers && !strings) kind = JSON_KIND_ARRAY;
    else return jw_fail(w, "invalid_table", "mixed array and object keys");
  }
  if ((kind == JSON_KIND_ARRAY &&
       (strings || (lua_Integer)count != max_index)) ||
      (kind == JSON_KIND_OBJECT && integers))
    return jw_fail(w, "invalid_table", "table does not match JSON container kind");

  lua_pushvalue(L, index);
  lua_pushboolean(L, 1);
  lua_rawset(L, w->active);
  w->depth++;
  if ((kind == JSON_KIND_ARRAY &&
       !jw_array(w, index, (lua_Integer)count)) ||
      (kind == JSON_KIND_OBJECT &&
       !(w->sort_keys ? jw_object_sorted(w, index, count)
                      : jw_object_unsorted(w, index, count))))
    return 0;
  w->depth--;
  lua_pushvalue(L, index);
  lua_pushnil(L);
  lua_rawset(L, w->active);
  return 1;
}


static int jw_value (JsonWriter *w, int index) {
  lua_State *L = w->L;
  int type;
  index = lua_absindex(L, index);
  if (w->values >= w->max_values)
    return jw_fail(w, "value_limit", "maximum JSON values exceeded");
  w->values++;
  type = lua_type(L, index);
  switch (type) {
    case LUA_TBOOLEAN:
      return jw_add(w, lua_toboolean(L, index) ? "true" : "false",
                    lua_toboolean(L, index) ? 4 : 5);
    case LUA_TNUMBER:
      return jw_number(w, index);
    case LUA_TSTRING: {
      size_t len;
      const char *s = lua_tolstring(L, index, &len);
      return jw_string(w, s, len);
    }
    case LUA_TTABLE:
      return jw_table(w, index);
    case LUA_TUSERDATA:
      if (quvjson_isnull(L, index)) return jw_add(w, "null", 4);
      return jw_fail(w, "unsupported_type", "unsupported userdata value");
    default:
      return jw_fail(w, "unsupported_type", "unsupported Lua value");
  }
}


static int jw_streq (const char *s, size_t len, const char *expected) {
  size_t n = strlen(expected);
  return len == n && memcmp(s, expected, n) == 0;
}


static void jw_options (JsonWriter *w) {
  lua_State *L = w->L;
  if (lua_isnoneornil(L, 2)) return;
  luaL_checktype(L, 2, LUA_TTABLE);
  lua_pushnil(L);
  while (lua_next(L, 2) != 0) {
    size_t len;
    const char *key;
    lua_Integer n;
    int valtype = lua_type(L, -1);
    if (lua_type(L, -2) != LUA_TSTRING)
      luaL_argerror(L, 2, "option names must be strings");
    key = lua_tolstring(L, -2, &len);
    if (jw_streq(key, len, "pretty") ||
        jw_streq(key, len, "sort_keys") ||
        jw_streq(key, len, "ensure_ascii") ||
        jw_streq(key, len, "safe_integers")) {
      if (valtype != LUA_TBOOLEAN)
        luaL_argerror(L, 2, "expected boolean option value");
      if (jw_streq(key, len, "pretty")) w->pretty = lua_toboolean(L, -1);
      else if (jw_streq(key, len, "sort_keys")) w->sort_keys = lua_toboolean(L, -1);
      else if (jw_streq(key, len, "ensure_ascii")) w->ensure_ascii = lua_toboolean(L, -1);
      else w->safe_integers = lua_toboolean(L, -1);
    }
    else if (jw_streq(key, len, "indent") ||
             jw_streq(key, len, "max_depth") ||
             jw_streq(key, len, "max_values") ||
             jw_streq(key, len, "max_bytes")) {
      if (!lua_isinteger(L, -1))
        luaL_argerror(L, 2, "integer option value expected");
      n = lua_tointeger(L, -1);
      if (jw_streq(key, len, "indent")) {
        if (n < 0 || n > 8)
          luaL_argerror(L, 2, "indent must be in 0..8");
        w->indent = (int)n;
      }
      else {
        if (n <= 0) luaL_argerror(L, 2, "resource limits must be positive integers");
        if (jw_streq(key, len, "max_depth")) {
          if (n > JSON_RECURSION_CEILING)
            luaL_argerror(L, 2, "max_depth must be at most 256");
          w->max_depth = n;
        }
        else if (jw_streq(key, len, "max_values")) w->max_values = n;
        else w->max_bytes = (size_t)n;
      }
    }
    else luaL_argerror(L, 2, "unknown JSON encode option");
    lua_pop(L, 1);
  }
}


static int jw_error_tostring (lua_State *L) {
  const char *message;
  const char *path;
  lua_getfield(L, 1, "message");
  message = lua_tostring(L, -1);
  lua_getfield(L, 1, "path");
  path = lua_tostring(L, -1);
  if (path == NULL || path[0] == '\0')
    lua_pushfstring(L, "json.encode: %s", message == NULL ? "error" : message);
  else
    lua_pushfstring(L, "json.encode: %s at %s",
                    message == NULL ? "error" : message, path);
  return 1;
}


static int jw_pusherror (JsonWriter *w) {
  lua_State *L = w->L;
  lua_settop(L, 2); /* discard scratch stack + buffer */
  lua_pushnil(L);
  lua_newtable(L);
  lua_pushstring(L, w->error_code);
  lua_setfield(L, -2, "code");
  lua_pushstring(L, w->error_message);
  lua_setfield(L, -2, "message");
  if (w->error_path_valid) {
    lua_pushlstring(L, w->error_path, w->error_path_length);
    lua_setfield(L, -2, "path");
  }
  if (luaL_newmetatable(L, "quvrena.std.json.encode.error")) {
    lua_pushcfunction(L, jw_error_tostring);
    lua_setfield(L, -2, "__tostring");
    lua_pushliteral(L, "std.json.error");
    lua_setfield(L, -2, "__metatable");
  }
  lua_setmetatable(L, -2);
  return 2;
}


/* Lua: json.encode(value[, options]) -> string | nil, error */
int quvjson_encode (lua_State *L) {
  JsonWriter w;
  memset(&w, 0, sizeof(w));
  if (lua_gettop(L) > 2)
    return luaL_argerror(L, 3, "too many arguments");
  luaL_checkany(L, 1); /* root nil is a data error; absence is a call error */
  w.L = L;
  w.max_bytes = JSON_DEFAULT_MAX_BYTES;
  w.max_depth = 128;
  w.max_values = 1000000;
  w.indent = 2;
  w.path_valid = 1;
  jw_options(&w);
  lua_settop(L, 2);
  lua_newtable(L);
  w.active = lua_absindex(L, -1);
  lua_newtable(L);
  w.chunks = lua_absindex(L, -1);
  if (!jw_value(&w, 1)) return jw_pusherror(&w);
  jw_pushresult(&w);
  return 1;
}
