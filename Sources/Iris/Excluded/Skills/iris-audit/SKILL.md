---
name: iris-audit
description: "Audit an iOS project's Iris integration for coverage gaps, wiring errors, and URL pattern issues. Checks that every navigable screen has an intent, URL codec mapping, navigation step, coordinator apply case, and view destination. Use when asked to 'audit links', 'check link coverage', 'validate links', or on PR reviews."
compatible_versions: ">=1.0.0"
---

# Iris Audit

Scans an iOS project using Iris for link coverage gaps, wiring errors, and URL pattern quality issues. Reports findings without modifying code.

## Prerequisites

- An existing iOS project with Iris integrated
- Navigation files following the Iris conventions (intent enums, route enums, codec, coordinator, navigation steps)

---

## Phase 0 — Version Check

Same as `iris-bootstrap`:

1. Locate Iris dependency (local path from `Package.swift` or resolved version from `Package.resolved`)
2. Read the version tag
3. If version < `1.0.0` or unrecognised, warn and ask whether to proceed

---

## Phase 1 — Locate Navigation Files

Search the project for the files that make up the Iris integration. These are identified by their imports and protocol conformances.

### Discovery steps

1. **Find all files importing Iris:**
   ```
   grep -rl "import Iris" --include="*.swift" .
   ```

2. **Find intent enums** — look for enums conforming to `Sendable, Equatable` that contain a `case unknown(URL)`:
   ```
   grep -l "case unknown(URL)" --include="*.swift" .
   ```
   Read each file to extract the intent enum name and all its cases.

3. **Find route enums** — look for namespace enums containing `StackRoute` and/or `SheetRoute`:
   ```
   grep -l "enum StackRoute" --include="*.swift" .
   ```
   Read each file to extract route namespace names (e.g. `TopLevel`, `Compose`) and all route cases.

4. **Find navigation flow enums** — look for `NavigationFlow` conformance:
   ```
   grep -l "NavigationFlow" --include="*.swift" .
   ```
   Read each file to extract the flow's `Route`, `SheetRoute`, and `SideEffect` types and the `operations(intent:)` switch body. Each arm returns `[Step<Route, SheetRoute, SideEffect>]`, where `Step.nav(_)` is a structural target the library dispatches and `Step.effect(_)` is a consumer side-effect.

5. **Find URL codec** — look for `URLParsing` conformance:
   ```
   grep -l "URLParsing" --include="*.swift" .
   ```
   Read the file to extract `parse(_:)` and `url(for:)` switch cases.

6. **Find coordinators** — look for `RouteCoordinator` conformance:
   ```
   grep -l "RouteCoordinator" --include="*.swift" .
   ```
   Read each file to extract `apply(_:_:)` switch cases and the `route(baton:)` convert closure.

7. **Find view destinations** — look for `.navigationDestination(for:` and `.sheet(item:`:
   ```
   grep -rn "\.navigationDestination(for:" --include="*.swift" .
   grep -rn "\.sheet(item:" --include="*.swift" .
   ```
   Read surrounding code to extract the switch cases that handle each route.

8. **Find screens reachable only via UI** — look for `.navigationDestination(isPresented:` and `NavigationLink(destination:` and `.sheet(isPresented:`:
   ```
   grep -rn "\.navigationDestination(isPresented:" --include="*.swift" .
   grep -rn "NavigationLink(" --include="*.swift" .
   grep -rn "\.sheet(isPresented:" --include="*.swift" .
   grep -rn "\.fullScreenCover(" --include="*.swift" .
   ```
   These represent screens that navigate via local `@State` booleans rather than route enums — they are **not linkable** by design.

Store all discovered information in a structured mental model before proceeding to checks.

---

## Phase 2 — Run Checks

Execute all 8 checks. For each check, record:
- **Status**: `pass`, `warn`, or `fail`
- **Details**: what was found, what's missing, file path and line number

### Category 1: Coverage Gaps

#### Check 1 — Route cases without intent mapping

For each `StackRoute` and `SheetRoute` case discovered in Phase 1:
- Search the intent enum(s) for a corresponding intent case
- A route is "covered" if an intent exists that, through the navigation step mapping, would cause that route to be navigated to

**Pass criteria:** Every route case has a corresponding intent path.

**How to match:** Read the flow's `operations(intent:)` switch body — each arm returns `Step.nav(.push/.present/...)` values whose payloads are the routes. Trace backwards: step → route. Then check that each route case is reachable from an intent that emits `Step.nav(.push(<route>))` or `Step.nav(.present(<route>))`.

**Report format for failures:**
```
FAIL: Route `TopLevel.StackRoute.badgeInfo` has no intent mapping
  → This screen is only reachable via UI navigation, not links
  → File: LinkableRoutes.swift:25
```

#### Check 2 — Intent cases without URL codec mapping

For each intent case (excluding `.unknown`):
- Check it appears as a case in the codec's `parse(_:)` return statements
- Check it appears as a case in the codec's `url(for:)` switch

**Pass criteria:** Every intent case has both parse and build coverage.

**Report format for failures:**
```
FAIL: Intent `.showProfile(id:)` has no URL parse mapping
  → Links cannot reach this intent
  → File: Intent.swift:18
```

#### Check 3 — Intent cases without flow mapping

For each intent case (excluding `.unknown`):
- Check it appears in the flow's `operations(intent:)` switch body

**Pass criteria:** Every intent case has a mapping (even if it returns `[]`).

**Report format for failures:**
```
FAIL: Intent `.showProfile(id:)` not handled in <Flow>.operations(intent:)
  → Link would be parsed but never routed
  → File: NavigationFlow.swift
```

#### Check 4 — Side-effects without coordinator apply case

Structural steps (`Step.nav(.push/.present/.popToRoot/.dismissSheet)`) are
dispatched by the library via `PlumbedCoordinatorBase` and don't need an `apply`
arm. Only `Step.effect(_)` cases reach the coordinator's `apply(_:_:)` switch.

For each `SideEffect` case emitted by `operations(intent:)`:
- Check it appears in the coordinator's `apply(_:_:)` switch body

**Pass criteria:** Every emitted side-effect is handled. (If the flow's
`SideEffect` is `Never`, this check passes trivially.)

**Report format for failures:**
```
FAIL: SideEffect `.clearSearchField` not handled in TopLevelRouteCoordinator.apply()
  → Side-effect would silently no-op
  → File: RouteCoordinators.swift
```

### Category 2: Wiring Validation

#### Check 5 — Route cases unhandled in view destinations

For each route type used in `.navigationDestination(for: <Type>.self)`:
- Parse the switch body inside the closure
- Compare against all cases in that route enum

For each route type used in `.sheet(item:)`:
- Parse the switch body
- Compare against all cases in that sheet route enum

**Pass criteria:** Every route case has a destination view.

**Report format for failures:**
```
FAIL: Route `TopLevel.StackRoute.settings` not handled in .navigationDestination
  → Would crash at runtime when navigating to this route
  → File: RootView.swift:33
```

**Severity:** This is the highest-severity check — unhandled routes cause runtime crashes.

#### Check 6 — Parse / Build round-trip symmetry

Compare the set of intent cases handled in `parse(_:)` with those handled in `url(for:)`:
- Every parseable intent should be buildable (otherwise you can receive a link but can't generate a URL for sharing)
- Every buildable intent should be parseable (otherwise you generate URLs that can't be opened)

**Pass criteria:** The two sets are identical.

**Report format for failures:**
```
WARN: Intent `.showProfile(id:)` is parseable but not buildable
  → Cannot generate shareable URLs for this link
  → File: LinkURLCodec.swift
```

#### Check 7 — Handoff consumption for parameterised routes

The library's `PlumbedCoordinatorBase` registers + delivers handoffs automatically
for every `Step.nav(.push(_))` / `Step.nav(.present(_))` via
`stackHandoffs` / `sheetHandoffs`. The consumer only needs to **consume** the
baton on the destination view.

For each parameterised route case (e.g. `.itemDetail(id:)`), check the
destination view in `.navigationDestination(for:)` / `.sheet(item:)`:
- It reads the handoff via `routeCoordinator.stackHandoffs.handoff(for: <route>)` (or `sheetHandoffs`)
- It consumes via `.onLink(from:)` — either the non-optional or the optional-handoff overload

For route cases without parameters (e.g. `.inbox`), consumption is optional —
not an error if missing.

**Pass criteria:** Every parameterised route's destination view consumes its handoff.

**Report format for failures:**
```
WARN: Destination view for `.itemDetail(id:)` does not consume its handoff
  → Link baton will never reach the view
  → File: RootView.swift:42
```

The handoff lifecycle (register on dispatch, auto-remove on `.delivered`) is
library-managed — never flag a missing `register(for:)` or `remove(for:)` call.

### Category 3: URL Pattern Quality

#### Check 8 — URL pattern normalisation

Scan the codec file for common quality issues:

**8a. Hardcoded URL strings outside constants:**
- Search the codec file for string literals that look like URL hosts, paths, or query param names
- Verify they reference the `LinkRoute` constants enum (e.g. `LinkRoute.Host.inbox`) rather than raw strings like `"inbox"`
- Also search **all other Swift files** for raw URL strings matching the app's scheme (e.g. `"myapp://"`)

```
WARN: Hardcoded URL string "inbox" found outside LinkRoute constants
  → Use LinkRoute.Host.inbox instead
  → File: LinkURLCodec.swift:45
```

**8b. Case-sensitive scheme/host comparison:**
- Check if `url.scheme` and `url.host` are compared with `==` without `.lowercased()` normalisation
- URLs are case-insensitive by spec; `APP://INBOX` should work the same as `app://inbox`

```
WARN: Scheme comparison is case-sensitive (line 38)
  → Consider: url.scheme?.lowercased() == LinkRoute.scheme
```

**8c. Missing empty-string guards:**
- For query parameters that are required (e.g. badge `name`), check that empty strings are handled
- Look for the `nonEmpty()` helper pattern or equivalent guards

```
WARN: Query parameter "name" has no empty-string guard
  → Empty ?name= would produce .showBadge(name: "") instead of .unknown
```

**8d. Query parameter naming consistency:**
- Extract all query parameter names from the codec
- Check for consistent naming convention (camelCase vs snake_case vs kebab-case)
- Flag mixed conventions

```
WARN: Mixed query parameter naming: "replyTo" (camelCase) vs "file" (single word)
  → Consider consistent naming convention
```

**8e. Deterministic URL output:**
- Check if `url(for:)` sorts query items before building the URL
- Unsorted query parameters produce non-deterministic URLs that break equality checks and caching

```
WARN: Query items not sorted in url(for:) for .compose intent
  → Add .sorted { $0.name < $1.name } for deterministic output
```

---

## Phase 3 — Report

After all checks complete, print the report in this format:

```markdown
## Link Audit Report

### Coverage Summary

| Screen | Route | Intent | URL Parse | URL Build | Step | Apply | Handoff | Status |
|--------|-------|--------|-----------|-----------|------|-------|---------|--------|

One row per route case. Columns show ✓ (present), ✗ (missing), or n/a (not applicable).
Status column: ✓ if all required columns pass, ❌ if any fail, ⚠️ if warnings only.

### UI-Only Screens

List screens discovered via `.navigationDestination(isPresented:)`, `NavigationLink`, or
`.sheet(isPresented:)` that are intentionally not linkable. These are informational,
not failures.

| Screen | Navigation Method | File | Notes |
|--------|------------------|------|-------|

### Findings

#### ❌ Failures (N)

Must-fix issues. Listed by severity:
1. Unhandled route cases in view destinations (crash risk)
2. Missing coordinator apply cases (silent navigation failure)
3. Missing navigation step mappings (parsed but never routed)

#### ⚠️ Warnings (N)

Should-fix issues:
1. Coverage gaps (routes without intents)
2. Parse/build asymmetry
3. Missing handoff registration
4. URL pattern quality issues

#### ✓ Passed (N)

Checks that passed cleanly. Listed briefly.

### Recommendations

Prioritised list of actions:
1. [Fix failures first — unhandled routes, missing apply cases]
2. [Add link coverage for uncovered routes]
3. [Improve URL pattern quality]
4. [Run `iris-test-scaffold` to generate tests for the gaps identified]
```

### CI / PR Comment

If the user asks for a PR-friendly report, or if `gh` CLI is available and a PR number is provided:
- Offer to post the report as a PR comment using `gh pr comment <N> --body "..."`
- Collapse the detailed findings under `<details>` tags to keep the comment scannable

---

## Edge Cases

### No Iris integration found
If no files import Iris, report: "No Iris integration detected. Run `iris-bootstrap` first."

### Multiple coordinators / navigation stacks
Some projects have nested navigation (e.g. a sheet with its own coordinator). The audit should:
- Discover all coordinators and their associated route/intent/step types
- Run checks independently for each coordinator's scope
- Report per-coordinator sections in the summary

### Partial integration
If some files exist but others are missing (e.g. intent enum exists but no codec), report which components are present and which are missing rather than failing silently.

### Non-standard patterns
If the project uses patterns that don't match Iris conventions (e.g. custom coordinator without `RouteCoordinator` conformance), note them as "unrecognised" and skip those checks rather than producing false positives.
