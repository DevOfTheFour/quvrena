# Quvrena `std.json` - API Contract v1

> **Status:** Accepted design specification; implementation pending.  
> **Date:** 2026-10-21  
> **Compatibility target:** Quvrena based on Lua 5.5.1  
> **Scope:** Public Lua API and observable behavior. Internal C data structures and file layout are not specified here.  

## 1. Goals and non-goals

`std.json` is a native, portable C99 module for JSON interchange in scripts, games, tools, services and embedded applications. It MUST support standard JSON, preserve JSON `null`, distinguish arrays from objects, provide informative diagnostics, and apply configurable resource limits. The module MUST NOT require filesystem/network access or a third-party runtime library.

The accepted JSON grammar is RFC 8259. UTF-8 and duplicate-key policies aim for predictable interoperability; the default output is **not** claimed to be RFC 7493 (I-JSON) or RFC 8785 (JCS) canonical JSON, since optional 64-bit integers may exceed interoperable IEEE-754 precision.

Not in v1: JSON5, comments/trailing commas, schema validation, JSON Pointer evaluation API, JSON Patch, SAX/streaming APIs, asynchronous I/O, file access, user-defined `__json` hooks, reference preservation, or canonical cryptographic output.

## 2. Module availability and public surface

```lua
local json = require("std.json")

json.encode(value [, options])        --> string | nil, error
json.decode(text [, options])         --> value | nil, error
json.array([table])                   --> table
json.object([table])                  --> table
json.kind(value)                      --> "array" | "object" | nil
json.null                             -- unique JSON null singleton
```

The default Quvrena runtime MUST register a loader for `std.json` so that `require("std.json")` works without finding a Lua file on disk. Embedded hosts MAY provide a restricted set of libraries/modules; a host that does not enable this optional module need not expose it. No global `json` variable is introduced. Details of the C registration function and build option are implementation details to settle during implementation, not new public Lua APIs in this contract.

All documented options are optional. Unknown option names and wrong option types MUST raise a Lua argument error (programmer error). Invalid JSON data, unsupported values and configured resource-limit violations MUST return `nil, err` as specified below, except for allocation failures and other unrecoverable Lua runtime errors.

## 3. JSON values and Lua representations

| JSON type | Quvrena/Lua value |
|---|---|
| `null` | `json.null` singleton |
| `false`, `true` | Lua boolean |
| number | Lua `integer` or `float` (section 7) |
| string | Lua string, UTF-8 validated |
| array | Lua table explicitly tagged as `array` on decode |
| object | Lua table explicitly tagged as `object` on decode |

### 3.1 `json.null`

* `json.null` is a unique, immutable-identity full userdata singleton per Lua state/module instance (a Lua value, **not** `nil`).
* Decoding the JSON literal `null` MUST return that singleton; `json.encode(json.null)` MUST produce `"null"`.
* `json.encode(nil)` MUST return `nil, err` with `err.code == "unsupported_type"`.
* Fields with `json.null` MUST remain present; assigning `nil` to a Lua table field removes that field and cannot represent JSON `null`.
* `false` is valid JSON. Failure MUST be tested with `result == nil`, never `not result`.

```lua
local v = assert(json.decode('{"name":null,"enabled":false}'))
assert(v.name == json.null)
assert(v.enabled == false)
assert(json.encode(json.null) == "null")
```

### 3.2 Marked and unmarked containers

`json.array(t)` and `json.object(t)` accept an optional existing table and return **the same table**; without an argument they create a new empty table. A non-table argument raises a Lua argument error. They tag the table but MUST NOT alter its raw entries or user metatable. Calling one of these functions on an already tagged table replaces its tag. The table is validated for its selected JSON kind when encoded, not when tagged.

The intended implementation stores tags in a private registry table with weak keys; it MUST NOT rely on users' metatables. Tags remain while the corresponding Lua table is reachable, but do not keep unreachable tables alive.

`json.kind(t)` returns the **explicit** tag for marked tables and decoded containers; for unmarked tables and values that are not tables it returns `nil`. It DOES NOT infer a kind from contents.

Unmarked tables are classified only during encoding:

| Raw Lua contents | Encoded as |
|---|---|
| No keys (`{}`) | JSON object `{}` |
| Exactly integer keys `1..N`, `N >= 1` | JSON array |
| Only string keys | JSON object |
| Mixed, sparse, zero/negative/noninteger numeric, boolean or other keys | `invalid_table` error |

Explicit arrays may contain only dense integer keys `1..N` (an empty explicit array is allowed). Explicit objects may contain only string keys (empty objects allowed). `nil` cannot fill a missing array element: use `json.null`. Validation uses **raw** entries; neither `#t` on sparse tables nor metamethods decide array shape. JSON object member order is unspecified unless `sort_keys = true`.

```lua
assert(json.encode({}) == "{}")
assert(json.encode(json.array()) == "[]")
assert(json.encode({10, 20}) == "[10,20]")
assert(json.kind({10, 20}) == nil)
local t = assert(json.decode("[]"))
assert(json.kind(t) == "array")
assert(json.encode(t) == "[]")
```

Marking a table affects only JSON serialization; `table.clone`, ordinary copying or rebuilding the contents does not promise to preserve the private JSON tag. A shallow copy of an empty tagged array, for example, is an unmarked empty table unless explicitly retagged.

### 3.3 Cycles, aliases and metatables

* A cycle reachable from the input MUST be rejected with `circular_reference`.
* A shared child referenced from multiple non-cyclic locations is allowed and serialized at each location independently (JSON has no shared references).
* Encoder and decoder MUST NOT invoke `__pairs`, `__index`, `__newindex`, `__tostring`, or a user-defined `__json` hook to interpret JSON values. Encoded tables are traversed using raw operations.
* Metatables and their behavior are neither serialized nor restored by decode.
* User code MUST NOT mutate a table concurrently with its encoding; no consistency guarantee is made for concurrent or reentrant mutation.

## 4. `json.encode(value [, options])`

Returns one JSON UTF-8 string on success. On a data/limit error returns `nil, err`. JSON text is compact by default and has **no trailing newline**.

| Option | Type | Default | Semantics |
|---|---|---:|---|
| `pretty` | boolean | `false` | Human-readable indentation and line breaks |
| `indent` | integer 0..8 | `2` | Spaces per nesting level when `pretty = true` |
| `sort_keys` | boolean | `false` | Sort object keys by raw UTF-8 byte order |
| `ensure_ascii` | boolean | `false` | Escape non-ASCII characters with `\uXXXX` (surrogate pairs when necessary) |
| `safe_integers` | boolean | `false` | Reject Lua integer values outside `[-(2^53 - 1), 2^53 - 1]` |
| `max_depth` | positive integer | `128` | Maximum nested container depth |
| `max_bytes` | positive integer | `67108864` | Maximum output bytes (64 MiB) |
| `max_values` | positive integer | `1000000` | Maximum total serialized JSON values |

`pretty = true` uses `\n` line endings on every OS, with no terminal newline. `sort_keys` is deterministic at the level of object-key ordering, but MUST NOT be presented as RFC 8785 canonicalization. Strings MUST be validated as UTF-8 even if `ensure_ascii = true`. Invalid UTF-8 returns `invalid_utf8`.

Unsupported values include `nil`, functions, threads, and arbitrary userdata/light userdata; only the `json.null` singleton is the supported userdata value. Non-finite floats are rejected with `invalid_number`. Input must be representable as a JSON number/string/container without silent coercion.

```lua
local text, err = json.encode(json.object({
    project = "Quvrena",
    modules = json.array({"physics", "audio"}),
    optional = json.null
}), { pretty = true, sort_keys = true })
if text == nil then error(tostring(err)) end
```

## 5. `json.decode(text [, options])`

The first argument MUST be a Lua string. Only complete RFC 8259 JSON text is accepted, optionally surrounded by RFC JSON whitespace (`space`, `tab`, `CR`, `LF`). Trailing non-whitespace data, comments, trailing commas, unquoted keys, single quotes, NaN and Infinity are errors. A UTF-8 BOM at the start is rejected in v1. Object and array nodes are tagged with their JSON kind, including empty nodes.

| Option | Type | Default | Semantics |
|---|---|---|---|
| `duplicate_keys` | `"error"` or `"last"` | `"error"` | Reject duplicate object names or keep last value |
| `integer_overflow` | `"error"` or `"float"` | `"error"` | Action when integral JSON literal exceeds `lua_Integer` range |
| `max_depth` | positive integer | `128` | Maximum nested container depth |
| `max_bytes` | positive integer | `67108864` | Maximum input bytes (64 MiB) |
| `max_values` | positive integer | `1000000` | Maximum parsed JSON values |

Duplicate keys are compared **after JSON escape decoding**: `"a"` and `"\u0061"` are duplicates. In `"last"` mode the last occurrence replaces earlier values, even when it is `null`.

`false` is a legitimate successful decode return; only `nil` signals failure. `json.decode("null")` returns `json.null`, not `nil`.

## 6. Depth and resource accounting

Depth is the number of currently nested object/array containers: a root scalar has depth 0, a root array/object has depth 1. A child array/object increments depth by one. `max_values` counts the root and every contained JSON value (including each container, scalar and `null`); object member names do **not** count as values. `max_bytes` counts the complete UTF-8 byte length of the input for decode and encoded output for encode. Exceeding a configured bound returns the corresponding structured limit error; invalid option values are argument errors. Resource limits do not guarantee a hard bound on internal temporary allocations or CPU usage, and Lua allocation failures may still raise runtime errors.

## 7. Numeric semantics

v1 targets Quvrena's normal 64-bit `lua_Integer` plus IEEE-754 binary64 `lua_Number` configuration; other numeric configurations are not promised identical edge-case behavior.

### Decode

* Integer-form JSON literals within `lua_Integer` range decode to Lua `integer` (except `-0`).
* JSON with a fraction or exponent decodes to Lua `float`, even when mathematically integral: `42.0`, `1e3`.
* The JSON literal `-0` decodes to floating-point negative zero, so its sign can round-trip.
* Integer-form values outside `lua_Integer` range fail with `invalid_number` by default; `integer_overflow = "float"` permits a finite approximate float instead.
* Overflow or underflow that cannot preserve a supported finite numeric result MUST NOT silently become Infinity, NaN, or an unrelated value; reject unrepresentable inputs with `invalid_number`.

### Encode

* Integers are emitted as exact decimal integer literals.
* Finite floats are emitted with enough precision to round-trip the float's binary value and preserve its Lua `float` subtype (use decimal point or exponent when needed).
* Positive/negative zero float signs are preserved (`0.0` / `-0.0` or equivalent decimal/exponent representation).
* `NaN` and positive/negative Infinity are rejected (`invalid_number`).
* `safe_integers = true` rejects Lua **integer** values whose absolute value exceeds `2^53 - 1`; it is a cross-language interoperability aid, not a promise of exactness for arbitrary floats.

JSON does not specify numeric subtypes. This `integer`/`float` handling is Quvrena-specific and may be incompatible with JavaScript's exact integer range; APIs needing exact IDs larger than `2^53 - 1` SHOULD exchange them as JSON strings.

## 8. Unicode and string validity

* Encoded and decoded JSON strings must contain valid UTF-8 Unicode scalar values.
* Recognize JSON escapes, including `\uXXXX`; valid UTF-16 surrogate pairs become their corresponding UTF-8 sequence.
* Reject unpaired surrogates, overlong UTF-8, invalid continuation bytes and invalid code points with `invalid_utf8` (or `syntax` for malformed escape grammar).
* Escape JSON control characters, including the Lua byte `\0` as `\u0000`.
* By default, preserve UTF-8 non-ASCII characters; when `ensure_ascii = true`, encode them as `\uXXXX` escapes, using surrogate pairs when required.
* Perform **no** Unicode normalization. Member-name equality compares decoded Unicode scalar sequences, not their source escape spelling.

## 9. Errors and diagnostics

Data errors and limit violations return `nil, err`, where `err` is a structured Lua error object exposing:

| Field | Type | Meaning |
|---|---|---|
| `code` | string | Machine-readable stable error code |
| `message` | string | Human-readable diagnostic |
| `offset` | integer or `nil` | 1-based byte position within input (decode only) |
| `line` | integer or `nil` | 1-based line number (decode only) |
| `column` | integer or `nil` | 1-based **byte** column (decode only) |
| `path` | string or `nil` | JSON Pointer identifying problematic location, when known |

`tostring(err)` MUST produce a useful description, such as `json.decode: unexpected token at line 1, column 10`. For error locations at end of input, `offset` may be `#text + 1`.

A present `path` uses RFC 6901 JSON Pointer syntax: `""` represents the root, object names escape `~` to `~0` and `/` to `~1`; array indices are **zero-based** even though Lua arrays are 1-based. Example: `/players/0/name`. No guarantee is made that `path` is available for malformed syntax before a location is identifiable.

Stable initial `err.code` values:

| Code | Meaning |
|---|---|
| `syntax` | Malformed JSON grammar or trailing content |
| `invalid_utf8` | Invalid UTF-8 or Unicode scalar representation |
| `invalid_number` | Overflow, non-finite value or unsupported numeric representation |
| `duplicate_key` | Duplicate object member in strict mode |
| `invalid_table` | Unsupported/sparse/mixed table key layout |
| `unsupported_type` | Lua value unsupported by JSON, including root `nil` |
| `circular_reference` | Cycle detected in table graph |
| `depth_limit` | `max_depth` exceeded |
| `size_limit` | `max_bytes` exceeded |
| `value_limit` | `max_values` exceeded |

Programming errors (incorrect arity, non-string input to `decode`, invalid option name/type/range, non-table passed to `array`/`object`) raise normal Lua argument errors. Allocation failures may raise Lua memory errors, not necessarily return structured errors.

```lua
local value, err = json.decode('{"a":}')
if value == nil then
    assert(type(err.code) == "string")
    print(tostring(err), err.offset, err.path)
end
```

## 10. References

* [RFC 8259 - JSON Data Interchange Format](https://www.rfc-editor.org/rfc/rfc8259)
* [RFC 7493 - I-JSON](https://www.rfc-editor.org/rfc/rfc7493)
* [RFC 6901 - JSON Pointer](https://www.rfc-editor.org/rfc/rfc6901)
* [RFC 8785 - JSON Canonicalization Scheme](https://www.rfc-editor.org/rfc/rfc8785)
* [Lua 5.5 Reference Manual](https://www.lua.org/manual/5.5/manual.html)
