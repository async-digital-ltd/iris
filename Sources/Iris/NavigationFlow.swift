// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

import Foundation

/// A scripted sequence of navigation operations the router can replay.
///
/// `NavigationFlow` is the protocol a consumer's *flow producer* conforms to.
/// `operations(intent:)` converts a `Baton`'s intent into a list of
/// ``Step`` values, each one either a structural ``NavTarget`` the library
/// dispatches automatically, or a ``SideEffect`` value the coordinator's
/// `apply(_:_:)` switch handles directly.
///
/// > Important:
/// > These operations describe **what should be shown**, not **how or when the
/// > baton is handed off**. Timing, animation boundaries, and
/// > ``Handoff`` posting are the coordinator's responsibility.
public protocol NavigationFlow: Sendable {
    associatedtype Intent: Sendable & Equatable
    associatedtype Route: Hashable & Sendable = Never
    associatedtype SheetRoute: Hashable & Sendable = Never
    associatedtype SideEffect: Sendable = Never

    /// Converts an intent into the sequence of steps that realise it.
    static func operations(intent: Intent) -> [Step<Route, SheetRoute, SideEffect>]
}

/// One unit of work in a navigation flow.
///
/// Either a structural ``NavTarget`` the library dispatches itself, or a
/// consumer-defined `SideEffect` value passed to the coordinator's
/// `apply(_:_:)`. Splitting the two arms means the coordinator's switch only
/// covers genuine side-effects; structural cases never appear there.
public enum Step<Route, SheetRoute, SideEffect>: Sendable
where Route: Hashable & Sendable, SheetRoute: Hashable & Sendable, SideEffect: Sendable {
    case nav(NavTarget<Route, SheetRoute>)
    case effect(SideEffect)
}

extension Step: Equatable where SideEffect: Equatable {}

/// A structural navigation operation the library dispatches on the consumer's
/// behalf: push/present/pop/dismiss without per-case boilerplate in the
/// coordinator's `apply` switch.
public enum NavTarget<Route, SheetRoute>: Sendable, Equatable
where Route: Hashable & Sendable, SheetRoute: Hashable & Sendable {
    case push(Route)
    case present(SheetRoute)
    case popToRoot
    case dismissSheet
}
