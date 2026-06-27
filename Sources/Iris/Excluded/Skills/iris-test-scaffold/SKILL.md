---
name: iris-test-scaffold
description: "Generate Swift Testing tests for link flows. Covers URL codec round-trips, navigation step sequences, Handoff deliver/claim cycles, and Baton remapping. Use when asked to 'test links', 'generate link tests', 'scaffold tests', or after running iris-audit."
compatible_versions: ">=1.0.0"
---

# Iris Test Scaffold

Generates Swift Testing test files for an iOS project's Iris integration. Produces up to four test files covering URL codec round-trips, navigation step sequences, Handoff deliver/claim lifecycle, and Baton intent remapping.

## Prerequisites

- An existing iOS project with Iris integrated and navigation files already scaffolded (intent enums, route enums, codec, navigation steps, coordinators)
- A test target in the project (e.g. `<AppName>Tests`)
- iOS 17+ deployment target

---

## Phase 0 — Version Check

Before generating any code, verify the Iris version is compatible with this skill's templates.

1. **Find the Iris dependency:**
   - Check the project's `Package.swift` for a `.package(path:)` or `.package(url:)` referencing Iris
   - If not found, check `*.xcodeproj/project.pbxproj` for a package reference
   - If not found at all, **stop** and tell the user to add Iris as a dependency first

2. **Read the version:**
   - **Local path dependency:** Run `git -C <path> describe --tags --abbrev=0` to get the latest semver tag
   - **Remote dependency:** Read `Package.resolved` and find the `"Iris"` entry's `"version"` field
   - If no version can be determined, warn the user and ask whether to proceed

3. **Compare:** This skill is compatible with Iris `>=1.0.0`. If the resolved version is older or unrecognised, warn and ask whether to proceed.

---

## Phase 1 — Discover Existing Tests and Navigation Files

### 1. Find the test target directory

Search for a test target:
```bash
find . -type d -name "*Tests" | head -10
```

Confirm by looking for existing test files with `import Testing` or `import XCTest`.

### 2. Read existing test files

List all `.swift` files in the test target directory. Read each one to understand:
- Which test categories already exist (codec, steps, handoff, baton)
- Naming conventions used (struct names, test function names)
- Helper functions and patterns (e.g. `matches()` helper, `U()` URL shorthand)
- Whether they use Swift Testing (`@Test`, `#expect`) or XCTest (`XCTestCase`, `XCTAssert`)

### 3. Read navigation source files

Find and read the project's navigation files to know what to generate tests for:

**Intent enum** — find the app's intent type:
```
grep -rl "case unknown(URL)" --include="*.swift" .
```
Read to extract: enum name, all cases with parameter types.

**Navigation flow enums** — find `NavigationFlow` conformances:
```
grep -rl "NavigationFlow" --include="*.swift" .
```
Read to extract: the flow type name, its `Route` / `SheetRoute` / `SideEffect` associated types, and the `operations(intent:)` switch body.

**URL codec** — find `URLParsing` conformance:
```
grep -rl "URLParsing" --include="*.swift" .
```
Read to extract: `parse(_:)` URL patterns and `url(for:)` build logic, the URL scheme, host constants, query parameter names.

**Sub-intent enums** — look for child intent types used in sheet/sub-coordinator flows:
```
grep -rl "NavigationFlow" --include="*.swift" . | xargs grep "associatedtype Intent"
```
Read any child intent enums (e.g. `ComposeIntent`) referenced by sub-coordinator flows.

Store all discovered types, cases, and parameter shapes before proceeding to generation.

---

## Phase 2 — Generate Test Files

Generate up to 3 test files. **Only generate files that do not already exist.** If a file exists, read it and report what additional test cases could be added (new intent cases not yet covered, missing edge cases). Never overwrite existing test files.

All generated tests must use:
- `import Testing` (NOT `import XCTest`)
- `@Test` macro for test functions
- `@Suite` macro for grouping (optional, use when a file has multiple logical sections)
- `#expect` for assertions
- `#require` for precondition unwrapping (replaces `XCTUnwrap`)
- `async` on test functions that call actor-isolated methods

Follow the project's existing test naming conventions. If no convention is established, use descriptive function names like `parse_inbox()`, `roundtrip_showBadge()`.

### File 1: `LinkURLCodecTests.swift`

Tests URL parsing, URL building, and round-trip symmetry for every intent case.

#### Structure

```swift
import Foundation
import Testing
import Iris

@testable import {{APP_TARGET}}

struct LinkURLCodecTests {

    let codec = LinkURLCodec()

    // MARK: - Parse: Push flows
    // One @Test per push intent case

    // MARK: - Parse: Sheet flows
    // One @Test per sheet intent case

    // MARK: - Parse: Edge cases
    // Wrong scheme, invalid params, empty params, missing required params

    // MARK: - Build: Push flows
    // One @Test per push intent, verify URL string output

    // MARK: - Build: Sheet flows
    // One @Test per sheet intent

    // MARK: - Round-trip samples
    // For each intent: parse(url(for: intent)) == intent
}
```

#### Generation rules

**Parse tests** — one per intent case plus edge cases:

- **No params:**
  ```swift
  @Test func parse_inbox() {
      let url = U("{{SCHEME}}://inbox")
      let intent = codec.parse(url)
      #expect(matches(intent, .showInbox))
  }
  ```

- **UUID in path:**
  ```swift
  @Test func parse_item_valid_uuid() {
      let id = UUID()
      let url = U("{{SCHEME}}://item/\(id.uuidString)")
      let intent = codec.parse(url)
      #expect(matches(intent, .openItem(id)))
  }

  @Test func parse_item_invalid_uuid_is_unknown() {
      let url = U("{{SCHEME}}://item/not-a-uuid")
      let intent = codec.parse(url)
      #expect(matches(intent, .unknown(url)))
  }
  ```

- **String query param:**
  ```swift
  @Test func parse_badge_with_name() {
      let url = U("{{SCHEME}}://ui/badge?name=Gold")
      let intent = codec.parse(url)
      #expect(matches(intent, .showBadge(name: "Gold")))
  }
  ```

- **Sheet with sub-intent:**
  Generate a parse test for each sub-intent variant (e.g. `.compose(.standard(replyTo:))`, `.compose(.attach)`, `.compose(.preview(file:))`).

**Edge case tests:**

```swift
@Test func parse_wrong_scheme_is_unknown() {
    let url = U("https://inbox")
    let intent = codec.parse(url)
    #expect(matches(intent, .unknown(url)))
}
```

Generate additional edge cases based on the codec's parameter requirements:
- Empty required query params (e.g. `?name=` with no value)
- Missing required path components
- Extra unexpected path segments

**Build tests** — one per intent case:

```swift
@Test func build_showInbox() {
    let url = codec.url(for: .showInbox)
    #expect(url.absoluteString == "{{SCHEME}}://inbox")
}
```

For intents with parameters, use deterministic test values (fixed UUIDs, known strings).

**Round-trip tests** — one per intent case:

```swift
@Test func roundtrip_showBadge() {
    let original: {{APP_INTENT}} = .showBadge(name: "Silver")
    let built = codec.url(for: original)
    let reparsed = codec.parse(built)
    #expect(matches(reparsed, original))
}
```

**Helper functions** — append at bottom of file:

```swift
private func matches(_ lhs: {{APP_INTENT}}, _ rhs: {{APP_INTENT}}) -> Bool {
    switch (lhs, rhs) {
    // One arm per intent case comparing associated values
    default: return false
    }
}

private func U(_ s: String) -> URL { URL(string: s)! }
```

The `matches` helper is needed because intent enums typically lack `Equatable` synthesis when they contain `URL` associated values (the `unknown(URL)` case). Generate one switch arm per case, comparing all associated values.

---

### File 2: `NavigationFlowTests.swift`

Tests that `{{APP_NAME}}Flow.operations(intent:)` produces the correct `Step`
sequence for every intent.

#### Structure

```swift
import Foundation
import Testing
import Iris

@testable import {{APP_TARGET}}

// MARK: - {{APP_NAME}}Flow Tests

struct {{APP_NAME}}FlowTests {

    // One @Test per intent case
}

// MARK: - {{CHILD}}Flow Tests (if sub-coordinators exist)

struct {{CHILD}}FlowTests {

    // One @Test per child intent case
}
```

#### Generation rules

`Step<Route, SheetRoute, SideEffect>` is `Equatable` when `SideEffect` is
`Equatable` (and `Never` satisfies that), so prefer direct equality on the
expected step sequence over per-case helpers.

**Push intent tests** — verify `.nav(.popToRoot)` is always first, followed by `.nav(.push(_))`:

```swift
@Test func showInbox_emitsPopToRootThenPushInbox() {
    let steps = {{APP_NAME}}Flow.operations(intent: .showInbox)
    #expect(steps == [.nav(.popToRoot), .nav(.push(.inbox))])
}
```

For parameterised push intents, verify the parameter is carried through:

```swift
@Test func showBadge_emitsPopToRootThenPushBadge() {
    let steps = {{APP_NAME}}Flow.operations(intent: .showBadge(name: "Gold"))
    #expect(steps == [.nav(.popToRoot), .nav(.push(.badge(name: "Gold")))])
}
```

**Sheet intent tests** — verify NO `.nav(.popToRoot)`, only the present step:

```swift
@Test func compose_emitsSinglePresentCompose() {
    let steps = {{APP_NAME}}Flow.operations(intent: .compose(.standard(replyTo: "user@example.com")))
    #expect(steps == [.nav(.present(.compose))])
}
```

**Unknown intent test:**

```swift
@Test func unknown_emitsNoSteps() {
    let url = URL(string: "{{SCHEME}}://unknown")!
    let steps = {{APP_NAME}}Flow.operations(intent: .unknown(url))
    #expect(steps.isEmpty)
}
```

**Side-effect tests** — if the flow declares its own `SideEffect`, assert that
the relevant arms emit `.effect(_)`:

```swift
@Test func clearSearch_emitsClearEffect() {
    let steps = SearchFlow.operations(intent: .clearSearch)
    #expect(steps == [.effect(.clearSearchField)])
}
```

**Child flow tests** — if the project has sub-coordinator flow types (e.g. `ComposeFlow`), generate a separate test struct for each, covering every child intent case. For composite intents that produce multi-step sequences, verify each step in order via array equality.

---

### File 3: `HandoffTests.swift`

Tests `Handoff` deliver/claim lifecycle using the framework's actor-based API.

#### Structure

```swift
import Foundation
import Testing
import Iris

@testable import {{APP_TARGET}}

struct HandoffTests {

    // MARK: - Producer-first (deliver then claim)

    // MARK: - Consumer-first (claim then deliver)

    // MARK: - Single-delivery semantics

    // MARK: - HandoffRegistry
}
```

#### Generation rules

Use the project's own intent type for realistic tests. All Handoff tests must be `async` because `claim()` is an actor-isolated async method.

**Producer-first pattern:**

```swift
@Test func deliverThenClaim_returnsMatchingBaton() async {
    let handoff = Handoff<{{APP_INTENT}}>()
    let flow = NavFlow(source: "test")
    let baton = Baton(intent: {{SAMPLE_INTENT}}, flow: flow)

    await handoff.deliver(baton)
    let claimed = await handoff.claim()

    #expect(claimed?.intent == baton.intent)
    #expect(claimed?.flow == flow)
}
```

`{{SAMPLE_INTENT}}` should be the simplest intent case with no parameters (e.g. `.showInbox`).

**Consumer-first pattern:**

```swift
@Test func claimThenDeliver_resumesWaitingConsumer() async {
    let handoff = Handoff<{{APP_INTENT}}>()
    let flow = NavFlow(source: "test")
    let baton = Baton(intent: {{SAMPLE_INTENT}}, flow: flow)

    async let claimed = handoff.claim()
    // Small yield to let the claim suspend before delivering
    await Task.yield()
    await handoff.deliver(baton)

    let result = await claimed
    #expect(result?.intent == baton.intent)
}
```

**Single-delivery semantics:**

```swift
@Test func secondClaimReturnsNil() async {
    let handoff = Handoff<{{APP_INTENT}}>()
    let flow = NavFlow(source: "test")
    let baton = Baton(intent: {{SAMPLE_INTENT}}, flow: flow)

    await handoff.deliver(baton)
    let first = await handoff.claim()
    let second = await handoff.claim()

    #expect(first != nil)
    #expect(second == nil)
}

@Test func duplicateDeliverIsIgnored() async {
    let handoff = Handoff<{{APP_INTENT}}>()
    let flow = NavFlow(source: "test")
    let baton1 = Baton(intent: {{SAMPLE_INTENT}}, flow: flow)
    let baton2 = Baton(intent: {{ANOTHER_INTENT}}, flow: flow)

    await handoff.deliver(baton1)
    await handoff.deliver(baton2)
    let claimed = await handoff.claim()

    #expect(claimed?.intent == baton1.intent)
}
```

`{{ANOTHER_INTENT}}` should be a different intent case to prove the second deliver was ignored.

**HandoffRegistry tests:**

```swift
@Test @MainActor func registryRegisterAndRetrieve() {
    let registry = HandoffRegistry<TopLevel.StackRoute, {{APP_INTENT}}>()
    let handoff = registry.register(for: .inbox)
    let retrieved = registry.handoff(for: .inbox)

    #expect(retrieved != nil)
    // Actor identity: the retrieved handoff is the same instance
    #expect(handoff === retrieved)
}

@Test @MainActor func registryReRegisterReplacesHandoff() {
    let registry = HandoffRegistry<TopLevel.StackRoute, {{APP_INTENT}}>()
    let first = registry.register(for: .inbox)
    let second = registry.register(for: .inbox)

    #expect(first !== second)
    let retrieved = registry.handoff(for: .inbox)
    #expect(retrieved === second)
}

@Test @MainActor func registryAutoClearsOnDelivery() async {
    let registry = HandoffRegistry<TopLevel.StackRoute, {{APP_INTENT}}>()
    let handoff = registry.register(for: .inbox)
    let baton = Baton<{{APP_INTENT}}>(intent: {{SAMPLE_INTENT}}, flow: NavFlow(source: "test"))

    _ = await handoff.deliver(baton)
    _ = await handoff.claim()

    // The handoff transitions to `.delivered`, so the registry auto-removes it.
    // The remove dispatches back to @MainActor — yield once for it to land.
    await Task.yield()
    #expect(registry.handoff(for: .inbox) == nil)
}
```

Replace `TopLevel.StackRoute` and `.inbox` with the project's actual route type and a representative case.

> **Note:** `HandoffRegistry` does not expose `remove(for:)` or `removeAll()` —
> the registry auto-clears entries when their handoff transitions to
> `.delivered`. Don't write tests asserting on those methods.

---

## Phase 3 — Build and Run Tests

1. **Build the test target** using XcodeBuildMCP (or `xcodebuild build-for-testing`). Fix any compilation errors:
   - Missing imports — add `import Iris` or `import Testing`
   - Type mismatches — verify intent/route type names match the project's actual types
   - Actor isolation — add `async` to test functions that call actor methods, add `@MainActor` to tests that use `@MainActor`-isolated types like `HandoffRegistry`

2. **Run the tests** using XcodeBuildMCP (or `xcodebuild test`). Do NOT use `-quiet` — full output is needed to see pass/fail results.

3. **Fix failures:**
   - Assertion failures indicate a mismatch between the test expectations and the actual codec/step behaviour. Read the codec or step implementation to correct the expected values.
   - Timeouts on `claim()` tests indicate the deliver was not called or the test structure needs adjustment.

---

## Phase 4 — Report

After all tests pass, print:

### Files Generated

List each new test file with its full path.

### Files Skipped

List each existing test file that was not overwritten, with the additional test cases that could be added.

### Test Summary

| File | Tests | Status |
|------|-------|--------|
| `LinkURLCodecTests.swift` | N | new / existing / skipped |
| `NavigationFlowTests.swift` | N | new / existing / skipped |
| `HandoffTests.swift` | N | new / existing / skipped |

### Coverage Gaps

List any intent cases, route cases, or codec patterns that are not yet tested. Suggest specific test functions to add.

### Next Steps

- Run `iris-audit` to check for wiring gaps between the tested components
- Add integration tests that exercise the full URL-to-screen flow via the coordinator
- Add performance tests for codec parsing if the URL space is large

---

## Edge Cases

### No test target found
If no test target directory exists, **stop** and tell the user to create one first. Provide instructions for adding a test target in Xcode.

### Existing test files cover all categories
If all three test files already exist, do not generate anything. Instead:
1. Read each file
2. Compare the tested intent cases against the current intent enum
3. Report any new intent cases that lack test coverage
4. Suggest specific `@Test` functions to add for the missing cases

### XCTest-based existing tests
If existing tests use XCTest instead of Swift Testing, generate new files using Swift Testing anyway. Do not mix frameworks within a single file. Note the coexistence in the report.

### Multiple intent types (nested coordinators)
If the project has sub-coordinators with their own intent types (e.g. `ComposeIntent`), generate codec and flow tests that cover the child intent variants. The Handoff tests should use the parent intent type unless child-specific handoff patterns exist.

### Intent enum without `Equatable` synthesis
If the intent enum contains cases with non-`Equatable` associated values (e.g. closures), the `matches()` helper must use manual pattern matching instead of `==`. Inspect each case's associated value types before generating the helper.
