# Iris

A small Swift package for routing incoming URLs (custom-scheme deep links
and Universal Links alike) into typed SwiftUI navigation, without
hand-rolling navigation plumbing for each new screen.

## What it does

- Turns an incoming URL into an app-defined `Intent` via your `URLParsing` codec.
- A `NavigationFlow` translates each intent into a list of `Step` values:
  - `Step.nav(.push/.present/.popToRoot/.dismissSheet)`: structural navigation, dispatched by Iris.
  - `Step.effect(_)`: consumer-defined side-effects, handled in your coordinator's `apply(_:_:)`.
- `PlumbedCoordinatorBase<Flow>` ships the navigators, facade, executors,
  and stack/sheet `HandoffRegistry`s out of the box; subclasses just declare
  their `Flow` and override `apply(_:_:)` when there are effects to handle.
- Latest-wins cancellation so a newer link supersedes one in flight.
- Hand-off batons let destination views consume the link payload once
  the screen mounts; the registry auto-cleans on `.delivered`.

## Requirements

- iOS 17+ or macOS 14+
- Swift 6.0 / Xcode 16+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/async-digital-ltd/iris.git", from: "1.0.0")
]
```

…and depend on the `Iris` product from any target that needs it.

## Quick sketch

```swift
// 1. Define your flow.
enum MyFlow: NavigationFlow {
    typealias Intent = MyIntent
    typealias Route = TopLevel.StackRoute
    typealias SheetRoute = TopLevel.SheetRoute

    static func operations(intent: Intent) -> [Step<Route, SheetRoute, Never>] {
        switch intent {
        case .showInbox:
            return [.nav(.popToRoot), .nav(.push(.inbox))]
        case .showProfile(let id):
            return [.nav(.popToRoot), .nav(.push(.profile(id: id)))]
        case .unknown:
            return []
        }
    }
}

// 2. Subclass PlumbedCoordinatorBase.
@MainActor @Observable
final class AppCoordinator: PlumbedCoordinatorBase<MyFlow> {}

// 3. Drive NavigationStack from the inherited facade.
NavigationStack(path: coordinator.nav.pathBinding) {
    RootView()
        .navigationDestination(for: TopLevel.StackRoute.self) { route in
            // …
        }
}
.sheet(item: coordinator.nav.sheetBinding) { route in
    // …
}
```

## Scaffolding skills

`Sources/Iris/Excluded/Skills/` holds five `SKILL.md` templates aimed
at coding agents (excluded from the SwiftPM target). They scaffold a new
consumer end to end:

- `iris-bootstrap`: generates the Intent / routes / flow / codec /
  coordinator / app-entry wiring.
- `iris-test-scaffold`: generates Swift Testing suites for codec, flow,
  and handoff lifecycle.
- `iris-audit`: runs eight wiring-coverage checks against an existing
  consumer.
- `iris-visualize`: produces a Mermaid diagram of the URL → Intent →
  Step → Route → View pipeline.
- `iris-url-catalog`: produces a Markdown table of every supported URL.

## License

See [LICENSE](LICENSE).
