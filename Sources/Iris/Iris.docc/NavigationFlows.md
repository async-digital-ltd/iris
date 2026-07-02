# Navigation flows

Translate an intent into the ordered list of steps that realise it.

## Overview

Once a URL has been parsed into an `Intent`, the consumer's
``NavigationFlow`` decides what the app should *do* about it:

```swift
public protocol NavigationFlow: Sendable {
    associatedtype Intent: Sendable & Equatable
    associatedtype Route: Hashable & Sendable = Never
    associatedtype SheetRoute: Hashable & Sendable = Never
    associatedtype SideEffect: Sendable = Never

    static func operations(intent: Intent) -> [Step<Route, SheetRoute, SideEffect>]
}
```

`operations(intent:)` returns a sequence of ``Step`` values. Each step
is one of:

- **``Step/nav(_:)``**: a structural ``NavTarget``. Push, present, pop
  to root, or dismiss a sheet. Iris dispatches these itself.
- **``Step/effect(_:)``**: a consumer-defined side-effect. Forwarded to
  the coordinator's `apply(_:_:)` switch.

The split matters: because structural cases never appear in `apply`,
the consumer's switch only covers genuine side-effects. There is no
boilerplate `case .push: assertionFailure(...)` left to write.

## A worked example

```swift
enum MessagesIntent: Equatable {
    case openInbox
    case openConversation(id: ConversationID)
    case applySearchQuery(String)
    case unknown
}

enum MessagesEffect: Equatable {
    case applyQuery(String)
}

enum MessagesFlow: NavigationFlow {
    typealias Intent = MessagesIntent
    typealias Route = TopLevel.StackRoute
    typealias SheetRoute = TopLevel.SheetRoute
    typealias SideEffect = MessagesEffect

    static func operations(intent: MessagesIntent) -> [Step<Route, SheetRoute, SideEffect>] {
        switch intent {
        case .openInbox:
            return [.nav(.popToRoot)]

        case .openConversation(let id):
            return [
                .nav(.popToRoot),
                .nav(.push(.conversation(id: id))),
            ]

        case .applySearchQuery(let q):
            return [
                .nav(.popToRoot),
                .effect(.applyQuery(q)),
            ]

        case .unknown:
            return []
        }
    }
}
```

Reading the cases:

- `openInbox` resets to root: no further work.
- `openConversation` resets *then* pushes; the coordinator runs them in
  order with a small pause between transitions so SwiftUI can commit
  the pop animation before the push lands.
- `applySearchQuery` resets, then emits an `applyQuery` effect for
  the coordinator's `apply(_:_:)` to handle (the coordinator owns
  whatever state powers the search field).
- `unknown` returns an empty list, a deliberate no-op.

## What the flow is *not* responsible for

`operations(intent:)` is pure: same intent in, same step list out. It
declares **what should be shown**, never **how or when the baton is
handed off**.

That separation is load-bearing:

- Timing between steps lives on the coordinator
  (``RouteCoordinator/interStepAnimationPause``).
- Animation boundaries are managed by SwiftUI as each
  ``NavTarget`` lands.
- Baton delivery to destination views happens through
  ``HandoffRegistry`` and ``Handoff``, dispatched from the
  coordinator, not the flow.

The flow doesn't `await`, doesn't talk to actors, doesn't read state.
This keeps it trivially testable: feed it intents, assert on the step
list. Every other moving part is tested separately.

## NavFlow: the correlation context

``NavFlow`` is a separate concept from `NavigationFlow`. It's a
correlation identifier carried inside every ``Baton``:

```swift
public struct NavFlow: Sendable, Equatable {
    public let id: UUID
    public let source: String  // "link", "tap", ...
}
```

A single link can fan out across multiple coordinators and
intent-type boundaries. `NavFlow` gives each event a stable identity so
debug log lines printing `[FLOW <id>]` can be grepped end-to-end. It
does *not* propagate cancellation: that's
``LatestWinsExecutor``'s job.

A bound flow is available to navigator calls inside
``NavFlow/withScope(_:_:)``, and to tap-driven calls via
``NavFlow/tap(_:)``. Outside any scope, ``NavFlow/current`` returns a
fresh tap flow per read, so navigator calls at tap sites get a usable
flow id without explicit wrapping.

## Topics

### The flow protocol

- ``NavigationFlow``

### Step model

- ``Step``
- ``NavTarget``

### Correlation context

- ``NavFlow``
