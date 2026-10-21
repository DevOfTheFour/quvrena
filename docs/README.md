# Quvrena Documentation

> **Document type:** Documentation index  
> **Status:** Accepted  
> **Last reviewed:** 2026-10-22  
> **Scope:** Technical documentation for Quvrena contributors and users.

This directory contains public API contracts and conventions for Quvrena, a scripting language and runtime based on Lua 5.5.1. Public contracts distinguish specification acceptance, actual implementation, and API stability.

## API specifications

| Module | API version | Specification | Implementation | Stability |
|---|---|---|---|---|
| [`std.json`](STDLIB_JSON.md) | v1 | Accepted | Implemented (`main`) | Experimental |

## Documentation maintenance

- [Documentation Style Guide](DOCUMENTATION_STYLE.md) - terminology, structure, metadata, examples, and review rules.
- [API Specification Template](_TEMPLATE.md) - starting point for future native standard-library modules (such as `std.path`).

For implementation details, use the source and test links in the relevant API specification. Do not assume a documented proposal is already available in the runtime; check its **Implementation status**.
