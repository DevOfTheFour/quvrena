-- Deterministic property / adversarial-input testing
local json = require("std.json")
local initial_seed = 20261022
local seed = initial_seed

-- Park-Miller generator. All intermediate values fit in a signed 64-bit int.
local function rnd(n)
    seed = (seed * 48271) % 2147483647
    return (seed % n) + 1
end

local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then
        if type(a) == "number" and math.type(a) ~= math.type(b) then
            return false
        end
        return a == b
    end
    if json.kind(a) ~= json.kind(b) then return false end
    local na, nb = 0, 0
    for k, v in next, a do
        na = na + 1
        if rawget(b, k) == nil or not same(v, rawget(b, k)) then
            return false
        end
    end
    for _ in next, b do nb = nb + 1 end
    return na == nb
end

local sample_strings = {
    "", "ascii", "hello\nworld", "\0", "slash/tilde~",
    "Привет", "🚀", "quote\"\\", "é", "a\tb"
}

local function generate(depth)
    local mode = rnd(depth >= 4 and 6 or 8)
    if mode == 1 then return rnd(2000001) - 1000001 end
    if mode == 2 then return (rnd(200001) - 100001) / 8.0 end
    if mode == 3 then return rnd(2) == 1 end
    if mode == 4 then return json.null end
    if mode == 5 then return sample_strings[rnd(#sample_strings)] end
    if mode == 6 then return -0.0 end
    if mode == 7 then
        local a = json.array()
        local count = rnd(4) - 1
        for i = 1, count do a[i] = generate(depth + 1) end
        return a
    end
    local o = json.object()
    local count = rnd(4) - 1
    for i = 1, count do
        o["key/" .. i .. "~"] = generate(depth + 1)
    end
    return o
end

-- Valid JSON round-trips with combinations of encoder options.
for case = 1, 700 do
    local original = generate(0)
    local options = {
        sort_keys = rnd(2) == 1,
        pretty = rnd(2) == 1,
        ensure_ascii = rnd(2) == 1,
        indent = rnd(5) - 1,
        max_depth = 16,
        max_values = 1024,
        max_bytes = 131072
    }
    local ok, text, err = pcall(json.encode, original, options)
    assert(ok, ("encode threw on valid case %d (seed %d): %s"):
        format(case, initial_seed, tostring(text)))
    assert(text ~= nil, ("encode failed on case %d: %s"):
        format(case, tostring(err)))
    local parsed, parse_err = json.decode(text, {
        max_depth = 16,
        max_values = 1024,
        max_bytes = 131072
    })
    assert(parsed ~= nil, ("decode failed on case %d: %s"):
        format(case, tostring(parse_err)))
    assert(same(original, parsed), ("round-trip mismatch on case %d"):
        format(case))
end

-- Arbitrary bytes: the decoder may accept a valid JSON value or return
-- structured data failure, but must not throw an unexpected Lua exception.
for case = 1, 3500 do
    local length = rnd(150) - 1
    local bytes = {}
    for i = 1, length do bytes[i] = string.char(rnd(256) - 1) end
    local text = table.concat(bytes)
    local ok, value, err = pcall(json.decode, text, {
        max_depth = 32, max_values = 256, max_bytes = 4096
    })
    assert(ok, ("decoder threw on byte case %d (seed %d): %s"):
        format(case, initial_seed, tostring(value)))
    if value == nil then
        assert(type(err) == "table" and type(err.code) == "string",
            ("unstructured error on byte case %d"):format(case))
    else
        local reencoded, encode_err = json.encode(value, {
            max_depth = 32, max_values = 256, max_bytes = 4096
        })
        assert(reencoded ~= nil,
            ("valid parse was not encodable on byte case %d: %s"):
            format(case, tostring(encode_err)))
        local reparsed, reparse_err = json.decode(reencoded)
        assert(reparsed ~= nil,
            ("re-parse failed on byte case %d: %s"):
            format(case, tostring(reparse_err)))
    end
end

print(("Quvrena std.json fuzz tests passed (seed %d)"):
    format(initial_seed))
