-- Manual microbenchmark: no performance threshold in CI.
local json = require("std.json")
local iterations = tonumber(arg[1]) or 3000
assert(iterations >= 1 and iterations <= 1000000 and
       iterations == math.floor(iterations), "invalid iteration count")

local data = json.object({
    application = "Quvrena",
    enabled = true,
    version = "0.1.0",
    players = json.array(),
    metadata = json.object({description = "Performance test 🚀"})
})
for i = 1, 30 do
    data.players[i] = json.object({
        id = i, name = "Player " .. i, score = i * 12.5,
        flags = json.array({true, false, json.null})
    })
end

local text = assert(json.encode(data))
local function measure(label, fn)
    collectgarbage("collect")
    local begin = os.clock()
    for _ = 1, iterations do fn() end
    local seconds = os.clock() - begin
    print(("%-20s %8.3f s  %10.0f ops/s"):
        format(label, seconds, seconds > 0 and iterations / seconds or 0))
end

print(("JSON bytes: %d | iterations: %d"):format(#text, iterations))
measure("json.encode", function()
    assert(json.encode(data))
end)
measure("json.decode", function()
    assert(json.decode(text))
end)
measure("round-trip", function()
    assert(json.decode(assert(json.encode(data))))
end)
