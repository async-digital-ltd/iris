# AGENTS.md

Guide for coding agents (Claude Code, Cursor, Copilot, others) integrating `iris` into a SwiftUI host app. Complements the human-facing DocC catalogue at `Sources/Iris/Iris.docc/`; this file is the agent-context-window-fittable version focused on wire-it-up patterns and the anti-patterns that don't survive the library's grain.

For deeper conceptual reading, the DocC catalogue and the `Sources/Iris/Excluded/Skills/*/SKILL.md` scaffolding templates remain authoritative.

## What this library is

`iris` turns a URL into a typed `Intent`, decomposes the intent into a list of `Step` values (structural navigation steps plus consumer-defined effects), and applies them in order. Newer links cancel earlier in-flight ones via `LatestWinsExecutor`. A `HandoffRegistry` lets destination views consume the original `Baton` once they have mounted.

Five decisions wire a host app into the library:

1. `Intent` enum — the consumer-defined verbs the app can be driven into.
2. `Route` and `SheetRoute` enums — the destinations a stack push or sheet present can land on.
3. `SideEffect` enum (or `Never`) — non-navigation state writes the URL needs to drive (search filters, scrolls, overlays).
4. A `NavigationFlow` conformance whose `operations(intent:)` returns an ordered `[Step]`.
5. A coordinator subclassing `PlumbedCoordinatorBase<Flow>`, optionally overriding `apply(_:_:)`.

Once those are in place, `coordinator.route(baton:)` is the single entry point from any URL.

## Minimal integration

Skeleton walkthrough for an app with two stack destinations (an inbox screen and a profile screen) plus a settings sheet, and zero side-effects.

### 1. Intent

```swift
enum AppIntent: Sendable, Equatable {
    case showInbox
    case showProfile(id: ProfileID)
}
```

### 2. Routes

```swift
enum AppRoute: Hashable, Sendable {
    case inbox
    case profile(id: ProfileID)
}

enum AppSheetRoute: Identifiable, Hashable, Sendable {
    case settings
    var id: Self { self }
}
```

`Route` must be `Hashable & Sendable`. `SheetRoute` must additionally be `Identifiable & Hashable & Sendable` because `PlumbedCoordinatorBase`'s `where` clause requires it and the library drives `.sheet(item:)` from the sheet binding. `Never` cannot satisfy `Identifiable`, so a stack-only app still needs a placeholder enum (e.g. `enum AppSheetRoute: Identifiable, Hashable, Sendable { case _unused; var id: Self { self } }`).

### 3. Flow

```swift
enum AppFlow: NavigationFlow {
    typealias Intent = AppIntent
    typealias Route = AppRoute
    typealias SheetRoute = AppSheetRoute
    typealias SideEffect = Never

    static func operations(intent: Intent) -> [Step<Route, SheetRoute, Never>] {
        switch intent {
        case .showInbox:
            return [.nav(.popToRoot), .nav(.dismissSheet), .nav(.push(.inbox))]
        case .showProfile(let id):
            return [.nav(.popToRoot), .nav(.dismissSheet), .nav(.push(.profile(id: id)))]
        }
    }
}
```

`SideEffect = Never` short-circuits the library's effect arm. The coordinator does not need to override `apply(_:_:)` in that case (the base class's no-op is unreachable for `Never`).

### 4. Coordinator

```swift
@MainActor
@Observable
final class AppCoordinator: PlumbedCoordinatorBase<AppFlow> {

    private let codec = AppURLCodec()

    func open(_ url: URL) {
        guard let intent = codec.parse(url) else { return }
        let baton = Baton(intent: intent, flow: NavFlow(source: "link"))
        route(baton: baton)
    }
}
```

`PlumbedCoordinatorBase` supplies `nav`, `routeNav`, `sheetNav`, `linkSwitcher`, `uiSwitcher`, `stackHandoffs`, `sheetHandoffs`, and `dispatchIfPossible(_:baton:)` out of the box. The subclass only needs to add its own observable state and the URL entry point.

### 5. Codec

For table-driven parsing, use `URLPathRouter`:

```swift
struct AppURLCodec {
    private let router = URLPathRouter<AppIntent>(
        scheme: "myapp",
        routes: [
            URLRoute("inbox",
                parse: { _ in .showInbox },
                emit: { intent in
                    if case .showInbox = intent { return URLEmission() }
                    return nil
                }
            ),
            URLRoute("profile/:id",
                parse: { captures in
                    guard let raw = captures["id"], let id = ProfileID(rawValue: raw) else { return nil }
                    return .showProfile(id: id)
                },
                emit: { intent in
                    if case .showProfile(let id) = intent {
                        return URLEmission(id.rawValue)
                    }
                    return nil
                }
            ),
        ]
    )

    func parse(_ url: URL) -> AppIntent? {
        router.parse(url)
    }

    func url(for intent: AppIntent) -> URL? {
        router.url(for: intent)
    }
}
```

Pattern grammar for `URLRoute`:

- `host/segment` — literal path segment after the host.
- `host/:name` — named capture, retrievable via `captures["name"]`.
- `host?q&r` — query parameter names; values surface via `captures["q"]`.
- `host` — bare host with no path or query.

Parse and emit live on the same `URLRoute` so the pair cannot drift apart silently. `URLEmission` carries only the path segments AFTER the host — `URLPathRouter` already knows the host from the pattern, so `URLEmission(id.rawValue)` for `"profile/:id"` produces `myapp://profile/<id>`, not `myapp://profile/profile/<id>`.

For an alternative state-aware codec that resolves the same URL to different intents depending on current navigation state, write a custom `URLParsing` conformance that takes a snapshot. See the showcase piece on the state-aware resolver in the AD vault for a worked example. The basic case is the table-driven router above.

### 6. App entry

```swift
@main
struct App: SwiftUI.App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: coordinator.nav.pathBinding) {
                RootView()
                    .navigationDestination(for: AppRoute.self) { route in
                        switch route {
                        case .inbox:
                            InboxView()
                        case .profile(let id):
                            ProfileView(id: id)
                        }
                    }
            }
            .sheet(item: coordinator.nav.sheetBinding) { route in
                switch route {
                case .settings:
                    SettingsView()
                }
            }
            .onOpenURL { url in
                coordinator.open(url)
            }
        }
    }
}
```

The `NavigationStack(path:)` binding and the `.sheet(item:)` binding both come from the inherited `NavigationFacade`. The `.onOpenURL` modifier is the standard SwiftUI universal-link / custom-scheme entry point; route every incoming URL through `coordinator.open(_:)`.

## Adding side-effects

When the URL needs to drive non-navigation state (search filters, list filters, scrolls, overlays), declare a `SideEffect` enum and override `apply(_:_:)`. Assume `AppIntent` is extended with an `openSearch(query: String)` case for the example below.

```swift
enum AppEffect: Sendable, Equatable {
    case applySearchQuery(String)
    case clearSearchQuery
}

enum AppFlow: NavigationFlow {
    typealias Intent = AppIntent
    typealias Route = AppRoute
    typealias SheetRoute = AppSheetRoute
    typealias SideEffect = AppEffect

    static func operations(intent: Intent) -> [Step<Route, SheetRoute, AppEffect>] {
        switch intent {
        case .openSearch(let query):
            return [.nav(.popToRoot), .effect(.applySearchQuery(query))]
        // ...
        }
    }
}

@MainActor
@Observable
final class AppCoordinator: PlumbedCoordinatorBase<AppFlow> {

    var searchQuery: String?

    override func apply(_ effect: AppEffect, _ baton: Baton<AppIntent>) async {
        switch effect {
        case .applySearchQuery(let q):
            searchQuery = q
        case .clearSearchQuery:
            searchQuery = nil
        }
    }
}
```

Views read `coordinator.searchQuery` directly. Taps that want the same write pattern call helper methods on the coordinator or construct a URL and call `open(_:)` — see the control-surface showcase piece for the "one apply switch for taps and URLs" pattern.

`apply` runs on `@MainActor` and is `async`. Check `Task.isCancelled` if a single effect's branch does long work; the base class checks cancellation between steps automatically.

## Hand-offs to destination views

When a destination view needs the original `Baton` (typically to inspect the intent payload after it has mounted), use the library's `.onLink(from:consume:)` view modifier with the registry's per-route handoff lookup. Iris registers the handoff during `Step.nav(.push)` / `Step.nav(.present)` dispatch; the view looks it up by route.

`stackHandoffs.handoff(for:)` returns `Handoff<Intent>?` (optional, because no handoff exists for routes the user navigated to manually). `.onLink` has an optional-handoff overload that returns the view unchanged on `nil`, so the modifier is safe to attach unconditionally.

```swift
.navigationDestination(for: AppRoute.self) { route in
    switch route {
    case .profile(let id):
        ProfileView(id: id)
            .onLink(from: coordinator.stackHandoffs.handoff(for: route)) { baton in
                // consume baton.intent here
            }
    case .inbox:
        InboxView()
    }
}
```

`HandoffRegistry` auto-cleans the entry once the handoff transitions to `.delivered` (the consumer claimed, or its task cancelled). For sheet destinations, the same pattern applies with `coordinator.sheetHandoffs.handoff(for: route)` instead of `stackHandoffs`.

## Multicast subscriptions

If multiple subsystems need to observe link arrivals (the coordinator plus an analytics surface, for instance), wire a `Broadcaster<URLCodec>`. It parses URLs once, wraps them in batons, and yields to all active subscribers. New subscribers receive the last baton by default. Create one broadcaster per app, not per URL — it is an actor designed to be long-lived.

## Anti-patterns

These are things an agent might reach for that do not fit the library's grain. Each one has a documented reason.

### Do not put structural cases in `SideEffect`

```swift
// WRONG
enum AppEffect {
    case pushProfile(ProfileID)   // structural navigation; belongs in Step.nav
    case applySearchQuery(String) // state write; correct for SideEffect
}
```

Push, present, pop, and dismiss are structural — express them as `Step.nav(.push(...))` etc. The library's executor dispatches them for free. Moving them into `SideEffect` duplicates the navigators' job in the consumer's `apply` switch and bypasses the library's animation-pause handling between structural steps.

### Do not call `apply(_:_:)` from views

`apply` is the protocol requirement the library calls. Views read coordinator state; they do not drive the apply switch. To trigger an effect from a tap, either expose a coordinator method (`coordinator.tapApplySearch(query:)`) that writes the same property `apply` would, or construct the equivalent URL and call `coordinator.open(_:)` so the tap and the URL hit the same apply switch. The latter pattern is documented in the control-surface showcase piece.

### Do not bypass `route(baton:)` and apply steps manually

`route(baton:)` runs inside `linkSwitcher.run`, which cancels any in-flight earlier link. Manually iterating `Flow.operations(intent:)` and dispatching steps yourself loses latest-wins cancellation. The flow's step list is correct; the executor is what makes a second URL supersede a first.

### Do not override `dispatchIfPossible(_:baton:)` in subclasses

`PlumbedCoordinatorBase` overrides it to dispatch via the bundled `nav` facade and registries. Subclasses overriding it again silently break structural navigation. The base override is correct; let it run.

### Do not declare `dispatchIfPossible` in a protocol extension only

The protocol requirement must be on the protocol body, not extension-only. If moved into the extension, every nav step resolves to the extension's empty default and structural navigation silently no-ops. Effects keep working, which makes the regression easy to miss in tests that only assert on effect state. See the doc comment on the requirement declaration in `RouteCoordinator.swift` for the full Swift-dispatch reasoning.

### Do not create a new `Broadcaster` per URL

The broadcaster is an actor that holds subscriber continuations. Create one per app and reuse. Per-URL instances lose subscribers between URLs.

### Do not skip the `Identifiable` conformance on `SheetRoute`

Iris drives `.sheet(item:)` from the sheet binding, which needs `Identifiable`. `Hashable` alone is not sufficient. `PlumbedCoordinatorBase`'s `where` clause requires `Flow.SheetRoute: Identifiable & Hashable & Sendable`, and `Never` does not conform to `Identifiable`, so a stack-only app still needs a placeholder enum with one dummy case (see the Routes section above).

### Do not store the `Baton` long-term

Batons are one-shot event references. `Equatable` and `Hashable` compare by `id` only — two batons with identical `intent` and `flow` compare unequal because each `init` generates a fresh `id`. Storing them defeats their identity semantics. If you need the intent later, store the intent.

## Where else to look

- DocC catalogue at `Sources/Iris/Iris.docc/`. Renders in Xcode's documentation viewer and on Swift Package Index.
- Five scaffolding skill templates at `Sources/Iris/Excluded/Skills/*/SKILL.md`:
  - `iris-bootstrap` — generates the Intent / routes / flow / codec / coordinator / app-entry wiring end to end.
  - `iris-test-scaffold` — generates Swift Testing suites for codec, flow, and handoff lifecycle.
  - `iris-audit` — runs eight wiring-coverage checks against an existing consumer.
  - `iris-visualize` — produces a Mermaid diagram of the URL to Intent to Step to Route to View pipeline.
  - `iris-url-catalog` — produces a Markdown table of every supported URL.
- Showcase pieces in the AD vault (`content/iris-*-showcase.md`) for measurement-led writeups on race handling, surface area, state-aware resolution, and the control-surface pattern.
