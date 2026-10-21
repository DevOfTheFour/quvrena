-- Quvrena std.json tests

local json = require("std.json")

-- 1. Module registration
do
    assert(type(json) == "table")
    assert(require("std.json") == json)
    assert(package.loaded["std.json"] == json)
    assert(type(package.preload["std.json"]) == "function")

    -- No global variable is introduced
    assert(rawget(_G, "json") == nil)
end

-- 2. Public API
do
    assert(type(json.array) == "function")
    assert(type(json.object) == "function")
    assert(type(json.kind) == "function")
end

-- 3. JSON null singleton
do
    assert(type(json.null) == "userdata")
    assert(json.null ~= nil)
    assert(json.null ~= false)

    local t = {
        value = json.null
    }

    assert(rawget(t, "value") == json.null)
    assert(tostring(json.null) == "json.null")
    assert(getmetatable(json.null) == "std.json.null")
end

-- 4. Empty containers
do
    local array = json.array()
    local object = json.object()

    assert(type(array) == "table")
    assert(type(object) == "table")

    assert(next(array) == nil)
    assert(next(object) == nil)

    assert(json.kind(array) == "array")
    assert(json.kind(object) == "object")

    assert(json.kind({}) == nil)
end

-- 5. Existing table identity
do
    local original = {10, 20, 30}
    local result = json.array(original)

    assert(result == original)
    assert(json.kind(original) == "array")
    assert(#original == 3)
    assert(original[2] == 20)
end

-- 6. Object identity and raw entries
do
    local key = {}
    local data = {
        name = "Quvrena",
        [key] = 123
    }

    assert(json.object(data) == data)
    assert(json.kind(data) == "object")

    assert(rawget(data, "name") == "Quvrena")
    assert(rawget(data, key) == 123)
end

-- 7. Retagging is allowed
do
    local t = {}

    json.array(t)
    assert(json.kind(t) == "array")

    json.object(t)
    assert(json.kind(t) == "object")

    json.array(t)
    assert(json.kind(t) == "array")
end

-- 8. User metatables are preserved
do
    local mt = {
        __index = function()
            return 42
        end
    }

    local t = setmetatable({}, mt)

    json.array(t)

    assert(getmetatable(t) == mt)
    assert(t.missing == 42)
    assert(json.kind(t) == "array")

    json.object(t)

    assert(getmetatable(t) == mt)
    assert(json.kind(t) == "object")
end

-- 9. kind() never infers from contents
do
    assert(json.kind({1, 2, 3}) == nil)
    assert(json.kind({name = "test"}) == nil)

    assert(json.kind(json.null) == nil)
    assert(json.kind(false) == nil)
    assert(json.kind(123) == nil)
    assert(json.kind("hello") == nil)
    assert(json.kind(nil) == nil)
end

-- 10. Tags survive garbage collection
do
    local t = json.array({1, 2, 3})

    collectgarbage("collect")

    assert(json.kind(t) == "array")
end

-- 11. Tags do not keep unreachable tables alive
do
    local weak = setmetatable({}, {
        __mode = "v"
    })

    weak[1] = json.object()

    collectgarbage("collect")
    collectgarbage("collect")

    assert(weak[1] == nil)
end

-- 12. Singleton survives module reload
do
    local old = package.loaded["std.json"]

    package.loaded["std.json"] = nil

    local reloaded = require("std.json")

    assert(reloaded.null == json.null)
    assert(json.kind(json.array()) == "array")
    assert(reloaded.kind(json.array()) == "array")

    package.loaded["std.json"] = old
end

-- 13. Invalid arguments
do
    assert(not pcall(json.array, nil))
    assert(not pcall(json.object, 123))
    assert(not pcall(json.array, "test"))
    assert(not pcall(json.object, false))

    assert(not pcall(json.array, {}, {}))
    assert(not pcall(json.kind))
    assert(not pcall(json.kind, {}, {}))
end

print("Quvrena std.json tests passed")
