// Copyright 2026 Async Digital Ltd. All rights reserved.

import Foundation
import Observation

/// Stores ``Handoff`` instances keyed by route, separating handoff
/// lifecycle from route identity.
///
/// Without a registry, handoffs must be embedded as associated values in route
/// enum cases, forcing custom `Equatable`/`Hashable` implementations.
/// `HandoffRegistry` lets routes remain plain `Hashable` enums with
/// auto-synthesised conformances.
///
/// `@Observable` — views that read `handoff(for:)` inside their body re-render
/// when ``register(for:)`` overwrites an entry, so they pick up the new handoff
/// identity and restart their `.task(id: ObjectIdentifier(handoff))` claim.
/// Without observation, a re-pushed link to an already-mounted route would
/// register a fresh handoff that the view's `.task` never sees.
///
/// **Lifecycle is library-managed.** Handoffs auto-remove from the registry when
/// they transition to `.delivered` (any path: waiter resumed, buffered baton
/// claimed, waiter cancelled). Consumers don't manage entries by hand.
@Observable
@MainActor
public final class HandoffRegistry<Route: Hashable & Sendable, Intent: Sendable & Equatable> {
    private var store: [Route: Handoff<Intent>] = [:]

    public init() {}

    /// Creates and registers a fresh handoff for the given route, replacing any
    /// existing one. The handoff auto-removes itself from the registry when it
    /// transitions to `.delivered`.
    @discardableResult
    public func register(for route: Route) -> Handoff<Intent> {
        let handoff = Handoff<Intent>(onDelivered: { [weak self] identity in
            Task { @MainActor [weak self] in
                self?.removeIfMatches(route: route, identity: identity)
            }
        })
        store[route] = handoff
        return handoff
    }

    /// Returns the handoff currently registered for this route, if any.
    public func handoff(for route: Route) -> Handoff<Intent>? {
        store[route]
    }

    /// Removes an entry only if it still points at the same handoff instance.
    /// Prevents the auto-clean callback from removing a freshly registered
    /// replacement that landed while the callback was dispatching back to
    /// `@MainActor`.
    private func removeIfMatches(route: Route, identity: ObjectIdentifier) {
        guard let current = store[route], ObjectIdentifier(current) == identity else { return }
        store.removeValue(forKey: route)
    }
}
