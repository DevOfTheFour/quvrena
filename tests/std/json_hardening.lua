-- Integration and adversarial boundary tests for std.json
local json = require("std.json")

local function decoded(text, options)
    local value, err = json.decode(text, options)
    assert(value ~= nil, "decode failed: " .. tostring(err))
    return value
end

local function encoded(value, options)
    local text, err = json.encode(value, options)
    assert(text ~= nil, "encode failed: " .. tostring(err))
    return text
end

local function decode_error(text, code, options)
    local result, err = json.decode(text, options)
    assert(result == nil and type(err) == "table", "expected decode error")
    assert(err.code == code,
        ("expected %s, got %s: %s"):format(code, tostring(err.code), tostring(err)))
    assert(type(err.offset) == "number" and err.offset >= 1)
    assert(type(err.line) == "number" and err.line >= 1)
    assert(type(err.column) == "number" and err.column >= 1)
    return err
end

local function encode_error(value, code, options)
    local result, err = json.encode(value, options)
    assert(result == nil and type(err) == "table", "expected encode error")
    assert(err.code == code,
        ("expected %s, got %s: %s"):format(code, tostring(err.code), tostring(err)))
    return err
end

local function argument_error(fn)
    assert(not pcall(fn), "expected Lua argument error")
end

-- Container shape, false, null, Unicode, zero bytes, and sorted keys.
do
    local original = json.object({
        ["~/"] = json.array({false, json.null, "\0\n\"", "🚀"}),
        empty_array = json.array(),
        empty_object = json.object(),
        id = math.maxinteger,
        flag = false
    })
    local text = encoded(original, {sort_keys = true, ensure_ascii = true})
    assert(text:find("\\ud83d\\ude80", 1, true))
    for i = 1, #text do assert(text:byte(i) < 128) end
    local copy = decoded(text)
    assert(json.kind(copy) == "object")
    assert(json.kind(copy["~/"]) == "array")
    assert(copy["~/"][1] == false)
    assert(copy["~/"][2] == json.null)
    assert(copy["~/"][3] == "\0\n\"")
    assert(copy["~/"][4] == "🚀")
    assert(json.kind(copy.empty_array) == "array")
    assert(json.kind(copy.empty_object) == "object")
    assert(next(copy.empty_array) == nil)
    assert(next(copy.empty_object) == nil)
    assert(copy.id == math.maxinteger)
    assert(copy.flag == false)
    assert(encoded(copy, {sort_keys = true, ensure_ascii = true}) == text)
end

-- Escaped object keys + zero-based array positions in error paths.
do
    local e = encode_error(json.object({
        ["~/"] = json.array({true, function() end})
    }), "unsupported_type", {sort_keys = true})
    assert(e.path == "/~0~1/1", tostring(e.path))

    e = decode_error('{"~/":[true,{"bad":}]}', "syntax")
    assert(e.path == "/~0~1/1/bad", tostring(e.path))
end

-- Stress exact resource boundaries, without huge allocations.
do
    local text = '{"root":[0,false,null]}'  -- five JSON values
    local obj = decoded(text, {max_values = 5})
    assert(obj.root[3] == json.null)
    decode_error(text, "value_limit", {max_values = 4})
    assert(encoded(obj, {sort_keys = true, max_values = 5}) == text)
    encode_error(obj, "value_limit", {max_values = 4})

    assert(decoded('"é"', {max_bytes = 4}) == "é")
    decode_error('"é"', "size_limit", {max_bytes = 3})
    assert(encoded("é", {ensure_ascii = true, max_bytes = 8}) == '"\\u00e9"')
    encode_error("é", "size_limit", {ensure_ascii = true, max_bytes = 7})

    local nesting = 65
    local nested_text = string.rep("[", nesting) .. "0" .. string.rep("]", nesting)
    assert(type(decoded(nested_text, {max_depth = 65})) == "table")
    decode_error(nested_text, "depth_limit", {max_depth = 64})

    local nested_value = 0
    for _ = 1, nesting do nested_value = json.array({nested_value}) end
    assert(encoded(nested_value, {max_depth = 65}) == nested_text)
    encode_error(nested_value, "depth_limit", {max_depth = 64})

    assert(decoded("null", {max_depth = 256}) == json.null)
    assert(encoded(json.null, {max_depth = 256}) == "null")
    argument_error(function() json.decode("null", {max_depth = 257}) end)
    argument_error(function() json.encode(json.null, {max_depth = 257}) end)
end

-- Strict UTF-8, escape grammar, duplicate keys and no extended JSON.
do
    for _, bytes in ipairs({
        "\128", "\192\128", "\224\128\128", "\237\160\128",
        "\240\128\128\128", "\244\144\128\128", "\226\130"
    }) do
        decode_error('"' .. bytes .. '"', "invalid_utf8")
        encode_error(bytes, "invalid_utf8")
    end
    decode_error('"\\uD800"', "invalid_utf8")
    decode_error('"\\uDC00"', "invalid_utf8")
    decode_error('"\\uD800\\u0041"', "invalid_utf8")
    decode_error('"\\u12G4"', "syntax")
    decode_error('{"a":1,"\\u0061":2}', "duplicate_key")
    assert(decoded('{"a":1,"\\u0061":null}', {
        duplicate_keys = "last"
    }).a == json.null)

    for _, invalid in ipairs({
        "{} trailing", "{a:1}", "[1,]", '{"x":1,}', "'text'",
        "//x\n42", "NaN", "Infinity", "01", "+1", "1.", "1e+"
    }) do
        decode_error(invalid, "syntax")
    end
end

-- Exact 64-bit boundaries and preservation of negative-zero float.
do
    assert(decoded("9223372036854775807") == math.maxinteger)
    assert(decoded("-9223372036854775808") == math.mininteger)
    decode_error("9223372036854775808", "invalid_number")
    decode_error("1e9999", "invalid_number")
    assert(1 / decoded(encoded(-0.0)) == -math.huge)
    encode_error(math.maxinteger, "invalid_number", {safe_integers = true})
    assert(encoded(9007199254740991, {safe_integers = true}) ==
        "9007199254740991")
end

-- Untrusted table graphs: cycles rejected, aliases allowed, no metamethods.
do
    local child = json.object({value = 7})
    local shared = json.array({child, child})
    assert(encoded(shared, {sort_keys = true}) ==
        '[{"value":7},{"value":7}]')
    child.parent = shared
    assert(encode_error(shared, "circular_reference").path ==
        "/0/parent")

    local mt = {
        __index = function() error("__index was called") end,
        __pairs = function() error("__pairs was called") end,
        __len = function() error("__len was called") end,
        __tostring = function() error("__tostring was called") end
    }
    local t = setmetatable({ok = 1}, mt)
    json.object(t)
    assert(encoded(t, {sort_keys = true}) == '{"ok":1}')
    assert(getmetatable(t) == mt)
end

print("Quvrena std.json hardening tests passed")
