# ``Iris``

Route incoming URLs (custom-scheme deep links and Universal Links alike)
into typed SwiftUI navigation, without hand-rolling navigation plumbing for
each new screen.

## Overview

Iris is built around a five-stage pipeline:

```
URL  ──parse──▶  Intent  ──operations──▶  [Step]  ──dispatch──▶  Route  ──handoff──▶  View
```

Each stage owns one responsibility:

- **Parsing**: ``URLParsing`` converts an incoming `URL` into a
  consumer-defined `Intent`. ``URLPathRouter`` is a ready-made table-driven
  implementation; consumers can also write their own codec.
- **Flow**: A ``NavigationFlow`` declares how each `Intent` decomposes into
  an ordered list of ``Step`` values. Each step is either a structural
  ``NavTarget`` (push, present, pop, dismiss) or a consumer-defined
  side-effect.
- **Dispatch**: A coordinator conforming to ``RouteCoordinator``
  applies the steps in order. Subclassing ``PlumbedCoordinatorBase`` gives a
  consumer the navigators, facade, executors, and registries pre-wired.
- **Cancellation**: ``LatestWinsExecutor`` ensures only the most recent
  link runs to completion; earlier flows are cancelled at their next
  `await` point.
- **Hand-off**: ``HandoffRegistry`` and ``Handoff`` deliver the
  original ``Baton`` to the destination view once it has mounted,
  so the screen can finish initialising itself from the link's payload.

See <doc:URLParsing>, <doc:NavigationFlows>, <doc:Coordinators>, and
<doc:Handoffs> for the conceptual walkthrough of each stage.

## Topics

### Essentials

- <doc:URLParsing>
- <doc:NavigationFlows>
- <doc:Coordinators>
- <doc:Handoffs>

### URL parsing

- ``URLParsing``
- ``URLPathRouter``
- ``URLRoute``
- ``URLPattern``
- ``URLCaptures``
- ``URLEmission``

### Navigation flows

- ``NavigationFlow``
- ``Step``
- ``NavTarget``
- ``NavFlow``

### Coordinator infrastructure

- ``RouteCoordinator``
- ``PlumbedCoordinatorBase``
- ``NavigationFacade``
- ``GenericRouteNavigator``
- ``GenericSheetNavigator``
- ``RouteStack``

### Cancellation

- ``LatestWinsExecutor``
- ``LatestTaskPolicy``
- ``DrainTimeout``

### Hand-offs

- ``Baton``
- ``Handoff``
- ``HandoffRegistry``
- ``Broadcaster``

### Timing

- ``MainRunLoopTick``
