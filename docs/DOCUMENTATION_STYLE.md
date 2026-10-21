# Quvrena Documentation Style Guide

> **Document type:** Contributor guide  
> **Status:** Accepted  
> **Last reviewed:** 2026-10-22  
> **Scope:** Markdown documentation maintained in `docs/`.

This guide defines a consistent, practical format for Quvrena documentation. The goal is to make public API contracts easy to find, compare, implement, test, and maintain without confusing proposed behavior with shipped behavior.

## 1. Language and markup

- Write repository documentation **in English**, including headings, tables, API descriptions, and examples. Keep identifiers, file paths, commands, and module names in their original spelling.
- Use GitHub Flavored Markdown (`.md`), UTF-8, and LF line endings. Use one `#` heading per document, then `##` sections and `###` subsections; do not skip heading levels.
- Keep paragraphs short and use lists/tables only where they clarify a contract or comparison. Do not use emoji, decorative banners, or status badges in normative documents.
- Put language labels on fenced code blocks (`lua`, `c`, `cmake`, `powershell`, `bash`, `json`, etc.). Ensure examples are valid in the documented runtime; mark pseudocode explicitly.
- Prefer **relative Markdown links** for repository files, so links work in branches and pull requests. Use authoritative external sources for standards and external dependencies.
- Use backticks for exact identifiers, functions, options, paths, commands, file names, and string literals.
- Avoid repeating the same API definition across documents. An API specification is the source of truth; guides link back to it.

## 2. Document types

| Type | Purpose | Typical sections |
|---|---|---|
| API specification | Normative, externally observable contract | Goals, public API, semantics, errors, limits, compatibility, verification |
| Architecture design | Components and internal trade-offs | Context, requirements, design, alternatives, risks, testing |
| Proposal | Suggested change that is not yet accepted | Problem, proposal, alternatives, open questions, decision |
| Guide | Task-oriented instructions | Prerequisites, steps, examples, troubleshooting |
| Reference | Stable lookup material | Definitions, tables, options, examples, links |
| Contributor guide | Repository conventions | Rules, workflow, checks, examples |

Use the closest document type, not a generic template with irrelevant empty sections. Start new documents from [_TEMPLATE.md](_TEMPLATE.md) and remove non-applicable sections.

## 3. Metadata and status

Every document starts with its H1 title and a short metadata block immediately below it. Mandatory metadata: **Document type**, **Last reviewed**, and an appropriate **status**. API specifications additionally have **Specification status**, **Implementation status**, **API stability**, **API version**, **Compatibility**, and **Scope**. Other document types can use a single **Status** field.

### Specification status (API contracts)

| Value | Meaning |
|---|---|
| Draft | Proposed or under discussion; not a binding contract |
| Accepted | Public behavior is agreed; changes require explicit review |
| Superseded | Replaced by a linked newer contract |

### Implementation status (API contracts)

| Value | Meaning |
|---|---|
| Not started | No implementation exists in the target branch |
| In progress | Work is ongoing or exists only in an unmerged feature branch |
| Implemented | Present in the target branch, with implementation and tests linked |
| Partial | Only a documented subset is implemented; missing pieces must be listed |
| Removed | No longer available; replacement or migration must be linked |

When **Implemented**, name the target branch, e.g. `Implemented (main)`. An unmerged implementation is **In progress**, even if its feature branch has green CI.

### API stability

| Value | Meaning |
|---|---|
| Experimental | API can change in future releases; document compatibility caveats |
| Stable | Public compatibility commitment has been explicitly adopted |
| Deprecated | API remains available but should not be used for new code; link replacement |

Implementation status and stability are independent: an implemented API may still be experimental. **Never infer Stable merely from passing tests or CI.**

For guides or other non-API documents use `Status: Draft | Accepted | Deprecated | Superseded`, as applicable. If replaced, include a relative link to the successor.

`Last reviewed` uses ISO 8601 calendar dates (`YYYY-MM-DD`) and changes only following a substantive review. `API version` refers to the contract, not the date or Quvrena runtime version; do not bump it for formatting-only changes.

## 4. Recommended API specification structure

For API contracts, use these sections in this order when applicable:

1. **Goals and non-goals** - purpose and exclusions.
2. **Module availability and public surface** - imports, names, signatures, compatibility.
3. **Representations and semantics** - types, defaults, ownership, corner cases.
4. **Operations and options** - detailed signatures, behavior, default values.
5. **Errors and limits** - failure mode, diagnostics, resource limits.
6. **Examples** - minimal valid, errors, nontrivial usage.
7. **Implementation and verification** - actual files, tests, build switches, and limitations.
8. **References** - related docs and external standards.

Numbered `##` headings are allowed in API specifications, as in [STDLIB_JSON.md](STDLIB_JSON.md). Use descriptive, unnumbered headings for guides. Do not renumber accepted contracts solely to make them cosmetically match the template.

## 5. Normative requirements and examples

- Only use uppercase **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** when expressing normative requirements (in the RFC 2119 / RFC 8174 sense). Explain behavior with normal prose when it is informational, not a guarantee.
- Explain defaults and boundary conditions explicitly. For Lua/C interfaces, specify argument errors vs. data errors and return types, including `nil`/`false` distinctions.
- Examples must be consistent with real supported syntax. If an example requires a later version or a non-default build option, say so.
- Separate **Current behavior**, **Proposed changes**, and **Known limitations**; never imply incomplete work is already shipped.
- Avoid volatile claims such as an unqualified “all tests currently pass.” Link to CI and describe what it validates; retain historical results only with commit or run identifiers if needed.

## 6. Verification and maintenance

- Every implemented module API document SHOULD link to its primary source, tests, and configuration/build entry point.
- Prefer deterministic examples/tests covering success, failure, edge conditions, and embedded use where applicable. Document resource ceilings and platform differences.
- When changing behavior, update API specification, tests, and implementation together in the same PR; review compatibility impact and whether the API version must change.
- When a proposal is accepted, update **Specification status**. When implementation reaches the target branch, update **Implementation status**. When compatibility is formally promised, update **API stability**.
- Keep documentation changes in the same feature PR when practical. If the CI workflow filters `paths`, do not assume a docs-only push triggered tests.

## 7. References

- [GitHub Flavored Markdown](https://github.github.com/gfm/)
- [RFC 2119 - Key words for use in RFCs](https://www.rfc-editor.org/rfc/rfc2119)
- [RFC 8174 - Ambiguity of Uppercase vs Lowercase](https://www.rfc-editor.org/rfc/rfc8174)
