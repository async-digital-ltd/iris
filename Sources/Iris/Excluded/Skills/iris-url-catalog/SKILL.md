---
name: iris-url-catalog
description: "Extract every supported URL pattern from the URLCodec into a structured Markdown or JSON catalog. Lists patterns, parameters, and examples. Use when asked to 'catalog links', 'list URL patterns', 'document links', 'export URL schema', or for QA/API documentation."
compatible_versions: ">=1.0.0"
---

# Iris URL Catalog

Extracts every supported URL pattern from a project's `URLParsing`-conforming codec and produces a structured catalog with patterns, parameters, examples, and validation results.

## Prerequisites

- An existing iOS project with Iris integrated
- A `URLParsing`-conforming struct (typically `LinkURLCodec`) with `parse(_:)` and `url(for:)` methods
- A `LinkRoute` constants enum centralising scheme, hosts, paths, and query params

---

## Phase 0 — Version Check

1. **Find the Iris dependency:**
   - Check the project's `Package.swift` for a `.package(path:)` or `.package(url:)` referencing Iris
   - If not found, check `*.xcodeproj/project.pbxproj` for a package reference
   - If not found at all, **stop** and tell the user no Iris integration was detected

2. **Read the version:**
   - **Local path dependency:** Run `git -C <path> describe --tags --abbrev=0` to get the latest semver tag
   - **Remote dependency:** Read `Package.resolved` (or `*.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`) and find the `"Iris"` entry's `"version"` field
   - If no version can be determined, warn the user and ask whether to proceed

3. **Compare:** This skill is compatible with Iris `>=1.0.0`. If the resolved version is older or unrecognised, warn and ask whether to proceed.

---

## Phase 1 — Discover the URL Codec

### Step 1: Find the codec file

```
grep -rl "URLParsing" --include="*.swift" .
```

Read the file to identify the `URLParsing`-conforming struct (typically named `LinkURLCodec`).

### Step 2: Read the `parse(_:)` method

Extract every URL pattern by analysing the switch/case structure:

- **Scheme:** The `url.scheme` guard value
- **Hosts:** Each `case` arm matching `url.host` (e.g. `LinkRoute.Host.inbox`)
- **Paths:** Any `url.pathComponents` or `url.lastPathComponent` extraction
- **Query params:** Any `URLComponents(url:).queryItems` extraction (e.g. `?name=`, `?replyTo=`, `?action=`)
- **Return values:** The intent case each branch returns (e.g. `.showInbox`, `.showBadge(name:)`)

Pay attention to:
- Nested conditionals within a host case (e.g. compose with different `action` query values)
- Optional vs required parameters (presence of `guard` or `if let` vs unconditional access)
- Type coercions (e.g. `UUID(uuidString:)` for path segments)
- Empty-string guards (e.g. `.nonEmpty()`)

### Step 3: Read the `url(for:)` method

Extract every buildable pattern by analysing the switch body:

- Each intent case and the URL it constructs via the `make(host:path:query:)` helper
- Query items and their names
- Path components appended

### Step 4: Read the `LinkRoute` constants enum

Extract:
- `scheme` — the URL scheme string
- `Host` — all host constants
- `Path` — all path constants (if present)
- `QueryParam` / `Query` — all query parameter name constants (if present)

### Step 5: Read the intent enum

Find the intent enum (the type returned by `parse(_:)`):

```
grep -l "case unknown(URL)" --include="*.swift" .
```

Read all cases to build a complete list of intents for validation in Phase 3.

---

## Phase 2 — Generate Catalog

Build the catalog from the data extracted in Phase 1. Produce two output formats depending on user preference.

### Markdown Table (default)

```markdown
# Link URL Catalog

**Scheme:** `<scheme>`
**Generated:** <date>

## Push Routes

| URL Pattern | Intent | Parameters | Example |
|-------------|--------|------------|---------|
| `<scheme>://<host>` | `.<intent>` | none | `<scheme>://<host>` |
| `<scheme>://<host>/<path>?<param>={value}` | `.<intent>(<param>:)` | `<param>: <Type>` (required) | `<scheme>://<host>/<path>?<param>=example` |

## Sheet Routes

| URL Pattern | Intent | Parameters | Example |
|-------------|--------|------------|---------|
| `<scheme>://<host>` | `.<intent>` | `<param>: <Type>` (optional) | `<scheme>://<host>?<param>=value` |

## Parameter Reference

| Parameter | Type | Location | Required | Used By |
|-----------|------|----------|----------|---------|
| `<name>` | `<Type>` | query / path | yes / no | `<intent>` |
```

**Generation rules:**

- **Grouping:** Determine whether each intent is a push or sheet route by tracing through the `NavigationFlow.operations(intent:)` method. Each `Step.nav(.push(_))` produces a push route; each `Step.nav(.present(_))` produces a sheet route. `Step.effect(_)` cases are consumer side-effects and don't appear as routes.
- **Parameters:**
  - Path parameters (e.g. UUID in `/<uuid>`): show as `{<name>}` in the pattern, type from the intent case's associated value
  - Query parameters: show as `?<name>={<name>}` in the pattern
  - Required vs optional: required if `parse(_:)` uses `guard` or returns `.unknown` when absent; optional if the code falls through to a default value
- **Examples:** Generate a realistic example URL for each pattern:
  - UUID: use `550e8400-e29b-41d4-a716-446655440000`
  - String: use a short contextual word (e.g. `people` for a badge name, `report.pdf` for a file name)
  - No params: the pattern itself is the example
- **Complex query logic:** When a single host handles multiple query parameter combinations (e.g. compose with `action=attach`, `action=preview&file=<name>`), list each distinct combination as a separate row.

### JSON (if requested)

```json
{
  "scheme": "<scheme>",
  "generated": "<date>",
  "routes": [
    {
      "pattern": "<scheme>://<host>",
      "intent": "<intentCase>",
      "parameters": [],
      "example": "<scheme>://<host>",
      "navigation": "push"
    },
    {
      "pattern": "<scheme>://<host>?<param>={value}",
      "intent": "<intentCase>",
      "parameters": [
        {
          "name": "<param>",
          "type": "<Type>",
          "location": "query",
          "required": true
        }
      ],
      "example": "<scheme>://<host>?<param>=example",
      "navigation": "sheet"
    }
  ]
}
```

---

## Phase 3 — Validation

Cross-reference the catalog against the intent enum to surface gaps.

### Check 1 — Undocumented intents

For every intent case (excluding `.unknown`):
- Verify it appears as a return value in `parse(_:)`
- If an intent has no URL pattern that produces it, flag it:

```
WARN: Intent `.showSettings` has no URL pattern — not reachable via link
```

### Check 2 — Parse / Build symmetry

Compare intents covered by `parse(_:)` with those covered by `url(for:)`:

- Intent parseable but not buildable:
  ```
  WARN: Intent `.showProfile(id:)` is parseable but not buildable
    → Cannot generate shareable URLs for this link
  ```
- Intent buildable but not parseable:
  ```
  WARN: Intent `.showProfile(id:)` is buildable but not parseable
    → Generated URLs cannot be opened by the app
  ```

### Check 3 — Dead patterns

Look for URL patterns in `parse(_:)` that map to `.unknown` or are unreachable due to earlier guards. Flag as:

```
WARN: URL pattern `<scheme>://<host>/<path>` always returns .unknown due to guard on line N
```

### Validation summary

Print a summary table after the catalog:

```markdown
## Validation

| Check | Status | Details |
|-------|--------|---------|
| All intents have URL patterns | PASS / WARN | N undocumented |
| Parse/Build symmetry | PASS / WARN | N asymmetric |
| No dead patterns | PASS / WARN | N unreachable |
```

---

## Phase 4 — Output

1. **Print** the catalog to the conversation.
2. **Write to file:** `<ProjectRoot>/link-catalog.md` (or `link-catalog.json` if JSON was requested).
3. **Ask the user** if they prefer a different output location before writing. If they confirm the default or provide an alternative, write there.

---

## Edge Cases

### No URLParsing conformance found
Report: "No `URLParsing`-conforming type found. Run `iris-bootstrap` first."

### Multiple codecs
Unusual but possible if the project has multiple URL schemes or modules. Generate a separate catalog section for each codec, clearly labelled with the codec type name and scheme.

### Complex query logic
When a single host handles multiple query parameter combinations (e.g. compose with `action=attach`, `action=preview&file=<name>`, `action=attach&preview=<name>`), list each distinct URL pattern as a separate row. Trace every code path through the `parse(_:)` conditionals to ensure no combination is missed.

### Nested intents
When an intent case wraps a sub-intent type (e.g. `.compose(ComposeIntent)` where `ComposeIntent` has cases like `.standard`, `.attach`, `.preview`), expand each sub-intent into its own row with the full URL pattern that produces it.

### Constants enum missing
If `LinkRoute` is not found, extract scheme, hosts, and query param names directly from string literals in the codec. Flag a warning:
```
WARN: No LinkRoute constants enum found — URL strings are hardcoded in the codec
```

### Intent enum in a separate module
If the intent type is defined in a dependency (e.g. a shared module), follow the import to locate and read it. The skill should still catalog all cases.
