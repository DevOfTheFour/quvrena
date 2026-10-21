cmake_minimum_required(VERSION 3.20)

project(Quvrena VERSION 0.1.0 LANGUAGES C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

set(LUA_SRC "${CMAKE_CURRENT_SOURCE_DIR}/lua/src")

if(NOT EXISTS "${LUA_SRC}/lua.h")
    message(FATAL_ERROR "Lua 5.5.1 sources not found in lua/src")
endif()

# Lua 5.5.1 core and standard libraries
set(LUA_SOURCES
    lapi.c
    lauxlib.c
    lbaselib.c
    lcode.c
    lcorolib.c
    lctype.c
    ldblib.c
    ldebug.c
    ldo.c
    ldump.c
    lfunc.c
    lgc.c
    linit.c
    liolib.c
    llex.c
    lmathlib.c
    lmem.c
    loadlib.c
    lobject.c
    lopcodes.c
    loslib.c
    lparser.c
    lstate.c
    lstring.c
    lstrlib.c
    ltable.c
    ltablib.c
    ltm.c
    lundump.c
    lutf8lib.c
    lvm.c
    lzio.c
)

list(TRANSFORM LUA_SOURCES PREPEND "${LUA_SRC}/")

add_library(quvrena_core STATIC ${LUA_SOURCES})

target_include_directories(quvrena_core PUBLIC
    "${LUA_SRC}"
)

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    target_compile_definitions(quvrena_core PUBLIC
        LUA_USE_LINUX
    )
    target_link_libraries(quvrena_core PUBLIC
        m ${CMAKE_DL_LIBS}
    )
elseif(UNIX)
    target_link_libraries(quvrena_core PUBLIC m)
endif()

add_executable(quvrena "${LUA_SRC}/lua.c")
target_link_libraries(quvrena PRIVATE quvrena_core)

if(UNIX)
    set_target_properties(quvrena PROPERTIES
        ENABLE_EXPORTS ON
    )
endif()

add_executable(quvrenac "${LUA_SRC}/luac.c")
target_link_libraries(quvrenac PRIVATE quvrena_core)

# MSVC Debug builds use larger native stack frames.
# Reserve 8 MiB for the interpreter stack during debugging.
if(MSVC)
    target_link_options(quvrena PRIVATE
        "$<$<CONFIG:Debug>:/STACK:8388608>"
    )
endif()

option(
    QUVRENA_REQUIRE_UPSTREAM_TESTS
    "Require Lua upstream compatibility tests"
    OFF
)

include(CTest)

if(BUILD_TESTING)
    add_test(
        NAME quvrena_version
        COMMAND $<TARGET_FILE:quvrena> -v
    )

    add_test(
        NAME quvrena_smoke
        COMMAND $<TARGET_FILE:quvrena>
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.lua"
    )

    add_test(
        NAME quvrena_compiler
        COMMAND $<TARGET_FILE:quvrenac>
            -p "${CMAKE_CURRENT_SOURCE_DIR}/tests/smoke.lua"
    )

    # Quvrena language extensions
    add_test(
        NAME quvrena_continue
        COMMAND $<TARGET_FILE:quvrena>
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/language/continue.lua"
    )

    add_test(
        NAME quvrena_compound_assignment
        COMMAND $<TARGET_FILE:quvrena>
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/language/compound_assignment.lua"
    )

    add_test(
        NAME quvrena_language_regression
        COMMAND $<TARGET_FILE:quvrena>
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/language/regression.lua"
    )

    add_test(
        NAME quvrena_language_regression_compile
        COMMAND $<TARGET_FILE:quvrenac>
            -p "${CMAKE_CURRENT_SOURCE_DIR}/tests/language/regression.lua"
    )

    # Quvrena table extensions
    add_test(
        NAME quvrena_table_extensions
        COMMAND $<TARGET_FILE:quvrena>
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/std/table.lua"
    )

    add_test(
        NAME quvrena_table_extensions_compile
        COMMAND $<TARGET_FILE:quvrenac>
            -p "${CMAKE_CURRENT_SOURCE_DIR}/tests/std/table.lua"
    )

    # Quvrena string extensions
    add_test(
        NAME quvrena_string_extensions
        COMMAND $<TARGET_FILE:quvrena>
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/std/string.lua"
    )

    add_test(
        NAME quvrena_string_extensions_compile
        COMMAND $<TARGET_FILE:quvrenac>
            -p "${CMAKE_CURRENT_SOURCE_DIR}/tests/std/string.lua"
    )

    add_executable(quvrena_embed_test
        tests/embed_smoke.c
    )

    target_link_libraries(quvrena_embed_test PRIVATE
        quvrena_core
    )

    add_test(
        NAME quvrena_c_api
        COMMAND $<TARGET_FILE:quvrena_embed_test>
    )

    # Official Lua compatibility suite
    set(LUA_TESTS_DIR
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/upstream/lua-5.5.1-tests"
    )

    if(EXISTS "${LUA_TESTS_DIR}/all.lua")
        add_test(
            NAME quvrena_upstream_compatibility
            COMMAND $<TARGET_FILE:quvrena>
            -e "_U=true"
            all.lua
        )

        set_tests_properties(
            quvrena_upstream_compatibility
            PROPERTIES
            WORKING_DIRECTORY "${LUA_TESTS_DIR}"
            TIMEOUT 600
            PASS_REGULAR_EXPRESSION "final OK"
        )
    else()
        if(QUVRENA_REQUIRE_UPSTREAM_TESTS)
            message(FATAL_ERROR
                "Lua upstream tests are required but missing. "
                "Run scripts/setup-tests.ps1"
            )
        else()
            message(STATUS
                "Upstream tests unavailable. Run scripts/setup-tests.ps1"
            )
        endif()
    endif()
endif()
