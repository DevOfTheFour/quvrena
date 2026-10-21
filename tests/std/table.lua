-- Quvrena table library tests

-- Existing Lua functionality must remain available
assert(type(table.create) == "function")
assert(type(table.insert) == "function")
assert(type(table.sort) == "function")
assert(type(table.move) == "function")

-- table.clear
do
    local t = {
        10, 20, 30,
        health = 100,
        enabled = true
    }

    local mt = {
        __newindex = function()
            error("unexpected __newindex")
        end
    }

    setmetatable(t, mt)

    assert(table.clear(t) == t)
    assert(next(t) == nil)

    -- Metatable must be preserved
    assert(getmetatable(t) == mt)

    -- Normal assignment must still invoke __newindex
    local ok = pcall(function()
        t.health = 50
    end)

    assert(not ok)

    -- Raw assignment bypasses __newindex
    rawset(t, "health", 50)

    assert(t.health == 50)
end

-- table.clone
do
    local nested = {value = 10}
    local key = {}
    local mt = {}

    local original = setmetatable({
        [1] = 15,
        [key] = "special",
        nested = nested
    }, mt)

    local copy = table.clone(original)

    assert(copy ~= original)
    assert(copy[1] == 15)
    assert(copy[key] == "special")
    assert(copy.nested == nested)
    assert(getmetatable(copy) == mt)

    copy[1] = 99
    assert(original[1] == 15)
end

-- table.find
do
    local values = {10, 20, 30, 20}

    assert(table.find(values, 20) == 2)
    assert(table.find(values, 20, 3) == 4)
    assert(table.find(values, 99) == nil)
    assert(table.find(values, nil) == nil)

    local ok = pcall(table.find, values, 20, 0)
    assert(not ok)

    local mt = {
        __eq = function(a, b)
            return a.id == b.id
        end
    }

    local a = setmetatable({id = 5}, mt)
    local b = setmetatable({id = 5}, mt)

    assert(table.find({a}, b) == 1)
end

-- table.keys
do
    local source = {alpha = 10, beta = 20}
    local keys = table.keys(source)

    assert(#keys == 2)

    local found = {}
    for _, key in ipairs(keys) do
        found[key] = true
    end

    assert(found.alpha)
    assert(found.beta)
end

-- table.values
do
    local values = table.values({
        alpha = 30,
        beta = 10,
        gamma = 20
    })

    assert(#values == 3)

    table.sort(values)

    assert(values[1] == 10)
    assert(values[2] == 20)
    assert(values[3] == 30)
end

-- table.map
do
    local source = {1, 2, 3}

    local result = table.map(source, function(value, index)
        return value * 2 + index
    end)

    assert(result[1] == 3)
    assert(result[2] == 6)
    assert(result[3] == 9)

    assert(source[1] == 1)

    local sparse = table.map(source, function(value)
        if value == 2 then
            return nil
        end

        return value * 3
    end)

    assert(rawget(sparse, 1) == 3)
    assert(rawget(sparse, 2) == nil)
    assert(rawget(sparse, 3) == 9)
end

-- table.filter
do
    local source = {10, 20, 30, 40}

    local result = table.filter(source, function(_, index)
        return index % 2 == 0
    end)

    assert(#result == 2)
    assert(result[1] == 20)
    assert(result[2] == 40)

    local empty = table.filter(source, function()
        return false
    end)

    assert(next(empty) == nil)
    assert(#source == 4)
end

-- Invalid argument handling
do
    assert(not pcall(table.clear, 123))
    assert(not pcall(table.clone, "invalid"))
    assert(not pcall(table.keys, nil))
    assert(not pcall(table.values, true))
    assert(not pcall(table.map, {}, 123))
    assert(not pcall(table.filter, {}, nil))
end

print("Quvrena table library tests passed")
