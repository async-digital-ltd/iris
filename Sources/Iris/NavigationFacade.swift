// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

import SwiftUI

/// Unified interface for coordinating navigation stack and modal sheet operations.
///
/// Consolidates push/pop and present/dismiss behind a single API so coordinators
/// don't need to interact with separate navigator instances. Generic over the
/// route and sheet *types*, not over navigator implementations. The underlying
/// concrete navigators are ``GenericRouteNavigator`` and
/// ``GenericSheetNavigator``.
@MainActor
public struct NavigationFacade<Route: Hashable & Sendable, Sheet: Identifiable & Hashable & Sendable> {
    public let route: GenericRouteNavigator<Route>
    public let sheet: GenericSheetNavigator<Sheet>

    public init(route: GenericRouteNavigator<Route>, sheet: GenericSheetNavigator<Sheet>) {
        self.route = route
        self.sheet = sheet
    }

    // MARK: Bindings

    /// Binding for driving `NavigationStack(path:)`.
    public var pathBinding: Binding<[Route]> { route.pathBinding }

    /// Binding for driving `.sheet(item:)`.
    public var sheetBinding: Binding<Sheet?> { sheet.sheetBinding }

    // MARK: Truth State

    /// The route at the top of the stack, or `nil` if at root.
    public var stackTop: Route? { route.routeStack.currentRoute }

    /// Number of routes in the stack (0 = root only).
    public var stackDepth: Int { route.routeStack.routes.count }

    /// The currently presented sheet, or `nil`.
    public var sheetTop: Sheet? { sheet.routeSheet }

    // MARK: Stack Operations

    public func push(_ stackRoute: Route, flow: NavFlow = .current) {
        route.push(stackRoute, flow)
    }

    public func popToRoot(flow: NavFlow = .current) { route.popToRoot(flow) }

    public func replaceTop(with stackRoute: Route, flow: NavFlow = .current) {
        route.replaceTop(stackRoute, flow)
    }

    /// Pushes the route if it isn't already at the top; otherwise does nothing.
    public func ensureTop(_ stackRoute: Route, flow: NavFlow = .current) {
        route.ensureTop(stackRoute, flow)
    }

    public func resetStack(flow: NavFlow = .current) { route.reset(flow) }

    /// Pushes the route only if it's not already at the top.
    ///
    /// - Returns: `true` if pushed, `false` if already at top or cancelled.
    @discardableResult
    public func pushIfNeeded(_ stackRoute: Route, flow: NavFlow = .current) -> Bool {
        if Task.isCancelled { return false }
        return route.pushIfNeeded(stackRoute, flow)
    }

    // MARK: Sheet Operations

    public func present(_ sheetRoute: Sheet, flow: NavFlow = .current) {
        sheet.present(sheetRoute, flow)
    }

    public func dismissSheet(flow: NavFlow = .current) { sheet.dismissSheet(flow) }

    /// Presents the sheet only if it's not already presented.
    ///
    /// - Returns: `true` if presented, `false` if already shown or cancelled.
    @discardableResult
    public func presentIfNeeded(_ sheetRoute: Sheet, flow: NavFlow = .current) -> Bool {
        if Task.isCancelled { return false }
        return sheet.presentIfNeeded(sheetRoute, flow)
    }

    /// Transitions to a target sheet state, dismissing or presenting as needed.
    ///
    /// Yields to the main run loop between state changes to allow SwiftUI
    /// animations to complete.
    public func transition(to target: Sheet?, flow: NavFlow = .current) async {
        if Task.isCancelled { return }
        await sheet.transition(to: target, flow)
    }
}
