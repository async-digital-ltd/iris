# Hand-offs

Deliver the original link payload to the destination view once it
has mounted.

## Overview

A link's payload often needs to reach a screen that isn't on
screen yet. Pushing `/conversation/42` mounts a new conversation view
— and that view needs the conversation id (and possibly other context
from the original URL) to finish its own initialisation.

Embedding the payload inside the route enum's associated values is one
option, but it forces every route enum case to carry custom
`Equatable` and `Hashable` implementations to avoid breaking
`NavigationStack`'s identity diffing. ``HandoffRegistry`` and
``Handoff`` solve the same problem with route enums that stay
plain `Hashable` with auto-synthesised conformances.

## The model

- A ``Baton`` carries the intent (the consumer-defined payload)
  plus a ``NavFlow`` correlation id.
- A ``Handoff`` is a one-shot rendezvous. It supports both
  patterns:
  - **Producer-first** — the coordinator calls
    ``Handoff/deliver(_:)`` before the destination view has
    mounted; the baton is buffered.
  - **Consumer-first** — the destination view calls
    ``Handoff/claim()`` before the coordinator has delivered;
    the view's task suspends until the baton arrives.
- A ``HandoffRegistry`` stores the handoffs keyed by route, so the
  coordinator can ``HandoffRegistry/register(for:)`` ahead of pushing
  and the view can look up the handoff for its own route.

## End-to-end

In the coordinator (or `dispatchIfPossible` if using
``PlumbedCoordinatorBase``):

```swift
let handoff = stackHandoffs.register(for: .conversation(id: id))
await nav.route.pushRoute(.conversation(id: id), registry: stackHandoffs, baton: baton)
// PlumbedCoordinatorBase calls deliver after the push lands.
```

In the destination view:

```swift
struct ConversationView: View {
    @Environment(\.appCoordinator) private var coordinator
    let route: TopLevel.StackRoute

    var body: some View {
        ConversationContent()
            .task(id: ObjectIdentifier(handoff ?? .init())) {
                guard let handoff,
                      let baton = await handoff.claim() else { return }
                consume(baton)
            }
    }

    private var handoff: Handoff<MessagesIntent>? {
        coordinator.stackHandoffs.handoff(for: route)
    }
}
```

The `.task(id:)` modifier restarts the task whenever the handoff
identity changes — so a re-pushed link to an already-mounted route
registers a fresh handoff that the view picks up on the next render.
That's why ``HandoffRegistry`` is `@Observable`: views reading
``HandoffRegistry/handoff(for:)`` re-render when
``HandoffRegistry/register(for:)`` overwrites an entry.

## Lifecycle is library-managed

Handoffs auto-remove from the registry once they transition to
`.delivered` — by any path:

- A waiter resumed with a posted baton.
- A buffered baton was claimed.
- A waiter was cancelled (the view disappeared before claiming).

Consumers never call a `remove(for:)` method by hand. The auto-clean
callback compares `ObjectIdentifier` before removing, so a freshly
registered replacement that lands while the callback is dispatching
back to `@MainActor` isn't accidentally removed in place of its
predecessor.

## Topics

### Baton

- ``Baton``

### Rendezvous

- ``Handoff``

### Registry

- ``HandoffRegistry``

### Multicast

- ``Broadcaster``
