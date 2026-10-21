/* Quvrena std.json - strict RFC 8259 decoder */

#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "quvjson_internal.h"

#define JSON_DEFAULT_MAX_BYTES 67108864u
#define JSON_PATH_CAPACITY 4096u
/* C-recursive parser: independent safety ceiling, documented in API. */
#define JSON_RECURSION_CEILING 256

typedef struct JsonParser {
  lua_State *L;
  const char *text;
  size_t length;
  size_t pos;
  lua_Integer max_depth;
  lua_Integer max_values;
  lua_Integer depth;
  lua_Integer values;
  size_t max_bytes;
  int duplicate_last;
  int overflow_float;

  char path[JSON_PATH_CAPACITY];
  size_t path_length;
  int path_valid;

  const char *error_code;
  const char *error_message;
  size_t error_pos;
  char error_path[JSON_PATH_CAPACITY];
  size_t error_path_length;
  int error_path_valid;
} JsonParser;


static int json_fail(JsonParser *p, const char *code,
                     const char *message, size_t pos) {
  if (p->error_code == NULL) {
    p->error_code = code;
    p->error_message = message;
    p->error_pos = pos;
    p->error_path_valid = p->path_valid;
    p->error_path_length = p->path_length;
    if (p->path_valid)
      memcpy(p->error_path, p->path, p->path_length);
  }
  return 0;
}


static void json_ws(JsonParser *p) {
  while (p->pos < p->length) {
    char c = p->text[p->pos];
    if (c != ' ' && c != '\n' && c != '\r' && c != '\t')
      break;
    p->pos++;
  }
}


static void json_path_append_byte(JsonParser *p, char c) {
  if (!p->path_valid) return;
  if (p->path_length >= JSON_PATH_CAPACITY - 1) {
    p->path_valid = 0;
    return;
  }
  p->path[p->path_length++] = c;
}


static void json_path_key(JsonParser *p, const char *key, size_t length) {
  size_t i;
  json_path_append_byte(p, '/');
  for (i = 0; i < length && p->path_valid; i++) {
    if (key[i] == '~') {
      json_path_append_byte(p, '~');
      json_path_append_byte(p, '0');
    }
    else if (key[i] == '/') {
      json_path_append_byte(p, '~');
      json_path_append_byte(p, '1');
    }
    else
      json_path_append_byte(p, key[i]);
  }
}


static void json_path_index(JsonParser *p, lua_Integer index) {
  char number[32];
  int n = snprintf(number, sizeof(number), "%llu",
                   (unsigned long long)(index - 1));
  if (n < 0 || (size_t)n >= sizeof(number)) {
    p->path_valid = 0;
    return;
  }
  json_path_key(p, number, (size_t)n);
}


/* Return UTF-8 sequence width, or 0 for malformed UTF-8. */
static int json_utf8_width(const char *s, size_t remaining) {
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
  if (a == 0xed && b <= 0x9f) return 3; /* no surrogates */
  if (a >= 0xee && a <= 0xef) return 3;
  if (remaining < 4) return 0;
  d = (unsigned char)s[3];
  if (d < 0x80 || d > 0xbf) return 0;
  if (a == 0xf0 && b >= 0x90) return 4;
  if (a >= 0xf1 && a <= 0xf3) return 4;
  if (a == 0xf4 && b <= 0x8f) return 4;
  return 0;
}


static int json_hex(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}


static int json_u4(JsonParser *p, unsigned *result) {
  int i;
  unsigned value = 0;
  for (i = 0; i < 4; i++) {
    int digit;
    if (p->pos >= p->length)
      return json_fail(p, "syntax", "incomplete Unicode escape", p->pos);
    digit = json_hex(p->text[p->pos]);
    if (digit < 0)
      return json_fail(p, "syntax", "invalid Unicode escape", p->pos);
    value = value * 16 + (unsigned)digit;
    p->pos++;
  }
  *result = value;
  return 1;
}


static void json_addcodepoint(luaL_Buffer *b, unsigned cp) {
  char bytes[4];
  int n;
  if (cp <= 0x7f) {
    bytes[0] = (char)cp;
    n = 1;
  }
  else if (cp <= 0x7ff) {
    bytes[0] = (char)(0xc0 | (cp >> 6));
    bytes[1] = (char)(0x80 | (cp & 0x3f));
    n = 2;
  }
  else if (cp <= 0xffff) {
    bytes[0] = (char)(0xe0 | (cp >> 12));
    bytes[1] = (char)(0x80 | ((cp >> 6) & 0x3f));
    bytes[2] = (char)(0x80 | (cp & 0x3f));
    n = 3;
  }
  else {
    bytes[0] = (char)(0xf0 | (cp >> 18));
    bytes[1] = (char)(0x80 | ((cp >> 12) & 0x3f));
    bytes[2] = (char)(0x80 | ((cp >> 6) & 0x3f));
    bytes[3] = (char)(0x80 | (cp & 0x3f));
    n = 4;
  }
  luaL_addlstring(b, bytes, (size_t)n);
}


/* Parse one JSON string; push decoded Lua string on success. */
static int json_string(JsonParser *p) {
  luaL_Buffer b;
  if (p->pos >= p->length || p->text[p->pos] != '"')
    return json_fail(p, "syntax", "expected string", p->pos);
  p->pos++;
  luaL_buffinit(p->L, &b);
  while (p->pos < p->length) {
    size_t at = p->pos;
    unsigned char c = (unsigned char)p->text[p->pos++];
    if (c == '"') {
      luaL_pushresult(&b);
      return 1;
    }
    if (c < 0x20)
      return json_fail(p, "syntax", "unescaped control character", at);
    if (c == '\\') {
      unsigned cp;
      if (p->pos >= p->length)
        return json_fail(p, "syntax", "incomplete escape", p->pos);
      c = (unsigned char)p->text[p->pos++];
      switch (c) {
        case '"': luaL_addchar(&b, '"'); break;
        case '\\': luaL_addchar(&b, '\\'); break;
        case '/': luaL_addchar(&b, '/'); break;
        case 'b': luaL_addchar(&b, '\b'); break;
        case 'f': luaL_addchar(&b, '\f'); break;
        case 'n': luaL_addchar(&b, '\n'); break;
        case 'r': luaL_addchar(&b, '\r'); break;
        case 't': luaL_addchar(&b, '\t'); break;
        case 'u':
          if (!json_u4(p, &cp)) return 0;
          if (cp >= 0xd800 && cp <= 0xdbff) {
            unsigned low;
            if (p->length - p->pos < 2 ||
                p->text[p->pos] != '\\' ||
                p->text[p->pos + 1] != 'u')
              return json_fail(p, "invalid_utf8", "unpaired high surrogate", at);
            p->pos += 2;
            if (!json_u4(p, &low)) return 0;
            if (low < 0xdc00 || low > 0xdfff)
              return json_fail(p, "invalid_utf8", "unpaired high surrogate", at);
            cp = 0x10000 + ((cp - 0xd800) << 10) + (low - 0xdc00);
          }
          else if (cp >= 0xdc00 && cp <= 0xdfff)
            return json_fail(p, "invalid_utf8", "unpaired low surrogate", at);
          json_addcodepoint(&b, cp);
          break;
        default:
          return json_fail(p, "syntax", "invalid string escape", p->pos - 1);
      }
    }
    else if (c >= 0x80) {
      int width = json_utf8_width(p->text + at, p->length - at);
      if (!width)
        return json_fail(p, "invalid_utf8", "invalid UTF-8 sequence", at);
      luaL_addlstring(&b, p->text + at, (size_t)width);
      p->pos = at + (size_t)width;
    }
    else
      luaL_addchar(&b, (char)c);
  }
  return json_fail(p, "syntax", "unterminated string", p->pos);
}


static int json_digit(char c) {
  return c >= '0' && c <= '9';
}


/* Strict JSON grammar, then exact integer or finite Lua float conversion. */
static int json_number(JsonParser *p) {
  size_t start = p->pos, digit_start, end, i;
  int negative = 0, floating = 0, nonzero = 0, overflow = 0;
  lua_Unsigned magnitude = 0;
  lua_Unsigned limit;
  lua_State *L = p->L;
  if (p->text[p->pos] == '-') {
    negative = 1;
    p->pos++;
  }
  digit_start = p->pos;
  if (p->pos == p->length)
    return json_fail(p, "syntax", "expected digit", p->pos);
  if (p->text[p->pos] == '0') {
    p->pos++;
    if (p->pos < p->length && json_digit(p->text[p->pos]))
      return json_fail(p, "syntax", "leading zero in number", p->pos);
  }
  else {
    if (p->text[p->pos] < '1' || p->text[p->pos] > '9')
      return json_fail(p, "syntax", "expected digit", p->pos);
    do { p->pos++; }
    while (p->pos < p->length && json_digit(p->text[p->pos]));
  }
  for (i = digit_start; i < p->pos; i++)
    if (p->text[i] != '0') nonzero = 1;
  end = p->pos; /* end of integral digits */
  if (p->pos < p->length && p->text[p->pos] == '.') {
    floating = 1;
    p->pos++;
    if (p->pos == p->length || !json_digit(p->text[p->pos]))
      return json_fail(p, "syntax", "expected fractional digit", p->pos);
    do {
      if (p->text[p->pos] != '0') nonzero = 1;
      p->pos++;
    } while (p->pos < p->length && json_digit(p->text[p->pos]));
  }
  if (p->pos < p->length &&
      (p->text[p->pos] == 'e' || p->text[p->pos] == 'E')) {
    floating = 1;
    p->pos++;
    if (p->pos < p->length &&
        (p->text[p->pos] == '+' || p->text[p->pos] == '-'))
      p->pos++;
    if (p->pos == p->length || !json_digit(p->text[p->pos]))
      return json_fail(p, "syntax", "expected exponent digit", p->pos);
    do { p->pos++; }
    while (p->pos < p->length && json_digit(p->text[p->pos]));
  }
  if (!floating && negative && end - digit_start == 1 &&
      p->text[digit_start] == '0') {
    lua_pushnumber(L, -(lua_Number)0.0);
    return 1;
  }
  if (!floating) {
    limit = (lua_Unsigned)LUA_MAXINTEGER + (negative ? 1u : 0u);
    for (i = digit_start; i < end; i++) {
      unsigned digit = (unsigned)(p->text[i] - '0');
      if (magnitude > (limit - digit) / 10u) {
        overflow = 1;
        break;
      }
      magnitude = magnitude * 10u + digit;
    }
    if (!overflow) {
      if (negative) {
        if (magnitude == (lua_Unsigned)LUA_MAXINTEGER + 1u)
          lua_pushinteger(L, LUA_MININTEGER);
        else
          lua_pushinteger(L, -(lua_Integer)magnitude);
      }
      else
        lua_pushinteger(L, (lua_Integer)magnitude);
      return 1;
    }
    if (!p->overflow_float)
      return json_fail(p, "invalid_number", "integer overflow", start);
  }
  /* Lua's locale-aware numeric reader accepts a JSON decimal literal
     after syntax has already been strictly validated above. */
  {
    size_t n = p->pos - start;
    lua_Number number;
    const char *temp = lua_pushlstring(L, p->text + start, n);
    if (lua_stringtonumber(L, temp) != n + 1) {
      lua_pop(L, 1); /* temporary text */
      return json_fail(p, "invalid_number", "unrepresentable number", start);
    }
    lua_remove(L, -2); /* temporary text, keep parsed number */
    number = lua_tonumber(L, -1);
    if (!isfinite(number) || (number == 0 && nonzero)) {
      lua_pop(L, 1);
      return json_fail(p, "invalid_number", "number overflow or underflow", start);
    }
    if (lua_isinteger(L, -1)) {
      lua_pop(L, 1);
      return json_fail(p, "invalid_number", "expected floating-point number", start);
    }
    return 1;
  }
}


static int json_value(JsonParser *p);


static int json_array(JsonParser *p) {
  lua_Integer index = 1;
  lua_State *L = p->L;
  int table;
  if (p->depth >= p->max_depth || p->depth >= JSON_RECURSION_CEILING)
    return json_fail(p, "depth_limit", "maximum container depth exceeded", p->pos);
  p->depth++;
  p->pos++; /* '[' */
  luaL_checkstack(L, 8, "JSON decoder stack");
  lua_newtable(L);
  table = lua_absindex(L, -1);
  quvjson_tagtable(L, table, "array");
  json_ws(p);
  if (p->pos < p->length && p->text[p->pos] == ']') {
    p->pos++;
    p->depth--;
    return 1;
  }
  for (;;) {
    size_t saved = p->path_length;
    int was_valid = p->path_valid;
    json_path_index(p, index);
    if (!json_value(p)) return 0;
    p->path_length = saved;
    p->path_valid = was_valid;
    lua_rawseti(L, table, index);
    index++;
    json_ws(p);
    if (p->pos < p->length && p->text[p->pos] == ']') {
      p->pos++;
      p->depth--;
      return 1;
    }
    if (p->pos >= p->length || p->text[p->pos] != ',')
      return json_fail(p, "syntax", "expected ',' or ']'", p->pos);
    p->pos++;
    json_ws(p);
    if (p->pos < p->length && p->text[p->pos] == ']')
      return json_fail(p, "syntax", "trailing comma in array", p->pos);
  }
}


static int json_object(JsonParser *p) {
  lua_State *L = p->L;
  int table;
  if (p->depth >= p->max_depth || p->depth >= JSON_RECURSION_CEILING)
    return json_fail(p, "depth_limit", "maximum container depth exceeded", p->pos);
  p->depth++;
  p->pos++; /* '{' */
  luaL_checkstack(L, 8, "JSON decoder stack");
  lua_newtable(L);
  table = lua_absindex(L, -1);
  quvjson_tagtable(L, table, "object");
  json_ws(p);
  if (p->pos < p->length && p->text[p->pos] == '}') {
    p->pos++;
    p->depth--;
    return 1;
  }
  for (;;) {
    size_t saved, member_start;
    int was_valid;
    size_t keylen;
    const char *key;
    if (p->pos >= p->length || p->text[p->pos] != '"')
      return json_fail(p, "syntax", "expected object member name", p->pos);
    member_start = p->pos;
    if (!json_string(p)) return 0;  /* push key */
    key = lua_tolstring(L, -1, &keylen);
    saved = p->path_length;
    was_valid = p->path_valid;
    json_path_key(p, key, keylen);
    lua_pushvalue(L, -1);
    lua_rawget(L, table);
    if (!lua_isnil(L, -1) && !p->duplicate_last) {
      lua_pop(L, 1);
      return json_fail(p, "duplicate_key", "duplicate object member", member_start);
    }
    lua_pop(L, 1);
    json_ws(p);
    if (p->pos >= p->length || p->text[p->pos] != ':')
      return json_fail(p, "syntax", "expected ':' after member name", p->pos);
    p->pos++;
    if (!json_value(p)) return 0;  /* push value */
    lua_rawset(L, table);  /* table[key] = value */
    p->path_length = saved;
    p->path_valid = was_valid;
    json_ws(p);
    if (p->pos < p->length && p->text[p->pos] == '}') {
      p->pos++;
      p->depth--;
      return 1;
    }
    if (p->pos >= p->length || p->text[p->pos] != ',')
      return json_fail(p, "syntax", "expected ',' or '}'", p->pos);
    p->pos++;
    json_ws(p);
    if (p->pos < p->length && p->text[p->pos] == '}')
      return json_fail(p, "syntax", "trailing comma in object", p->pos);
  }
}


static int json_literal(JsonParser *p, const char *literal, int kind) {
  size_t n = strlen(literal);
  if (p->length - p->pos < n ||
      memcmp(p->text + p->pos, literal, n) != 0)
    return json_fail(p, "syntax", "invalid JSON literal", p->pos);
  p->pos += n;
  if (kind == 0) quvjson_pushnull(p->L);
  else lua_pushboolean(p->L, kind == 2);
  return 1;
}


static int json_value(JsonParser *p) {
  char c;
  json_ws(p);
  if (p->values >= p->max_values)
    return json_fail(p, "value_limit", "maximum JSON values exceeded", p->pos);
  p->values++;
  if (p->pos >= p->length)
    return json_fail(p, "syntax", "expected JSON value", p->pos);
  c = p->text[p->pos];
  switch (c) {
    case '{': return json_object(p);
    case '[': return json_array(p);
    case '"': return json_string(p);
    case 'n': return json_literal(p, "null", 0);
    case 'f': return json_literal(p, "false", 1);
    case 't': return json_literal(p, "true", 2);
    default:
      if (c == '-' || json_digit(c)) return json_number(p);
      return json_fail(p, "syntax", "unexpected token", p->pos);
  }
}


static int json_streq(const char *s, size_t length, const char *literal) {
  size_t literal_length = strlen(literal);
  return length == literal_length && memcmp(s, literal, length) == 0;
}


static void json_decode_options(lua_State *L, JsonParser *p) {
  if (lua_isnoneornil(L, 2)) return;
  luaL_checktype(L, 2, LUA_TTABLE);
  lua_pushnil(L);
  while (lua_next(L, 2)) {
    const char *name;
    size_t name_length;
    if (lua_type(L, -2) != LUA_TSTRING)
      luaL_argerror(L, 2, "option names must be strings");
    name = lua_tolstring(L, -2, &name_length);
    if (json_streq(name, name_length, "duplicate_keys") ||
        json_streq(name, name_length, "integer_overflow")) {
      const char *value;
      size_t value_length;
      if (lua_type(L, -1) != LUA_TSTRING)
        luaL_argerror(L, 2, "expected string option value");
      value = lua_tolstring(L, -1, &value_length);
      if (json_streq(name, name_length, "duplicate_keys")) {
        if (!json_streq(value, value_length, "error") &&
            !json_streq(value, value_length, "last"))
          luaL_argerror(L, 2, "duplicate_keys must be 'error' or 'last'");
        p->duplicate_last = json_streq(value, value_length, "last");
      }
      else {
        if (!json_streq(value, value_length, "error") &&
            !json_streq(value, value_length, "float"))
          luaL_argerror(L, 2, "integer_overflow must be 'error' or 'float'");
        p->overflow_float = json_streq(value, value_length, "float");
      }
    }
    else if (json_streq(name, name_length, "max_depth") ||
             json_streq(name, name_length, "max_values") ||
             json_streq(name, name_length, "max_bytes")) {
      lua_Integer n;
      if (!lua_isinteger(L, -1) || (n = lua_tointeger(L, -1)) <= 0)
        luaL_argerror(L, 2, "resource limits must be positive integers");
      if (json_streq(name, name_length, "max_depth")) {
        if (n > JSON_RECURSION_CEILING)
          luaL_argerror(L, 2, "max_depth must be at most 256");
        p->max_depth = n;
      }
      else if (json_streq(name, name_length, "max_values")) p->max_values = n;
      else p->max_bytes = (size_t)n;
    }
    else
      luaL_argerror(L, 2, "unknown JSON decode option");
    lua_pop(L, 1);
  }
}


static int json_error_tostring(lua_State *L) {
  lua_Integer line, column;
  const char *message;
  lua_getfield(L, 1, "message");
  message = lua_tostring(L, -1);
  lua_getfield(L, 1, "line");
  line = lua_tointeger(L, -1);
  lua_getfield(L, 1, "column");
  column = lua_tointeger(L, -1);
  lua_pushfstring(L, "json.decode: %s at line %I, column %I",
                  message == NULL ? "error" : message, line, column);
  return 1;
}


static int json_pusherror(JsonParser *p) {
  lua_State *L = p->L;
  lua_Integer line = 1, column = 1;
  size_t i;
  for (i = 0; i < p->error_pos; i++) {
    if (p->text[i] == '\n') { line++; column = 1; }
    else column++;
  }
  lua_settop(L, 2);  /* discard incomplete parse tree */
  lua_pushnil(L);
  lua_newtable(L);
  lua_pushstring(L, p->error_code);
  lua_setfield(L, -2, "code");
  lua_pushstring(L, p->error_message);
  lua_setfield(L, -2, "message");
  lua_pushinteger(L, (lua_Integer)p->error_pos + 1);
  lua_setfield(L, -2, "offset");
  lua_pushinteger(L, line);
  lua_setfield(L, -2, "line");
  lua_pushinteger(L, column);
  lua_setfield(L, -2, "column");
  if (p->error_path_valid) {
    lua_pushlstring(L, p->error_path, p->error_path_length);
    lua_setfield(L, -2, "path");
  }
  if (luaL_newmetatable(L, "quvrena.std.json.error")) {
    lua_pushcfunction(L, json_error_tostring);
    lua_setfield(L, -2, "__tostring");
    lua_pushliteral(L, "std.json.error");
    lua_setfield(L, -2, "__metatable");
  }
  lua_setmetatable(L, -2);
  return 2;
}


/* lua: json.decode(text [, options]) -> value | nil, err */
int quvjson_decode(lua_State *L) {
  JsonParser p;
  memset(&p, 0, sizeof(p));
  if (lua_gettop(L) > 2)
    return luaL_argerror(L, 3, "too many arguments");
  luaL_checktype(L, 1, LUA_TSTRING);
  p.L = L;
  p.text = lua_tolstring(L, 1, &p.length);
  p.max_depth = 128;
  p.max_values = 1000000;
  p.max_bytes = JSON_DEFAULT_MAX_BYTES;
  p.path_valid = 1;
  json_decode_options(L, &p);
  lua_settop(L, 2);
  if (p.length > p.max_bytes) {
    json_fail(&p, "size_limit", "maximum input bytes exceeded", p.max_bytes);
    return json_pusherror(&p);
  }
  if (!json_value(&p)) return json_pusherror(&p);
  json_ws(&p);
  if (p.pos != p.length) {
    json_fail(&p, "syntax", "trailing content after JSON value", p.pos);
    return json_pusherror(&p);
  }
  return 1;
}
