// Copyright 2026 Async Digital Ltd. All rights reserved.

import Foundation

/// A lightweight, generic navigation stack for routing.
///
/// Manages an ordered list of `Hashable` routes and exposes navigation
/// primitives (`push`, `popLast`, `popToRoot`, `replaceTop`). The underlying
/// route array is exposed read-only via ``routes`` for tests, snapshots, and
/// derived state such as `stackDepth`.
public struct RouteStack<Route: Hashable> {
    /// Read-only view of the current route sequence, root-first.
    public private(set) var routes: [Route] = []

    @inlinable public var currentRoute: Route? { routes.last }
    @inlinable public var isEmpty: Bool { routes.isEmpty }

    public init() {}

    // MARK: - Navigation primitives

    public mutating func push(_ route: Route) {
        routes.append(route)
    }

    public mutating func popLast() {
        _ = routes.popLast()
    }

    public mutating func popToRoot() {
        routes.removeAll()
    }

    /// Truncates the stack to retain only the first `count` routes.
    ///
    /// - Returns: `true` if the stack changed.
    @discardableResult
    public mutating func popTo(count: Int) -> Bool {
        let originalCount = routes.count
        guard count > 0 else { routes.removeAll(); return originalCount != 0 }
        guard count < originalCount else { return false }
        routes.removeSubrange(count..<originalCount)
        return true
    }

    /// Replaces the current top route, or pushes if the stack is empty.
    public mutating func replaceTop(with route: Route) {
        guard !routes.isEmpty else { routes.append(route); return }
        routes[routes.count - 1] = route
    }

    /// Replaces the entire stack.
    public mutating func reset(to newRoutes: [Route]) {
        routes = newRoutes
    }

    // MARK: - Policy helpers

    /// Pushes the route only if it differs from the current top.
    public mutating func pushIfNeeded(_ route: Route) {
        if let currentRoute, currentRoute == route { return }
        push(route)
    }

    /// Ensures the route is at the top: replaces if already there, pushes otherwise.
    public mutating func ensureTop(_ route: Route) {
        if let currentRoute, currentRoute == route {
            replaceTop(with: route)
        } else {
            push(route)
        }
    }
}
