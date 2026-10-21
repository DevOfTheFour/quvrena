-- Quvrena std.json encoder regression tests

local json = require("std.json")

local function failcode(value, code, options)
    local result, err = json.encode(value, options)
    assert(result == nil, "expected encode failure")
    assert(type(err) == "table")
    assert(err.code == code,
        ("expected %s, got %s: %s"):format(code, tostring(err.code), tostring(err)))
    assert(type(err.message) == "string")
    assert(type(tostring(err)) == "string")
    assert(err.offset == nil and err.line == nil and err.column == nil)
    return err
end

local function argfail(fn)
    assert(not pcall(fn), "expected Lua argument error")
end

-- 1. Primitives: root scalar, booleans, null and literal NUL.
do
    assert(json.encode(true) == "true")
    assert(json.encode(false) == "false")
    assert(json.encode(json.null) == "null")
    assert(json.encode(123) == "123")
    assert(json.encode("hello") == '"hello"')
    assert(json.encode("") == '""')
    assert(json.encode("\0") == '"\\u0000"')
    assert(json.encode("a\nb\t\"\\") == '"a\\nb\\t\\\"\\\\"')
    failcode(nil, "unsupported_type")
    failcode(function() end, "unsupported_type")
    failcode(coroutine.create(function() end), "unsupported_type")
    failcode(io.stdout, "unsupported_type")
end

-- 2. Automatic and explicit JSON container kinds.
do
    assert(json.encode({}) == "{}")
    assert(json.encode(json.object()) == "{}")
    assert(json.encode(json.array()) == "[]")
    assert(json.encode({10, 20, 30}) == "[10,20,30]")
    assert(json.encode(json.array({10, 20, 30})) == "[10,20,30]")
    assert(json.encode(json.object({a = 1}), {sort_keys = true}) == '{"a":1}')

    failcode({[1] = 10, [3] = 30}, "invalid_table")
    failcode({[0] = 10}, "invalid_table")
    failcode({[-1] = 10}, "invalid_table")
    failcode({[2.5] = 10}, "invalid_table")
    failcode({[true] = 10}, "invalid_table")
    failcode({[1] = 10, a = 20}, "invalid_table")
    failcode(json.array({name = "bad"}), "invalid_table")
    failcode(json.object({1, 2}), "invalid_table")
    failcode({[{}] = 1}, "invalid_table")
end

-- 3. Strictly raw traversal; no table metamethod execution.
do
    local mt = {
        __index = function() error("__index called") end,
        __pairs = function() error("__pairs called") end,
        __len = function() error("__len called") end,
        __tostring = function() error("__tostring called") end
    }
    local t = setmetatable({a = 1}, mt)
    local text = assert(json.encode(t, {sort_keys = true}))
    assert(text == '{"a":1}')
    assert(getmetatable(t) == mt)
end

-- 4. Sorting keys (bytewise) and pretty output.
do
    local t = {z = 3, a = 1, b = 2}
    assert(json.encode(t, {sort_keys = true}) ==
        '{"a":1,"b":2,"z":3}')

    local formatted = json.encode({b = {2, 3}, a = true}, {
        pretty = true,
        indent = 2,
        sort_keys = true
    })
    assert(formatted == table.concat({
        '{',
        '  "a": true,',
        '  "b": [',
        '    2,',
        '    3',
        '  ]',
        '}'
    }, '\n'))
    assert(formatted:sub(-1) ~= '\n')
    assert(json.encode(json.array(), {pretty = true}) == "[]")
    assert(json.encode(json.object(), {pretty = true}) == "{}")
    assert(json.encode({a = 1}, {pretty = true, indent = 0}) ==
        '{\n"a": 1\n}')
end
