// Copyright 2026 Async Digital Ltd. All rights reserved.

import SwiftUI

// MARK: - GenericRouteNavigator

/// Drives a `NavigationStack` path backed by a ``RouteStack``.
///
/// Owns the stack state plus the binding SwiftUI consumes. Coordinators
/// usually interact with this through ``NavigationFacade`` rather than
/// directly.
@Observable
@MainActor
public final class GenericRouteNavigator<R: Hashable & Sendable> {
    public var routeStack = RouteStack<R>()

    public init() {}

    // MARK: Sanitisation

    /// Removes consecutive duplicate routes from the path.
    ///
    /// Override on a subclass to customise. Default collapses adjacent
    /// repeats so the same route can't appear twice in a row.
    public func sanitise(_ path: [R]) -> [R] {
        var result: [R] = []
        for route in path {
            if result.last == route { continue }
            result.append(route)
        }
        return result
    }

    // MARK: Binding

    /// Binding for driving `NavigationStack(path:)`, with automatic sanitization.
    public var pathBinding: Binding<[R]> {
        Binding(
            get: { self.routeStack.routes },
            set: { newValue in
                let sanitised = self.sanitise(newValue)
                self.routeStack.reset(to: sanitised)
            }
        )
    }

    // MARK: Stack Operations

    public func push(_ route: R, _ flow: NavFlow = .current) {
        routeStack.push(route)
    }

    public func popToRoot(_ flow: NavFlow = .current) {
        routeStack.popToRoot()
    }

    /// Pushes the route only if it's not already at the top.
    ///
    /// Honours task cancellation: returns `false` (without mutating the stack)
    /// when the current task is cancelled.
    ///
    /// - Returns: `true` if pushed, `false` if already at top or cancelled.
    @discardableResult
    public func pushIfNeeded(_ route: R, _ flow: NavFlow = .current) -> Bool {
        if Task.isCancelled { return false }
        if let top = routeStack.currentRoute, top == route {
            return false
        }
        push(route, flow)
        return true
    }

    /// Replaces the top route, maintaining the same stack depth.
    public func replaceTop(_ route: R, _ flow: NavFlow = .current) {
        routeStack.replaceTop(with: route)
    }

    /// If the route is already at the top, replaces it; otherwise pushes it.
    public func ensureTop(_ route: R, _ flow: NavFlow = .current) {
        if let top = routeStack.currentRoute, top == route {
            replaceTop(route, flow)
            return
        }
        push(route, flow)
    }

    public func reset(_ flow: NavFlow = .current) {
        popToRoot(flow)
    }

    public func reset(to pathRoute: [R]) {
        routeStack.reset(to: pathRoute)
    }

    // MARK: Handoff-Aware Push

    /// Pushes a route and delivers a baton via the handoff registry.
    ///
    /// Three cases:
    /// - Route not on top: push it, register a fresh handoff, deliver the baton
    ///   (waiter resumes when the new view mounts and claims).
    /// - Route already on top and an existing handoff has a waiting claimant:
    ///   deliver to the existing handoff so the mounted view's `.task` resumes
    ///   without a duplicate push.
    /// - Route already on top but no waiting claimant (handoff already
    ///   delivered, or no handoff yet): register a fresh handoff and deliver
    ///   the baton into it. ``HandoffRegistry`` is `@Observable`, so the view
    ///   re-renders, captures the new handoff identity, and its
    ///   `.task(id: ObjectIdentifier(handoff))` restarts to claim the buffered baton.
    public func pushRoute<Intent: Sendable & Equatable>(
        _ route: R,
        registry: HandoffRegistry<R, Intent>,
        baton: Baton<Intent>
    ) async {
        let flow = baton.flow
        let didPush = pushIfNeeded(route, flow)
        if didPush {
            let handoff = registry.register(for: route)
            await handoff.deliver(baton)
        } else {
            if let existing = registry.handoff(for: route),
               await existing.deliver(baton) {
                // Waiter resumed: no fresh handoff, no duplicate push.
            } else {
                let handoff = registry.register(for: route)
                await handoff.deliver(baton)
            }
        }
        await Task.waitOneTick()
    }
}

// MARK: - GenericSheetNavigator

/// Drives a `.sheet(item:)` modifier backed by an optional route.
///
/// Owns the presented-sheet state plus the binding SwiftUI consumes.
/// Coordinators usually interact with this through ``NavigationFacade``
/// rather than directly.
@Observable
@MainActor
public final class GenericSheetNavigator<S: Identifiable & Hashable & Sendable> {
    public var routeSheet: S?

    public init() {}

    // MARK: Sanitisation

    /// Sanitises a proposed sheet route before applying it.
    /// Override on a subclass to customise; default returns the input.
    public func sanitizeSheet(_ proposed: S?) -> S? { proposed }

    // MARK: Binding

    /// Binding for driving `.sheet(item:)`, with automatic sanitization.
    public var sheetBinding: Binding<S?> {
        Binding(
            get: { self.routeSheet },
            set: { incoming in
                let sanitised = self.sanitizeSheet(incoming)
                self.routeSheet = sanitised
            }
        )
    }

    public var currentRoute: S? { routeSheet }

    // MARK: Sheet Operations

    public func present(_ route: S, _ flow: NavFlow = .current) {
        routeSheet = route
    }

    public func dismissSheet(_ flow: NavFlow = .current) {
        routeSheet = nil
    }

    /// Presents the sheet only if it's not already the current sheet.
    ///
    /// Honours task cancellation: returns `false` (without mutating the
    /// presented sheet) when the current task is cancelled.
    ///
    /// - Returns: `true` if presented, `false` if already shown or cancelled.
    @discardableResult
    public func presentIfNeeded(_ sheet: S, _ flow: NavFlow = .current) -> Bool {
        if Task.isCancelled { return false }
        if routeSheet == sheet {
            return false
        }
        present(sheet, flow)
        return true
    }

    /// Transitions to a target sheet state with proper sequencing.
    ///
    /// Yields to the main run loop between dismiss and present to allow
    /// SwiftUI animations to complete. Respects task cancellation.
    public func transition(to target: S?, _ flow: NavFlow = .current) async {
        if Task.isCancelled { return }
        if target == routeSheet { return }
        if Task.isCancelled { return }

        guard let target else {
            dismissSheet(flow)
            await Task.waitOneTick()
            return
        }

        if routeSheet == nil {
            present(target, flow)
            await Task.waitOneTick()
            return
        }

        // swap: dismiss -> yield -> present -> yield
        dismissSheet(flow)
        await Task.waitOneTick()
        if Task.isCancelled { return }
        present(target, flow)
        await Task.waitOneTick()
    }

    // MARK: Handoff-Aware Present

    /// Presents a sheet and delivers a baton via the handoff registry.
    ///
    /// Mirrors ``GenericRouteNavigator/pushRoute(_:registry:baton:)`` logic
    /// for sheets.
    public func presentRoute<Intent: Sendable & Equatable>(
        _ route: S,
        registry: HandoffRegistry<S, Intent>,
        baton: Baton<Intent>
    ) async {
        let flow = baton.flow
        let didPresent = presentIfNeeded(route, flow)
        if didPresent {
            let handoff = registry.register(for: route)
            await handoff.deliver(baton)
        } else {
            if let existing = registry.handoff(for: route),
               await existing.deliver(baton) {
                // Waiter resumed: no fresh handoff, no duplicate present.
            } else {
                let handoff = registry.register(for: route)
                await handoff.deliver(baton)
            }
        }
        await Task.waitOneTick()
    }
}
