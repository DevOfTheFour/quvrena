-- Quvrena continue statement tests

-- 1. Numeric for
do
    local result = {}

    for i = 1, 10 do
        if i % 2 == 0 then
            continue
        end

        result[#result + 1] = i
    end

    assert(table.concat(result, ",") == "1,3,5,7,9")
end

-- 2. While
do
    local i = 0
    local sum = 0

    while i < 5 do
        i = i + 1

        if i % 2 == 0 then
            continue
        end

        sum = sum + i
    end

    assert(sum == 9)
end

-- 3. Generic for
do
    local result = {}

    for _, value in ipairs({1, 2, 3, 4, 5}) do
        if value == 3 then
            continue
        end

        result[#result + 1] = value
    end

    assert(table.concat(result, ",") == "1,2,4,5")
end

-- 4. Repeat until
do
    local i = 0
    local sum = 0

    repeat
        i = i + 1

        local current = i

        if current % 2 == 0 then
            continue
        end

        sum = sum + current
    until i >= 5

    assert(sum == 9)
end

-- 5. Nested loops
do
    local result = {}

    for i = 1, 3 do
        for j = 1, 3 do
            if j == 2 then
                continue
            end

            result[#result + 1] = i * 10 + j
        end
    end

    assert(
        table.concat(result, ",") ==
        "11,13,21,23,31,33"
    )
end

-- 6. Continue and break together
do
    local count = 0

    for i = 1, 10 do
        if i == 2 then
            continue
        end

        if i == 6 then
            break
        end

        count = count + 1
    end

    assert(count == 4)
end

-- 7. To-be-closed variables
do
    local closed = {}

    for i = 1, 3 do
        do
            local guard <close> = setmetatable(
                { id = i },
                {
                    __close = function(self)
                        closed[#closed + 1] = self.id
                    end
                }
            )

            if i < 3 then
                continue
            end
        end
    end

    assert(table.concat(closed, ",") == "1,2,3")
end

-- 8. To-be-closed variables in repeat
do
    local count = 0
    local closed = 0

    repeat
        count = count + 1

        local guard <close> = setmetatable({}, {
            __close = function()
                closed = closed + 1
            end
        })

        if count < 3 then
            continue
        end
    until count == 3

    assert(closed == 3)
end

-- 9. Upvalues survive continue correctly
do
    local functions = {}

    for i = 1, 4 do
        local value = i

        functions[i] = function()
            return value
        end

        if i < 4 then
            continue
        end
    end

    for i = 1, 4 do
        assert(functions[i]() == i)
    end
end

-- 10. Contextual keyword compatibility
do
    local continue = function(x)
        return x * 2
    end

    assert(continue(7) == 14)

    continue = { value = 10 }
    assert(continue.value == 10)

    continue.value = 20
    continue["value"] = 30
    assert(continue.value == 30)

    local other
    continue, other = { value = 40 }, 5

    assert(continue.value == 40)
    assert(other == 5)
end

-- 11. Continue outside loop must fail
do
    local chunk, err = load("continue")

    assert(chunk == nil)
    assert(err:find("continue outside loop", 1, true))
end

-- 12. Cannot skip local declarations in repeat
do
    local chunk, err = load([[
        repeat
            continue
            local value = 10
        until value == 10
    ]])

    assert(chunk == nil)
    assert(err:find("jumps into the scope", 1, true))
end

-- 13. Continue inside a nested function must fail
do
    local chunk, err = load([[
        for i = 1, 5 do
            local function f()
                continue
            end
        end
    ]])

    assert(chunk == nil)
    assert(err:find("continue outside loop", 1, true))
end

print("Quvrena continue tests passed")
