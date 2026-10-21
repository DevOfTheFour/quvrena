-- Quvrena std.json decoder conformance tests (M2.4b).
local json = require("std.json")

local function reject(text, expected, options)
    local result, err = json.decode(text, options)
    assert(result == nil, "expected JSON decoder failure")
    assert(type(err) == "table")
    assert(err.code == expected,
        ("expected error '%s', got '%s': %s")
            :format(expected, tostring(err.code), tostring(err)))
    assert(type(err.message) == "string")
    assert(type(err.offset) == "number" and err.offset >= 1)
    assert(type(err.line) == "number" and err.line >= 1)
    assert(type(err.column) == "number" and err.column >= 1)
    assert(type(tostring(err)) == "string")
    return err
end

-- JSON scalar values; failure is nil, not false.
do
    assert(json.decode("true") == true)
    assert(json.decode("false") == false)
    assert(json.decode("null") == json.null)
    assert(json.decode(' "text" \n') == "text")
    assert(json.decode("42") == 42)
    assert(json.decode("-42") == -42)
    assert(json.decode("42.0") == 42.0)
    assert(math.type(json.decode("42")) == "integer")
    assert(math.type(json.decode("42.0")) == "float")
    assert(math.type(json.decode("1e3")) == "float")
    assert(json.decode("-0") == 0)
    assert(math.type(json.decode("-0")) == "float")
    assert(1 / json.decode("-0") == -math.huge)
end

-- Containers get explicit JSON kind tags, including empties.
do
    local a = assert(json.decode("[]"))
    local o = assert(json.decode("{}"))

    assert(json.kind(a) == "array" and next(a) == nil)
    assert(json.kind(o) == "object" and next(o) == nil)

    local data = assert(json.decode([=[
        {
            "name": "Quvrena",
            "active": false,
            "items": [1, null, {"ok": true}]
        }
    ]=]))

    assert(json.kind(data) == "object")
    assert(data.name == "Quvrena")
    assert(data.active == false)
    assert(json.kind(data.items) == "array")
    assert(data.items[2] == json.null)
    assert(json.kind(data.items[3]) == "object")
    assert(data.items[3].ok == true)
    assert(getmetatable(data) == nil)
end

-- String escapes and Unicode scalar values.
do
    assert(json.decode([=["hello\nworld\t!"]=]) == "hello\nworld\t!")
    assert(json.decode([=["a\u0000b"]=]) == "a\0b")
    assert(json.decode([=["\u041F\u0440\u0438\u0432\u0435\u0442"]=]) == "Привет")
    assert(json.decode([=["\uD83D\uDE80"]=]) == "🚀")
    assert(json.decode('"Привет, 🚀"') == "Привет, 🚀")
    assert(json.decode([=["\/\"\\"]=]) == '/"\\')
    reject('"' .. string.char(0xc0, 0xaf) .. '"', "invalid_utf8")
    reject('"' .. string.char(0xed, 0xa0, 0x80) .. '"', "invalid_utf8")
    reject([=["\uD800"]=], "invalid_utf8")
    reject([=["\uDC00"]=], "invalid_utf8")
    reject([=["\uD800\u0041"]=], "invalid_utf8")
    reject([=["\u12ZZ"]=], "syntax")
    reject('"a\0b"', "syntax")
end

-- Strict RFC 8259 syntax.
do
    for _, text in ipairs({
        "", " ", "tru", "True", "NULL", "NaN", "Infinity", 
        "[1,]", '{"a":1,}', '{a:1}', "{'a':1}",
        "[1 2]", "{}{}", "true false", "// comment\n1",
        "01", "-01", "+1", "1.", "1e", "1e+", "--1",
        '["unterminated]', '["bad\\x"]', "[1, /* comment */ 2]"
    }) do
        reject(text, "syntax")
    end

    reject(string.char(0xef, 0xbb, 0xbf) .. "{}", "syntax")
end

-- Duplicate names compare after JSON unescaping.
do
    local duplicate = reject('{"a":1,"\\u0061":2}', "duplicate_key")

    assert(duplicate.path == "/a")
    assert(reject('{"/~":1,"/~":2}', "duplicate_key").path == "/~1~0")

    local keep_last = assert(json.decode('{"a":1,"\\u0061":null}', {
        duplicate_keys = "last"
    }))

    assert(keep_last.a == json.null)
    assert(json.kind(keep_last) == "object")
end

-- JSON Pointer uses zero-based array positions.
do
    local nested_error = reject('{"players":[0,{"name":}]}' , "syntax")
    assert(nested_error.path == "/players/1/name")
    
    local err_at_second_line = reject('{"a":1,\n "b":}', "syntax")
    assert(err_at_second_line.line == 2)
end
