-- Quvrena compound assignment tests

-- 1. Arithmetic operators
do
    local x = 10

    x += 5
    assert(x == 15)

    x -= 3
    assert(x == 12)

    x *= 2
    assert(x == 24)

    x /= 4
    assert(x == 6)
end

-- 2. String concatenation
do
    local name = "Quvrena"

    name ..= " Language"
    assert(name == "Quvrena Language")
end

-- 3. Operator precedence
do
    local x = 10

    x += 2 * 3
    assert(x == 16)

    x *= 2 + 3
    assert(x == 80)
end

-- 4. Indexed fields
do
    local player = {
        health = 100,
        damage = 10
    }

    player.health -= 25
    player.damage *= 2

    assert(player.health == 75)
    assert(player.damage == 20)

    local values = {2, 4, 6}
    values[2] += 10

    assert(values[2] == 14)
end

-- 5. Table and key evaluated exactly once
do
    local tableCalls = 0
    local keyCalls = 0

    local data = {health = 100}

    local function getTable()
        tableCalls += 1
        return data
    end

    local function getKey()
        keyCalls += 1
        return "health"
    end

    getTable()[getKey()] -= 25

    assert(data.health == 75)
    assert(tableCalls == 1)
    assert(keyCalls == 1)
end

-- 6. Preserve original table during RHS
do
    local original = {value = 10}
    local target = original

    local function changeTarget()
        target = {value = 100}
        return 5
    end

    target.value += changeTarget()

    assert(original.value == 15)
    assert(target.value == 100)
end

-- 7. Preserve original key during RHS
do
    local data = {a = 10, b = 100}
    local key = "a"

    local function changeKey()
        key = "b"
        return 5
    end

    data[key] += changeKey()

    assert(data.a == 15)
    assert(data.b == 100)
end

-- 8. Upvalues
do
    local count = 0

    local function increment()
        count += 1
    end

    increment()
    increment()
    increment()

    assert(count == 3)
end

-- 9. Metamethods for reading, arithmetic and writing
do
    local events = {}

    local value = setmetatable({}, {
        __add = function(_, amount)
            events[#events + 1] = "add"
            return 10 + amount
        end
    })

    local object = setmetatable({}, {
        __index = function(self, key)
            assert(key == "score")
            events[#events + 1] = "read"
            return value
        end,

        __newindex = function(self, key, newValue)
            assert(key == "score")
            events[#events + 1] = "write"
            rawset(self, key, newValue)
        end
    })

    object.score += 5

    assert(object.score == 15)
    assert(table.concat(events, ",") == "read,add,write")
end

-- 10. Global variables
do
    _G.quvrena_test_counter = 10

    quvrena_test_counter += 5

    assert(quvrena_test_counter == 15)

    _G.quvrena_test_counter = nil
end

-- 11. RHS returns multiple values
do
    local x = 10

    local function values()
        return 2, 100
    end

    x += values()
    assert(x == 12)
end

-- 12. Readonly locals
do
    local fn, err = load([[
        local x <const> = 10
        x += 5
    ]])

    assert(fn == nil)
    assert(type(err) == "string")
end

-- 13. Invalid targets
do
    local fn = load("(1 + 2) += 3")
    assert(fn == nil)

    fn = load("a, b += 10")
    assert(fn == nil)

    fn = load("local a = 1; a += ")
    assert(fn == nil)
end

print("Quvrena compound assignment tests passed")
