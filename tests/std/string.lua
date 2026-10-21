-- Quvrena string library tests

-- Original Lua functions remain available
assert(type(string.find) == "function")
assert(type(string.gsub) == "function")
assert(type(string.match) == "function")
assert(type(string.pack) == "function")

-- 1. split
do
    local parts = string.split("a,b,c", ",")
    assert(#parts == 3)
    assert(parts[1] == "a")
    assert(parts[2] == "b")
    assert(parts[3] == "c")

    -- Preserve empty fields
    parts = string.split("a,,b,", ",")
    assert(#parts == 4)
    assert(parts[1] == "a")
    assert(parts[2] == "")
    assert(parts[3] == "b")
    assert(parts[4] == "")

    -- Multi-byte delimiter
    parts = string.split("a::b::c", "::")
    assert(table.concat(parts, ",") == "a,b,c")

    -- Limit number of splits
    parts = string.split("a,b,c", ",", 1)
    assert(#parts == 2)
    assert(parts[1] == "a")
    assert(parts[2] == "b,c")

    parts = string.split("a,b", ",", 0)
    assert(#parts == 1)
    assert(parts[1] == "a,b")

    -- Empty input
    parts = string.split("", ",")
    assert(#parts == 1)
    assert(parts[1] == "")

    -- Literal separator, not a Lua pattern
    parts = string.split("a.b.c", ".")
    assert(table.concat(parts, ",") == "a,b,c")
end

-- 2. trim
do
    assert(string.trim("  hello  ") == "hello")
    assert(string.trim("\t\nhello\r\n") == "hello")
    assert(string.trim("hello") == "hello")
    assert(string.trim("   ") == "")
    assert(string.trim("") == "")

    -- Custom trim characters
    assert(string.trim("--hello--", "-") == "hello")
    assert(string.trim("...test...", ".") == "test")
    assert(string.trim(" x ", "") == " x ")

    -- Only trim the ends
    assert(string.trim(" a b ") == "a b")
end

-- 3. startsWith
do
    assert(string.startsWith("Quvrena", "Qu"))
    assert(string.startsWith("Quvrena", ""))
    assert(string.startsWith("", ""))

    assert(not string.startsWith("Quvrena", "qu"))
    assert(not string.startsWith("abc", "abcd"))
    assert(not string.startsWith("", "a"))
end

-- 4. endsWith
do
    assert(string.endsWith("main.lua", ".lua"))
    assert(string.endsWith("Quvrena", "rena"))
    assert(string.endsWith("abc", ""))
    assert(string.endsWith("", ""))

    assert(not string.endsWith("main.lua", ".txt"))
    assert(not string.endsWith("abc", "abcd"))
end

-- 5. replace
do
    local result, count

    result, count = string.replace("a-b-a", "a", "x")
    assert(result == "x-b-x")
    assert(count == 2)

    result, count = string.replace("aaaa", "aa", "X")
    assert(result == "XX")
    assert(count == 2)

    result, count = string.replace("aaaa", "aa", "X", 1)
    assert(result == "Xaa")
    assert(count == 1)

    result, count = string.replace("abc", "b", "")
    assert(result == "ac")
    assert(count == 1)

    result, count = string.replace("abc", "x", "y")
    assert(result == "abc")
    assert(count == 0)

    result, count = string.replace("abc", "a", "x", 0)
    assert(result == "abc")
    assert(count == 0)

    -- Replacement is literal, not pattern-based
    result, count = string.replace("a.b", ".", "!")
    assert(result == "a!b")
    assert(count == 1)
end

-- 6. Binary strings, including embedded NUL
do
    local parts = string.split("a\0b\0", "\0")

    assert(#parts == 3)
    assert(parts[1] == "a")
    assert(parts[2] == "b")
    assert(parts[3] == "")

    assert(string.startsWith("\0abc", "\0"))
    assert(string.endsWith("abc\0", "\0"))

    assert(string.trim("\0abc\0", "\0") == "abc")

    local result, count =
        string.replace("a\0b\0", "\0", "!")

    assert(result == "a!b!")
    assert(count == 2)
end

-- 7. UTF-8 data
do
    local parts = string.split("яблоко|груша", "|")

    assert(parts[1] == "яблоко")
    assert(parts[2] == "груша")

    assert(string.startsWith("Привет", "При"))
    assert(string.endsWith("Привет", "вет"))

    local result = string.replace(
        "Привет, мир!",
        "мир",
        "Quvrena"
    )

    assert(result == "Привет, Quvrena!")
end

-- 8. String method syntax
do
    local text = "  main.lua  "
    local trimmed = text:trim()

    assert(trimmed == "main.lua")
    assert(trimmed:endsWith(".lua"))
    assert(trimmed:startsWith("main"))

    local parts = ("a,b"):split(",")
    assert(parts[1] == "a")
    assert(parts[2] == "b")
end

-- 9. Invalid arguments
do
    assert(not pcall(string.split, "abc", ""))
    assert(not pcall(string.split, "a,b", ",", -1))
    assert(not pcall(string.replace, "abc", "", "x"))
    assert(not pcall(string.replace, "abc", "a", "x", -1))

    assert(not pcall(string.trim, nil))
    assert(not pcall(string.startsWith, "abc", nil))
    assert(not pcall(string.endsWith, "abc", nil))
end

print("Quvrena string library tests passed")
