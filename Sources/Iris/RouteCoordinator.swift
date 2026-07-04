// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

import Foundation

/// Orchestrates multi-step link navigation flows.
///
/// Breaks down a navigation intent into a sequence of ``Step`` values via a
/// ``NavigationFlow`` and applies them in order. Structural ``Step/nav(_:)``
/// cases are dispatched by the library; ``Step/effect(_:)`` cases are forwarded to
/// ``apply(_:_:)`` for consumer side-effect handling. Only the most recent
/// flow runs; earlier flows are cancelled via ``LatestWinsExecutor``.
@MainActor
public protocol RouteCoordinator: AnyObject {
    associatedtype Intent: Sendable & Equatable
    associatedtype Flow: NavigationFlow where Flow.Intent == Intent

    /// The executor that cancels earlier flows when a new link arrives.
    var linkSwitcher: LatestWinsExecutor { get }

    /// Applies a single side-effect emitted by the flow.
    ///
    /// Structural cases (push/present/pop/dismiss) are handled by the library and
    /// never appear here; this switch only covers the consumer's own
    /// `SideEffect` cases.
    ///
    /// - Parameters:
    ///   - effect: The side-effect value to apply.
    ///   - baton: The original baton, available for forwarding to child destinations.
    func apply(_ effect: Flow.SideEffect, _ baton: Baton<Intent>) async

    /// Dispatches a structural ``NavTarget`` (push/present/pop/dismiss).
    ///
    /// **Important: keep this declaration on the protocol body.** It must be
    /// a protocol requirement (not extension-only) so that
    /// ``PlumbedCoordinatorBase``'s implementation is reached via dynamic
    /// dispatch from ``route(baton:)``.
    ///
    /// Swift's rule: methods declared in a protocol body are dispatched
    /// dynamically through the witness table; methods defined only in a
    /// protocol extension are dispatched statically based on the type the
    /// compiler sees at the call site. ``route(baton:)`` is itself a
    /// protocol-extension method, and its call to `self.dispatchIfPossible`
    /// resolves at compile time. If this declaration is moved into the
    /// extension, every nav step (push/present/pop/dismiss) will resolve to
    /// the extension's empty default: `PlumbedCoordinatorBase`'s override
    /// never runs and structural navigation silently no-ops. Effects keep
    /// working (``apply(_:_:)`` is a protocol requirement) which makes the
    /// regression easy to miss in tests that only assert on effect state.
    ///
    /// The Swift Programming Language calls this out under "Protocol
    /// Extensions" (search: "Methods defined in a protocol extension").
    func dispatchIfPossible(
        _ target: NavTarget<Flow.Route, Flow.SheetRoute>,
        baton: Baton<Intent>
    ) async
}

public extension RouteCoordinator {
    /// Pause inserted between steps so SwiftUI can commit each transition's
    /// animation (sheet dismiss, stack push, etc.) before the next step fires.
    ///
    /// Defaults to `.zero`, which is right for non-animated chains. Coordinators driving
    /// mixed sheet/stack flows should override with a duration that covers the
    /// longest transition (~700ms is a safe floor for sheet-dismiss → stack-push).
    static var interStepAnimationPause: Duration { .zero }

    /// Converts the baton's intent into steps and applies them sequentially.
    ///
    /// Runs inside ``linkSwitcher`` so a newer link cancels any
    /// in-progress flow. Binds ``NavFlow/current`` to the baton's flow for the
    /// duration of step application, so ``apply(_:_:)`` (and any navigator
    /// calls it makes) can omit the explicit `flow:` argument. Checks
    /// `Task.isCancelled` between steps and sleeps for
    /// ``interStepAnimationPause`` between them when non-zero.
    func route(baton: Baton<Intent>) {
        linkSwitcher.run { @MainActor [weak self] in
            guard let self else { return }
            await NavFlow.withScope(baton.flow) {
                for op in Flow.operations(intent: baton.intent) {
                    if Task.isCancelled { break }
                    switch op {
                    case .nav(let target):
                        // `dispatchIfPossible` MUST be a protocol requirement
                        // for this call to dispatch dynamically; see the doc
                        // on the requirement declaration above.
                        await self.dispatchIfPossible(target, baton: baton)
                    case .effect(let effect):
                        await self.apply(effect, baton)
                    }
                    if Task.isCancelled { break }
                    if Self.interStepAnimationPause > .zero {
                        try? await Task.sleep(for: Self.interStepAnimationPause)
                    }
                }
            }
        }
    }

    /// Bridge for the bare ``RouteCoordinator`` protocol: a no-op for
    /// `.nav` cases. ``PlumbedCoordinatorBase`` overrides this to actually
    /// dispatch via the bundled facade and handoff registries.
    func dispatchIfPossible(
        _ target: NavTarget<Flow.Route, Flow.SheetRoute>,
        baton: Baton<Intent>
    ) async {}
}

extension RouteCoordinator {
    /// Dispatches a structural ``NavTarget`` to the given facade and handoff
    /// registries.
    ///
    /// Internal: ``PlumbedCoordinatorBase`` exposes a 2-arg
    /// ``PlumbedCoordinatorBase/dispatchIfPossible(_:baton:)`` that forwards
    /// here using the base's nav and registries.
    @MainActor
    func dispatch<Route: Hashable & Sendable, Sheet: Identifiable & Hashable & Sendable>(
        _ target: NavTarget<Route, Sheet>,
        on nav: NavigationFacade<Route, Sheet>,
        stackHandoffs: HandoffRegistry<Route, Intent>,
        sheetHandoffs: HandoffRegistry<Sheet, Intent>,
        baton: Baton<Intent>
    ) async {
        if Task.isCancelled { return }
        switch target {
        case .push(let route):
            await nav.route.pushRoute(route, registry: stackHandoffs, baton: baton)
        case .present(let sheet):
            await nav.sheet.presentRoute(sheet, registry: sheetHandoffs, baton: baton)
        case .popToRoot:
            nav.popToRoot()
        case .dismissSheet:
            nav.dismissSheet()
        }
    }
}

/// Open base class for coordinators that want the library's plumbing (navigators,
/// facade, executors, and handoff registries) out of the box.
///
/// Subclasses declare:
/// - the `Flow` generic parameter (a ``NavigationFlow`` defining their
///   `Intent`, `Route`, `SheetRoute`, and `SideEffect` shapes)
/// - their own observable state (`@Observable` on the subclass)
/// - an override of ``apply(_:_:)`` that handles their flow's side-effects
///
/// Everything else (`linkSwitcher`, `uiSwitcher`, `nav`, `stackHandoffs`,
/// `sheetHandoffs`, and the structural step dispatcher) is inherited.
///
/// ```swift
/// @MainActor @Observable
/// final class MessagesCoordinator: PlumbedCoordinatorBase<MessagesFlow> {
///     var activeQuery: String?
///     override func apply(_ effect: MessagesEffect, _ baton: Baton<MessagesIntent>) async {
///         switch effect {
///         case .applyQuery(let q): activeQuery = q
///         ...
///         }
///     }
/// }
/// ```
@MainActor
open class PlumbedCoordinatorBase<Flow: NavigationFlow>: RouteCoordinator
where Flow.Route: Hashable & Sendable, Flow.SheetRoute: Identifiable & Hashable & Sendable {
    public typealias Intent = Flow.Intent

    public let routeNav: GenericRouteNavigator<Flow.Route>
    public let sheetNav: GenericSheetNavigator<Flow.SheetRoute>
    public let nav: NavigationFacade<Flow.Route, Flow.SheetRoute>
    public let linkSwitcher: LatestWinsExecutor
    public let uiSwitcher: LatestWinsExecutor
    public let stackHandoffs: HandoffRegistry<Flow.Route, Intent>
    public let sheetHandoffs: HandoffRegistry<Flow.SheetRoute, Intent>

    public init() {
        let routeNav = GenericRouteNavigator<Flow.Route>()
        let sheetNav = GenericSheetNavigator<Flow.SheetRoute>()
        self.routeNav = routeNav
        self.sheetNav = sheetNav
        self.nav = NavigationFacade(route: routeNav, sheet: sheetNav)
        self.linkSwitcher = LatestWinsExecutor(policy: .links)
        self.uiSwitcher = LatestWinsExecutor(policy: .ui)
        self.stackHandoffs = HandoffRegistry()
        self.sheetHandoffs = HandoffRegistry()
    }

    /// Subclasses override to handle their flow's side-effects.
    ///
    /// The default implementation is a no-op, appropriate for a `SideEffect`
    /// of `Never`, which makes any call here unreachable anyway.
    open func apply(_ effect: Flow.SideEffect, _ baton: Baton<Intent>) async {}

    public func dispatchIfPossible(
        _ target: NavTarget<Flow.Route, Flow.SheetRoute>,
        baton: Baton<Intent>
    ) async {
        await dispatch(
            target,
            on: nav,
            stackHandoffs: stackHandoffs,
            sheetHandoffs: sheetHandoffs,
            baton: baton
        )
    }
}
