-- Quvrena math library tests

local function near(actual, expected)
    assert(
        math.abs(actual - expected) <= 1e-10,
        ("expected %.17g, got %.17g"):format(expected, actual)
    )
end

local function mustFail(fn)
    local ok = pcall(fn)
    assert(not ok, "expected an error")
end

-- Original Lua functionality
assert(type(math.abs) == "function")
assert(type(math.floor) == "function")
assert(type(math.ceil) == "function")
assert(type(math.random) == "function")
assert(type(math.tointeger) == "function")

-- 1. clamp
do
    assert(math.clamp(50, 0, 100) == 50)
    assert(math.clamp(-10, 0, 100) == 0)
    assert(math.clamp(150, 0, 100) == 100)

    assert(math.clamp(5, 5, 5) == 5)
    assert(math.clamp(-5, -10, -1) == -5)

    assert(math.clamp(2.5, 0, 10) == 2.5)

    -- Preserve numeric subtype
    assert(math.type(math.clamp(5, 0, 10)) == "integer")
    assert(math.type(math.clamp(5.0, 0, 10)) == "float")

    -- Exact 64-bit integer preservation
    local maximum = math.maxinteger
    local minimum = math.mininteger

    assert(math.clamp(maximum, minimum, maximum) == maximum)
    assert(math.clamp(minimum, minimum, maximum) == minimum)

    mustFail(function()
        math.clamp(5, 10, 0)
    end)
end

-- 2. lerp
do
    near(math.lerp(0, 100, 0), 0)
    near(math.lerp(0, 100, 0.25), 25)
    near(math.lerp(0, 100, 0.5), 50)
    near(math.lerp(0, 100, 1), 100)

    -- Extrapolation
    near(math.lerp(0, 100, 1.5), 150)
    near(math.lerp(0, 100, -0.5), -50)

    -- Reversed endpoints
    near(math.lerp(100, 0, 0.25), 75)

    assert(math.type(math.lerp(0, 10, 0)) == "float")

    -- Opposite-sign endpoints near floating-point limits
    assert(math.lerp(1e308, -1e308, 0.5) == 0)
end

-- 3. round
do
    assert(math.round(1.2) == 1)
    assert(math.round(1.5) == 2)
    assert(math.round(1.8) == 2)

    assert(math.round(-1.2) == -1)
    assert(math.round(-1.5) == -2)
    assert(math.round(-1.8) == -2)

    assert(math.round(0.5) == 1)
    assert(math.round(-0.5) == -1)
    assert(math.round(0) == 0)

    -- Values immediately below halfway
    assert(math.round(0.49999999999999994) == 0)
    assert(math.round(-0.49999999999999994) == 0)

    -- Preserve exact integer values
    assert(math.round(math.maxinteger) == math.maxinteger)
    assert(math.round(math.mininteger) == math.mininteger)

    assert(math.type(math.round(2.5)) == "integer")

    -- Large float outside Lua integer range
    assert(math.round(1e100) == 1e100)
    assert(math.type(math.round(1e100)) == "float")
end

-- 4. sign
do
    assert(math.sign(-100) == -1)
    assert(math.sign(-0.5) == -1)

    assert(math.sign(0) == 0)
    assert(math.sign(0.0) == 0)
    assert(math.sign(-0.0) == 0)

    assert(math.sign(0.5) == 1)
    assert(math.sign(100) == 1)

    assert(math.sign(math.mininteger) == -1)
    assert(math.sign(math.maxinteger) == 1)

    assert(math.type(math.sign(2.5)) == "integer")
end

-- 5. mapRange
do
    near(math.mapRange(0, 0, 100, 0, 1), 0)
    near(math.mapRange(50, 0, 100, 0, 1), 0.5)
    near(math.mapRange(100, 0, 100, 0, 1), 1)

    near(math.mapRange(5, 0, 10, 0, 100), 50)
    near(math.mapRange(5, 0, 10, 100, 0), 50)

    -- Reversed source range
    near(math.mapRange(2.5, 10, 0, 0, 100), 75)

    -- Extrapolation
    near(math.mapRange(15, 0, 10, 0, 100), 150)
    near(math.mapRange(-5, 0, 10, 0, 100), -50)

    -- Large values that overflow a naive subtraction
    near(math.mapRange(0, -1e308, 1e308, 0, 100), 50)

    assert(math.type(
        math.mapRange(5, 0, 10, 0, 100)
    ) == "float")

    mustFail(function()
        math.mapRange(5, 10, 10, 0, 100)
    end)
end

-- 6. Invalid values and overflow
do
    local nan = math.huge - math.huge

    mustFail(function()
        math.clamp(nan, 0, 1)
    end)

    mustFail(function()
        math.sign(math.huge)
    end)

    mustFail(function()
        math.round(-math.huge)
    end)

    mustFail(function()
        math.lerp(0, 1, nan)
    end)

    mustFail(function()
        math.mapRange(math.huge, 0, 1, 0, 10)
    end)

    mustFail(function()
        math.lerp(1e308, -1e308, 2)
    end)

    -- Only actual Lua numbers are accepted
    mustFail(function()
        math.sign("10")
    end)

    mustFail(function()
        math.clamp("5", 0, 10)
    end)

    mustFail(function()
        math.mapRange(5, 0, 10, "0", 100)
    end)
end

print("Quvrena math library tests passed")
