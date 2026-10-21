-- Regression test for std.json encoder output-buffer stack corruption.
-- The serialized document must exceed the old luaL_Buffer inline capacity.
local json = require("std.json")

local root = json.object({
    application = "Quvrena",
    enabled = true,
    players = json.array(),
    metadata = json.object({description = "Performance test 🚀"})
})

for i = 1, 250 do
    root.players[i] = json.object({
        id = i,
        name = "Player " .. i,
        score = i * 12.5,
        flags = json.array({true, false, json.null})
    })
end

for attempt = 1, 20 do
    local encoded, err = json.encode(root)
    assert(encoded, tostring(err))
    assert(#encoded > 16384, "JSON document should be large enough")

    local decoded, decode_err = json.decode(encoded)
    assert(decoded, tostring(decode_err))
    assert(json.kind(decoded.players) == "array")
    assert(#decoded.players == 250)
    for i = 1, 250 do
        local player = decoded.players[i]
        assert(player.id == i)
        assert(player.name == "Player " .. i)
        assert(player.score == i * 12.5)
        assert(player.flags[3] == json.null)
    end

    -- Exercise the object-key sorting code on the same large data.
    local sorted, sorted_err = json.encode(root, {sort_keys = true})
    assert(sorted, tostring(sorted_err))
    assert(#sorted > 16384)
    local sorted_decoded = assert(json.decode(sorted))
    assert(sorted_decoded.players[250].score == 3125)
end

for _ = 1, 20 do
    local encoded, err = json.encode(root, {max_bytes = 100})
    assert(encoded == nil and err.code == "size_limit")
end

-- An error must not corrupt subsequent calls.
local small = assert(json.encode(json.array({1, 2, json.null})))
assert(small == "[1,2,null]")

print("Quvrena JSON encoder buffer regression passed")
