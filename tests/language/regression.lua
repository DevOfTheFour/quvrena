-- Quvrena regression tests

-- Contextual 'continue' with compound operators
do
    local continue = 20

    continue += 2
    assert(continue == 22)

    continue -= 3
    assert(continue == 19)

    continue *= 2
    assert(continue == 38)

    continue /= 2
    assert(continue == 19.0)
    assert(math.type(continue) == "float")

    continue ..= "!"
    assert(continue == "19.0!")

    local counter = 0

    for i = 1, 4 do
        if i < 4 then
            continue
        end

        counter += 1
    end

    assert(counter == 1)
end

-- Continue in descending numeric loops
do
    local result = {}

    for i = 7, 1, -1 do
        if i % 2 == 0 then
            continue
        end

        result[#result + 1] = i
    end

    assert(table.concat(result, ",") == "7,5,3,1")
end

-- Continue in a custom iterator
do
    local calls = 0
    local values = {}

    local function iterator(_, previous)
        calls += 1

        if previous >= 5 then
            return nil
        end

        return previous + 1
    end

    for value in iterator, nil, 0 do
        if value == 3 then
            continue
        end

        values[#values + 1] = value
    end

    assert(calls == 6)
    assert(table.concat(values, ",") == "1,2,4,5")
end

-- Nested to-be-closed variables
do
    local events = {}

    local function resource(name)
        return setmetatable({}, {
            __close = function()
                events[#events + 1] = name
            end
        })
    end

    for i = 1, 2 do
        do
            local outer <close> = resource("outer" .. i)

            do
                local inner <close> = resource("inner" .. i)
                continue
            end
        end
    end

    assert(
        table.concat(events, ",") ==
        "inner1,outer1,inner2,outer2"
    )
end

-- Evaluation order and metamethods
do
    local events = {}

    local oldValue = setmetatable({}, {
        __add = function(_, amount)
            events[#events + 1] = "add"
            return 100 + amount
        end
    })

    local object = setmetatable({}, {
        __index = function(_, key)
            assert(key == "score")
            events[#events + 1] = "read"
            return oldValue
        end,

        __newindex = function(self, key, value)
            assert(key == "score")
            events[#events + 1] = "write"
            rawset(self, key, value)
        end
    })

    local function getObject()
        events[#events + 1] = "table"
        return object
    end

    local function getKey()
        events[#events + 1] = "key"
        return "score"
    end

    local function getAmount()
        events[#events + 1] = "rhs"
        return 5
    end

    getObject()[getKey()] += getAmount()

    assert(rawget(object, "score") == 105)

    assert(
        table.concat(events, ",") ==
        "table,key,read,rhs,add,write"
    )
end

-- Preserve destination even when __index changes it
do
    local original
    local target

    original = setmetatable({}, {
        __index = function(_, key)
            assert(key == "value")
            target = {value = 100}
            return 10
        end
    })

    target = original
    target.value += 5

    assert(rawget(original, "value") == 15)
    assert(target.value == 100)
end

-- Complex expressions and register reuse
do
    local data = {
        nested = {
            {value = 1},
            {value = 2}
        }
    }

    local function index()
        return 2
    end

    for i = 1, 100 do
        data.nested[index()].value += i * 2
    end

    assert(data.nested[2].value == 10102)
end

-- Bytecode serialization and loading
do
    local source = [[
        return function(limit)
            local sum = 0

            for i = 1, limit do
                if i % 2 == 0 then
                    continue
                end

                sum += i
            end

            return sum
        end
    ]]

    local chunk = assert(load(source, "regression", "t"))
    local bytecode = string.dump(chunk)
    local restored = assert(load(bytecode, "regression", "b"))

    local calculate = restored()
    assert(calculate(7) == 16)
end

print("Quvrena M1 regression tests passed")
