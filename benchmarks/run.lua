local iterations = tonumber(arg[1]) or 1000000
local repetitions = tonumber(arg[2]) or 7

assert(iterations >= 1000 and iterations % 1 == 0)
assert(repetitions >= 1 and repetitions % 1 == 0)

local benchmarks = {}

local function register(name, fn)
    benchmarks[#benchmarks + 1] = {
        name = name,
        run = fn
    }
end

-- Arithmetic performance
register("arithmetic", function()
    local sum = 0

    for i = 1, iterations do
        sum = sum + ((i * 3) % 97)
    end

    return sum
end)

-- Table field read/write performance
register("table_fields", function()
    local entity = {
        x = 0,
        vx = 3
    }

    for i = 1, iterations do
        entity.x = entity.x + entity.vx
    end

    return entity.x
end)

-- Lua function call performance
register("lua_calls", function()
    local function increment(x)
        return x + 1
    end

    local value = 0

    for i = 1, iterations do
        value = increment(value)
    end

    return value
end)

-- Table allocation and garbage collection
register("table_allocation", function()
    local sum = 0
    local count = math.floor(iterations / 5)

    for i = 1, count do
        local object = {
            id = i,
            value = i + 1
        }

        sum = sum + object.value
    end

    return sum
end)

local function median(values)
    table.sort(values)

    local n = #values
    local middle = math.floor((n + 1) / 2)

    if n % 2 == 1 then
        return values[middle]
    end

    return (values[n / 2] + values[n / 2 + 1]) / 2
end

local function measure(fn)
    local values = {}

    -- One warmup run followed by measured runs
    for run = 0, repetitions do
        collectgarbage("collect")

        local start = os.clock()
        local result = fn()
        local elapsed = (os.clock() - start) * 1000

        assert(type(result) == "number")

        if run > 0 then
            values[#values + 1] = elapsed
        end
    end

    return median(values)
end

print("benchmark,median_cpu_ms,iterations,repetitions")

for _, benchmark in ipairs(benchmarks) do
    local elapsed = measure(benchmark.run)

    print(string.format(
        "%s,%.3f,%d,%d",
        benchmark.name,
        elapsed,
        iterations,
        repetitions
    ))
end
