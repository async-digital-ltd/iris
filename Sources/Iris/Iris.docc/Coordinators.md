# Coordinators

Run the steps and dispatch the structural navigation.

## Overview

A coordinator is the runtime piece that takes a ``Baton``,
asks its ``NavigationFlow`` for the matching ``Step`` list, and applies
the steps in order. Iris ships two entry points:

- ``RouteCoordinator``: the protocol. Implement it directly if
  the consumer needs full control of its own navigator wiring.
- ``PlumbedCoordinatorBase``: an open class that bundles every moving
  part the coordinator needs. Almost every consumer wants this.

## Subclassing PlumbedCoordinatorBase

The base class supplies:

- Two ``LatestWinsExecutor`` instances: one for links, one for
  UI taps.
- ``GenericRouteNavigator`` and ``GenericSheetNavigator``, plus a
  ``NavigationFacade`` that owns them.
- Two ``HandoffRegistry`` instances: one keyed by stack route, one
  by sheet route.
- A default ``RouteCoordinator/dispatchIfPossible(_:baton:)``
  that routes ``NavTarget`` values through the facade.

The subclass only declares its `Flow`, its own observable state, and
its `apply(_:_:)` override:

```swift
@MainActor @Observable
final class MessagesCoordinator: PlumbedCoordinatorBase<MessagesFlow> {

    var activeQuery: String?

    override func apply(_ effect: MessagesEffect, _ baton: Baton<MessagesIntent>) async {
        switch effect {
        case .applyQuery(let q):
            activeQuery = q
        }
    }
}
```

The base class is `open`, so subclassing is the supported extension
point.

## Driving SwiftUI from the facade

``NavigationFacade`` exposes the bindings that drive `NavigationStack`
and `.sheet`:

```swift
NavigationStack(path: coordinator.nav.pathBinding) {
    RootView()
        .navigationDestination(for: TopLevel.StackRoute.self) { route in
            destination(for: route)
        }
}
.sheet(item: coordinator.nav.sheetBinding) { route in
    sheetContent(for: route)
}
```

The facade also surfaces direct methods for cases where a tap site
needs to drive the navigator without going through a link:
``NavigationFacade/popToRoot(flow:)`` and
``NavigationFacade/dismissSheet(flow:)``.

## How a step list is applied

When a baton arrives, the coordinator's `route(baton:)` method:

1. Hands the work to the link ``LatestWinsExecutor``, which
   cancels any in-flight earlier flow.
2. Binds ``NavFlow/current`` to the baton's flow so any navigator
   calls inside `apply(_:_:)` can omit the explicit `flow:` argument.
3. Iterates the steps:
   - ``Step/nav(_:)`` cases call
     ``RouteCoordinator/dispatchIfPossible(_:baton:)``, which
     ``PlumbedCoordinatorBase`` routes through the facade and the
     handoff registries.
   - ``Step/effect(_:)`` cases call the subclass's `apply(_:_:)`.
4. Checks `Task.isCancelled` between steps and sleeps for
   ``RouteCoordinator/interStepAnimationPause`` between them
   when that pause is non-zero.

The default `interStepAnimationPause` is `.zero`, which is right for
non-animated chains. Coordinators that drive mixed sheet/stack flows
should override with a duration that covers the longest transition
(~700ms is a safe floor for sheet-dismiss → stack-push).

## Dispatch is dynamic, and that matters

``RouteCoordinator/dispatchIfPossible(_:baton:)`` is declared
on the protocol body deliberately, not in an extension. Protocol-body
methods dispatch dynamically through the witness table; extension-only
methods dispatch statically based on the type the compiler sees.

If `dispatchIfPossible` were moved into the extension, the call from
`route(baton:)` would resolve to the extension's empty default at
compile time, and ``PlumbedCoordinatorBase``'s override would never run.
Structural navigation would silently no-op. Effects would keep working
(``RouteCoordinator/apply(_:_:)`` is also a protocol
requirement), which makes the regression easy to miss in tests that
only assert on effect state.

The lesson the test suite has learned the hard way: when asserting on
the result of a link, assert on both effect state *and*
``NavigationFacade``'s stack/sheet top.

## Topics

### Protocol

- ``RouteCoordinator``

### Base class

- ``PlumbedCoordinatorBase``

### Navigation primitives

- ``NavigationFacade``
- ``GenericRouteNavigator``
- ``GenericSheetNavigator``
- ``RouteStack``
