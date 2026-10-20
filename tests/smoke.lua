assert(_VERSION == "Lua 5.5")

assert(10 + 20 == 30)
assert(10 // 3 == 3)

local object = {
    name = "test",
    health = 100
}

assert(object.health == 100)

local function add(a, b)
    return a + b
end

assert(add(5, 7) == 12)

local closed = false

do
    local resource <close> = setmetatable({}, {
        __close = function()
            closed = true
        end
    })
end

assert(closed)

print("Lua baseline tests passed!")
