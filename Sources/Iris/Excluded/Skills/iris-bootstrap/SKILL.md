---
name: iris-bootstrap
description: "Scaffold Iris link wiring into an existing iOS project. Creates intent enums, route containers, a navigation flow, URL codec, a PlumbedCoordinatorBase subclass, a link modifier, and wires them into the App entry point and RootView. Use when starting a new project that needs linking or when asked to 'add links', 'scaffold navigation', or 'wire up Iris'."
compatible_versions: ">=1.0.0"
---

# Iris Bootstrap

Scaffolds the full Iris navigation layer into an existing iOS project so every navigable screen is linkable from the start.

## Prerequisites

- An existing Xcode iOS project or workspace
- Iris added as an SPM dependency (local path or remote URL)
- iOS 17+ deployment target

---

## Phase 0: Version Check

Before generating any code, verify the Iris version is compatible with this skill's templates.

1. **Find the Iris dependency:**
   - Check the project's `Package.swift` for a `.package(path:)` or `.package(url:)` referencing Iris
   - If not found, check `*.xcodeproj/project.pbxproj` for a package reference
   - If not found at all, **stop** and tell the user to add Iris as a dependency first. Provide the git URL.

2. **Read the version:**
   - **Local path dependency:** Run `git -C <path> describe --tags --abbrev=0` to get the latest semver tag
   - **Remote dependency:** Read `Package.resolved` (or `*.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`) and find the `"Iris"` entry's `"version"` field
   - If no version can be determined, warn the user and ask whether to proceed

3. **Compare:** This skill is compatible with Iris `>=1.0.0`. If the resolved version is older or unrecognised, warn and ask whether to proceed.

---

## Phase 1: Gather Inputs

Ask the user the following questions interactively. Auto-detect where possible and confirm.

### 1. App name

Detect from `.xcodeproj` name or `@main` struct file name. Confirm with the user.

Example: `"MyApp"`

### 2. URL scheme

Ask: "What URL scheme should links use? (e.g. `myapp`, default: lowercase app name)"

- Must be a single word, no colons, no slashes
- Validate it is not a system scheme (`http`, `https`, `mailto`, `tel`, `sms`, `facetime`, `maps`)
- Default: lowercase app name

Example: `"myapp"` → URLs like `myapp://inbox`

### 3. Initial screens

Ask: "List 2-5 initial screens for linking. For each, provide: name, type (push/sheet), and any parameters."

For each screen, collect:
- **Name**: a short identifier (e.g. "inbox", "profile", "settings")
- **Type**: `push` (NavigationStack destination) or `sheet` (modal presentation)
- **Parameters**: zero or more typed parameters (e.g. `id: UUID`, `name: String`)

Default if user provides nothing: two screens, "home" (push, no params) and "settings" (push, no params).

---

## Phase 2: Detect Project Structure

1. **Find the app target directory:**
   ```bash
   grep -rl "@main" --include="*.swift" .
   ```
   The directory containing the `@main` `App` struct is the target directory.

2. **Check for existing Navigation/ folder:**
   If `<TargetDir>/Navigation/` exists, warn the user and ask before overwriting any files.

3. **Check for BundleLocator.swift:**
   If it exists, note it for later (no action needed). If missing, note but do not create. That is the `bootstrap-project` skill's responsibility.

4. **Detect logging:**
   - Search for `import SLLog` or `AppLogger` in the target. If found, use `AppLogger` / `makeLogger()` / `desc()` pattern.
   - Otherwise, use `os.Logger` with subsystem from bundle identifier:
     ```swift
     import os
     private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "Iris")
     ```

---

## Phase 3: Generate Files

Create all files in `<TargetDir>/Navigation/`. Use the templates below, substituting placeholders.

### Placeholder Reference

| Placeholder | Example value |
|-------------|---------------|
| `{{APP_NAME}}` | `MyApp` |
| `{{APP_INTENT}}` | `MyAppIntent` |
| `{{URL_SCHEME}}` | `myapp` |

Screen-derived placeholders are generated dynamically from the user's screen list.

---

### File 1: `Intent.swift`

```swift
//
//  Intent.swift
//  {{APP_NAME}}
//

import Foundation
import Iris

// MARK: {{APP_INTENT}}

/// A high-level navigation intent used across the app.
enum {{APP_INTENT}}: Sendable, Equatable {
    {{INTENT_CASES}}

    /// A link the parser did not recognise.
    case unknown(URL)
}

extension {{APP_INTENT}}: CustomStringConvertible {

    var description: String {
        switch self {
        {{INTENT_DESCRIPTION_CASES}}
        case .unknown(let url):
            return "unknown(\(url.absoluteString))"
        }
    }
}

extension {{APP_INTENT}}: CustomDebugStringConvertible {
    var debugDescription: String { description }
}
```

**Generation rules for `{{INTENT_CASES}}`:**

For each screen the user specified:
- No params: `case show<ScreenName>` (e.g. `case showInbox`)
- With params: `case show<ScreenName>(<paramName>: <ParamType>)` (e.g. `case showProfile(id: UUID)`)
- Sheet screens: `case present<ScreenName>` or `case present<ScreenName>(<params>)`

Use verb prefix `show` for push screens, `present` for sheet screens.

**Generation rules for `{{INTENT_DESCRIPTION_CASES}}`:**

For each case, generate a switch arm returning a human-readable string:
```swift
case .showInbox:
    return "showInbox"
case .showProfile(let id):
    return "showProfile(\(id))"
```

---

### File 2: `LinkableRoutes.swift`

```swift
//
//  LinkableRoutes.swift
//  {{APP_NAME}}
//

import SwiftUI
import Iris

// MARK: TopLevel

enum TopLevel {

    enum StackRoute: Hashable {
        {{STACK_ROUTE_CASES}}
    }

    enum SheetRoute: Identifiable, Hashable {
        {{SHEET_ROUTE_CASES}}

        var id: String {
            switch self {
            {{SHEET_ROUTE_ID_CASES}}
            }
        }
    }

    /// View-facing navigation intents for the TopLevel flow.
    enum Intent: Sendable {
        {{VIEW_INTENT_CASES}}
    }
}

{{DEBUG_DESCRIPTION_EXTENSIONS}}
```

**Generation rules:**

- **`{{STACK_ROUTE_CASES}}`**: One case per push screen. No params → `case inbox`. With params → `case profile(id: UUID)`.
- **`{{SHEET_ROUTE_CASES}}`**: One case per sheet screen. Typically no params on the route itself (e.g. `case compose`).
  - If no sheet screens were specified, generate:
    ```swift
    // No sheet routes defined yet. Add cases here when needed.

    var id: String { "" }
    ```
- **`{{SHEET_ROUTE_ID_CASES}}`**: One arm per sheet case returning a stable string ID.
- **`{{VIEW_INTENT_CASES}}`**: One case per screen. Push screens with params get `forwarding: Baton<{{APP_INTENT}}>? = nil`. Sheet screens get `forwarding: Baton<ChildIntentType>? = nil` (or `{{APP_INTENT}}` if no child coordinator).
- **`{{DEBUG_DESCRIPTION_EXTENSIONS}}`**: `CustomDebugStringConvertible` extensions for `StackRoute` and `SheetRoute`.

---

### File 3: `NavigationFlow.swift`

```swift
//
//  NavigationFlow.swift
//  {{APP_NAME}}
//

import Foundation
import Iris

// MARK: {{APP_NAME}}Flow

/// Translates `{{APP_INTENT}}` cases into a list of `Step` values for the library
/// to execute. Structural moves are `Step.nav(.push/.present/.popToRoot/.dismissSheet)`
/// and are dispatched automatically. Consumer-defined side-effects (if any)
/// go in the `SideEffect` associated type and surface as `Step.effect(_)`.
/// The coordinator's `apply(_:_:)` handles those.
enum {{APP_NAME}}Flow: NavigationFlow {

    typealias Intent = {{APP_INTENT}}
    typealias Route = TopLevel.StackRoute
    typealias SheetRoute = TopLevel.SheetRoute
    // typealias SideEffect = Never  // default; declare only if the flow needs effects

    static func operations(intent: Intent) -> [Step<Route, SheetRoute, Never>] {
        switch intent {
        {{FLOW_OPERATIONS}}
        case .unknown:
            return []
        }
    }
}
```

**Generation rules for `{{FLOW_OPERATIONS}}`:**

- Push screens: `case .show<ScreenName>: return [.nav(.popToRoot), .nav(.push(.<screenName>))]`
- Sheet screens: `case .present<ScreenName>: return [.nav(.present(.<screenName>))]`
- Parameterised: build the route value from the intent's payload, e.g. `case .showProfile(let id): return [.nav(.popToRoot), .nav(.push(.profile(id: id)))]`
- Multi-step composite flows (push → present, etc.): return the steps in order; the library pauses between them by `Self.interStepAnimationPause` (default `.zero`, override on the coordinator if a chain involves competing animations).

**If the flow needs side-effects** (e.g. "clear the search field after navigating"), add a `SideEffect` enum and emit it via `.effect(.clearSearch)`. The coordinator's `apply(_:_:)` override handles it.

---

### File 4: `LinkURLCodec.swift`

```swift
//
//  LinkURLCodec.swift
//  {{APP_NAME}}
//

import Foundation
import Iris

/// A codec that parses and builds app-specific link URLs.
struct LinkURLCodec: Sendable, URLParsing {

    // MARK: Parse

    func parse(_ url: URL) -> {{APP_INTENT}} {
        guard url.scheme == LinkRoute.scheme,
              let host = url.host
        else { return .unknown(url) }

        switch host {
        {{URL_PARSE_CASES}}
        default:
            return .unknown(url)
        }
    }

    // MARK: Build

    func url(for intent: {{APP_INTENT}}) -> URL {
        switch intent {
        {{URL_BUILD_CASES}}
        case .unknown(let url):
            return url
        }
    }

    // MARK: Internals

    private func make(host: String, path: String = "", query: [URLQueryItem] = []) -> URL {
        var c = URLComponents()
        c.scheme = LinkRoute.scheme
        c.host   = host
        c.path   = path
        c.queryItems = query.isEmpty ? nil : query
        return c.url! // safe: we control all parts
    }
}

// MARK: - Route table (single place)

private enum LinkRoute {
    static let scheme = "{{URL_SCHEME}}"
    enum Host {
        {{URL_HOSTS}}
    }
    {{URL_QUERY_CONSTANTS}}
}
```

**Generation rules:**

- Each screen maps to a host: `static let <screenName> = "<screenName>"` inside `Host`.
- **Parse cases:** Switch on host string, extract query params or path components for parameterised routes.
  - No params: `case LinkRoute.Host.inbox: return .showInbox`
  - UUID param in path: extract `url.lastPathComponent` as UUID
  - String param in query: extract from `URLComponents.queryItems`
- **Build cases:** Reverse mapping using the `make(host:path:query:)` helper.
- **Query constants:** Only generated if any screen has string query parameters.

---

### File 5: `RouteCoordinators.swift`

```swift
//
//  RouteCoordinators.swift
//  {{APP_NAME}}
//

import SwiftUI
import Iris

// MARK: - TopLevelRouteCoordinator

/// Subclasses `PlumbedCoordinatorBase<{{APP_NAME}}Flow>` so it inherits the
/// library's navigators, facade, executors (link + UI), and stack/sheet
/// `HandoffRegistry`s out of the box. Override `apply(_:_:)` to handle the
/// flow's `SideEffect` cases. Structural cases (push/present/popToRoot/
/// dismissSheet) are dispatched by the library and never reach here.
@MainActor
@Observable
final class TopLevelRouteCoordinator: PlumbedCoordinatorBase<{{APP_NAME}}Flow> {

    {{LOGGER_PROPERTY}}

    // MARK: Apply (side-effects only)

    override func apply(_ effect: {{APP_NAME}}Flow.SideEffect, _ baton: Baton<Intent>) async {
        // {{APP_NAME}}Flow.SideEffect defaults to Never, so this is unreachable.
        // If the flow declares its own SideEffect enum, switch on `effect` here.
    }
}

// MARK: - UI-driven navigation

extension TopLevelRouteCoordinator {

    func open(_ intent: TopLevel.Intent, _ flow: NavFlow = .init(source: "tap")) {
        uiSwitcher.run { [weak self] in
            guard let self else { return }
            await self._open(intent, flow)
        }
    }

    private func _open(_ intent: TopLevel.Intent, _ flow: NavFlow) async {
        switch intent {
        {{UI_OPEN_CASES}}
        }
    }
}
```

**Iris handles all structural navigation.** `{{APP_NAME}}Flow.operations(intent:)` returns `Step.nav(.push(_))` / `Step.nav(.present(_))` / etc., and `PlumbedCoordinatorBase`'s inherited `dispatchIfPossible(_:baton:)` routes them through `nav.route.pushRoute(_:registry:baton:)` and `nav.sheet.presentRoute(_:registry:baton:)`. Those methods register a handoff against `stackHandoffs` / `sheetHandoffs`, perform the SwiftUI mutation, and deliver the baton once the destination mounts. The consumer writes none of this any more.

**Override `apply(_:_:)` only when the flow declares side-effects.** Example: a search flow that emits `.clearSearchField` after the navigation completes.

```swift
override func apply(_ effect: SearchFlow.SideEffect, _ baton: Baton<Intent>) async {
    switch effect {
    case .clearSearchField:
        searchText = ""
    }
}
```

**Generation rules for `{{UI_OPEN_CASES}}`:**

For each view intent case, navigate via the inherited `nav` facade. Handoffs are only needed when the entry point has a baton to deliver (tap-driven UI navigation typically doesn't):

- Simple push: `case .inbox: nav.popToRoot(flow: flow); nav.pushIfNeeded(.inbox, flow: flow)`
- Push with handoff (UI flow carrying a payload):
  ```swift
  case .profile(let id, let forwarding):
      let route: TopLevel.StackRoute = .profile(id: id)
      let handoff = stackHandoffs.register(for: route)
      nav.ensureTop(route, flow: flow)
      if let forwarding {
          await Task.waitOneTick()
          await handoff.deliver(forwarding)
      }
  ```
- Sheet: `case .compose: nav.presentIfNeeded(.compose, flow: flow)`

**`{{LOGGER_PROPERTY}}`:**
- If SLLog detected: `private var loggerSteps: AppLogger { makeLogger("TopLevel/steps") }`
- If os.Logger: `private let loggerSteps = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "TopLevel/steps")`

---

### File 6: `LinkModifier.swift`

```swift
//
//  LinkModifier.swift
//  {{APP_NAME}}
//

import SwiftUI
import Iris

private struct LinkModifier: ViewModifier {

    let broadcaster: Broadcaster<LinkURLCodec>
    let routeCoordinator: TopLevelRouteCoordinator

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                Task {
                    await broadcaster.handle(
                        url: url,
                        flow: .init(source: "link")
                    )
                }
            }
            .onEvents(
                from: { await broadcaster.makeStream() },
                consume: { (baton: Baton<{{APP_INTENT}}>) in
                    routeCoordinator.route(baton: baton)
                }
            )
    }
}

extension View {
    func onLinks(
        from broadcaster: Broadcaster<LinkURLCodec>,
        routing routeCoordinator: TopLevelRouteCoordinator
    ) -> some View {
        modifier(
            LinkModifier(
                broadcaster: broadcaster,
                routeCoordinator: routeCoordinator
            )
        )
    }
}
```

This file requires no dynamic generation beyond the `{{APP_INTENT}}` substitution.

Also append a `#if DEBUG` commands struct to the same file. This gives the developer a macOS menu to fire every link without needing to type URLs manually:

```swift
// MARK: - Debug Link Commands

#if DEBUG
struct DebugLinkCommands: Commands {

    let broadcaster: Broadcaster<LinkURLCodec>
    let urlCodec: LinkURLCodec

    var body: some Commands {
        CommandMenu("Debug Links") {
            {{DEBUG_COMMAND_BUTTONS}}
        }
    }
}
#endif
```

**Generation rules for `{{DEBUG_COMMAND_BUTTONS}}`:**

For each screen, generate a `Button` that fires the corresponding link URL through the broadcaster:

- **No params:**
  ```swift
  Button("Show Inbox") {
      Task {
          await broadcaster.handle(
              url: urlCodec.url(for: .showInbox),
              flow: .init(source: "link")
          )
      }
  }
  ```

- **With params (use a sensible example value):**
  ```swift
  Button("Show Profile (random)") {
      let id = UUID()
      Task {
          await broadcaster.handle(
              url: urlCodec.url(for: .showProfile(id: id)),
              flow: .init(source: "link")
          )
      }
  }
  ```

- **UUID params:** use `UUID()` for a random value
- **String params:** use a placeholder like `"example"`

Then wire the commands into the App entry point inside `#if DEBUG`:

```swift
// In <AppName>App.swift body, after WindowGroup:
#if DEBUG
.commands {
    DebugLinkCommands(broadcaster: broadcaster, urlCodec: urlCodec)
}
#endif
```

---

## Phase 4: Modify Existing Files

### 1. App entry point (`<AppName>App.swift`)

Add or modify:

```swift
import Iris

// Inside the @main App struct:

private let urlCodec = LinkURLCodec()
private let broadcaster: Broadcaster<LinkURLCodec>

@State private var routeCoordinator: TopLevelRouteCoordinator

init() {
    self.broadcaster = Broadcaster(urlCodec: urlCodec)
    self._routeCoordinator = State(initialValue: TopLevelRouteCoordinator())
}

// In body, on the root view:
RootView()
    .environment(routeCoordinator)
    .onLinks(from: broadcaster, routing: routeCoordinator)

// After WindowGroup, add debug commands:
#if DEBUG
.commands {
    DebugLinkCommands(broadcaster: broadcaster, urlCodec: urlCodec)
}
#endif
```

### 2. RootView (`RootView.swift` or main content view)

Wrap the content in a `NavigationStack` driven by the coordinator's inherited
`nav` facade:

```swift
import Iris

struct RootView: View {

    @Environment(TopLevelRouteCoordinator.self) var routeCoordinator

    var body: some View {
        NavigationStack(path: routeCoordinator.nav.pathBinding) {
            // Existing content here
            .navigationDestination(for: TopLevel.StackRoute.self) { route in
                switch route {
                {{NAV_DESTINATION_CASES}}
                }
            }
            {{SHEET_MODIFIER}}
        }
    }
}
```

**`{{NAV_DESTINATION_CASES}}`:** One arm per push route rendering a placeholder:
```swift
case .inbox:
    Text("Inbox") // TODO: Replace with InboxView
case .profile(let id):
    Text("Profile: \(id)") // TODO: Replace with ProfileView
```

**`{{SHEET_MODIFIER}}`:** Only if sheet routes exist:
```swift
.sheet(item: routeCoordinator.nav.sheetBinding) { route in
    switch route {
    case .compose:
        Text("Compose") // TODO: Replace with ComposeView
    }
}
```

**Destinations that need the baton payload** consume it via the
`.onLink(from:)` modifier, pulling the handoff out of the coordinator's
inherited `stackHandoffs` / `sheetHandoffs` registry:

```swift
case .profile(let id):
    ProfileView(id: id)
        .onLink(from: routeCoordinator.stackHandoffs.handoff(for: .profile(id: id))) { baton in
            // act on baton.intent
        }
```

The optional-handoff overload of `.onLink(from:)` no-ops when nothing is
registered, and the registry auto-cleans on `.delivered`. Destination views
never call `remove(for:)`.

---

## Phase 5: Validate

1. **Build** the project using XcodeBuildMCP to confirm compilation succeeds.
2. If build fails, read the errors and fix. Common issues:
   - Missing `import Iris`: add to files that reference framework types
   - Type mismatches in handoff generics: check `HandoffRegistry` type parameters match the flow's `Route` / `SheetRoute`
   - `NavigationFlow` conformance: ensure `operations(intent:)` covers all intent cases and returns `[Step<Route, SheetRoute, SideEffect>]`

---

## Phase 6: Summary

After successful build, print:

### Files Created
List each file with its full path.

### Files Modified
List each modified file and what changed.

### Supported Link URLs
A table of all URL patterns from the codec:

| URL Pattern | Intent |
|-------------|--------|
| `{{URL_SCHEME}}://inbox` | `.showInbox` |
| `{{URL_SCHEME}}://profile/<uuid>` | `.showProfile(id:)` |

### Next Steps
- Replace placeholder `Text` views with real destination views
- Add `.onLink(from: handoff)` in destination views that need to receive baton data
- Add sub-coordinators for sheets with their own NavigationStack (follow the ComposeRouteCoordinator pattern in LinkDemo)
- Use `iris-test-scaffold` skill to generate tests for URL parsing and navigation flows
- Register the URL scheme in Info.plist under `CFBundleURLTypes`

---

## Edge Cases

### No `@main` App struct found
The project might use UIKit lifecycle (`UIApplicationDelegate` / `UISceneDelegate`). Generate the Navigation/ files but skip Phase 4. Instead, provide manual wiring instructions for `UISceneDelegate.scene(_:openURLContexts:)`.

### Iris not added as a dependency
Generate the code anyway (it will not compile), but prominently warn the user. Provide the git URL for adding the package.

### Existing files in Navigation/
Ask the user per-file whether to overwrite. Never silently overwrite.

### Screen name collisions
Validate that no two screens share the same name. Error if they do.

### URL scheme conflicts
Warn if the chosen scheme matches a system scheme or a common third-party scheme.

### Multiple app targets
If multiple `@main` structs are found, ask the user which target to scaffold into.
