// Copyright 2026 Async Digital Ltd. All rights reserved.

import Testing
@testable import Iris

@MainActor
struct RouteCoordinatorTests {
    @Test func defaultRouteBindsNavFlowCurrentToBatonFlow() async {
        let coordinator = TestCoordinator()
        let flow = NavFlow(source: "link-route-test")
        let baton = Baton(intent: TestIntent(value: "hello"), flow: flow)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            coordinator.completion = cont
            coordinator.route(baton: baton)
        }

        #expect(coordinator.capturedFlow == flow)
    }

    @Test func defaultRouteAppliesEveryStepInOrder() async {
        let coordinator = TestCoordinator()
        let intent = TestIntent(value: "abc")
        let baton = Baton(intent: intent, flow: NavFlow(source: "ordering-test"))

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            coordinator.completion = cont
            coordinator.route(baton: baton)
        }

        #expect(coordinator.appliedSteps == [.first, .second, .third])
    }

    // MARK: - NavTarget dispatch

    @Test func dispatchPushInvokesStackNavigator() async {
        let coordinator = DispatchCoordinator()
        let route = TestRoute.detail(id: 42)
        let baton = Baton(intent: TestIntent(value: "x"), flow: NavFlow(source: "dispatch"))

        await coordinator.dispatch(
            .push(route),
            on: coordinator.nav,
            stackHandoffs: coordinator.stackHandoffs,
            sheetHandoffs: coordinator.sheetHandoffs,
            baton: baton
        )

        #expect(coordinator.stackNav.path == [route])
    }

    @Test func dispatchPresentInvokesSheetNavigator() async {
        let coordinator = DispatchCoordinator()
        let sheet = TestSheetRoute.preview
        let baton = Baton(intent: TestIntent(value: "x"), flow: NavFlow(source: "dispatch"))

        await coordinator.dispatch(
            .present(sheet),
            on: coordinator.nav,
            stackHandoffs: coordinator.stackHandoffs,
            sheetHandoffs: coordinator.sheetHandoffs,
            baton: baton
        )

        #expect(coordinator.sheetNav.routeSheet == sheet)
    }

    @Test func dispatchPopToRootClearsStack() async {
        let coordinator = DispatchCoordinator()
        coordinator.stackNav.routeStack.push(.detail(id: 1))
        coordinator.stackNav.routeStack.push(.detail(id: 2))
        let baton = Baton(intent: TestIntent(value: "x"), flow: NavFlow(source: "dispatch"))

        await coordinator.dispatch(
            .popToRoot,
            on: coordinator.nav,
            stackHandoffs: coordinator.stackHandoffs,
            sheetHandoffs: coordinator.sheetHandoffs,
            baton: baton
        )

        #expect(coordinator.stackNav.routeStack.routes.isEmpty)
    }

    @Test func dispatchDismissSheetClearsSheet() async {
        let coordinator = DispatchCoordinator()
        coordinator.sheetNav.routeSheet = .preview
        let baton = Baton(intent: TestIntent(value: "x"), flow: NavFlow(source: "dispatch"))

        await coordinator.dispatch(
            .dismissSheet,
            on: coordinator.nav,
            stackHandoffs: coordinator.stackHandoffs,
            sheetHandoffs: coordinator.sheetHandoffs,
            baton: baton
        )

        #expect(coordinator.sheetNav.routeSheet == nil)
    }

    // MARK: - pushRoute "already at top" regression coverage

    @Test func dispatchPushToAlreadyTopRouteDoesNotDuplicate() async {
        let coordinator = DispatchCoordinator()
        let route = TestRoute.detail(id: 1)
        let baton1 = Baton(intent: TestIntent(value: "a"), flow: NavFlow(source: "first"))
        let baton2 = Baton(intent: TestIntent(value: "b"), flow: NavFlow(source: "second"))

        // First dispatch — pushes route and registers handoff.
        await coordinator.dispatch(
            .push(route),
            on: coordinator.nav,
            stackHandoffs: coordinator.stackHandoffs,
            sheetHandoffs: coordinator.sheetHandoffs,
            baton: baton1
        )

        // Second dispatch to same route — must NOT duplicate the stack entry.
        await coordinator.dispatch(
            .push(route),
            on: coordinator.nav,
            stackHandoffs: coordinator.stackHandoffs,
            sheetHandoffs: coordinator.sheetHandoffs,
            baton: baton2
        )

        #expect(coordinator.stackNav.path == [route])
    }

    // MARK: - protocol-dispatch regression
    //
    // Before `dispatchIfPossible` was declared on the protocol, the extension's
    // `route(baton:)` called `self.dispatchIfPossible(...)` via static dispatch
    // and resolved to the extension's empty default — `PlumbedCoordinatorBase`'s
    // implementation never ran. Effects went through `apply(_:_:)` (a protocol
    // requirement, dynamically dispatched) and worked, but nav steps silently
    // no-op'd. This test fires a baton whose ops include push/popToRoot and
    // asserts the navigator actually mutated.

    @Test func routeDispatchesNavStepsThroughPlumbedBase() async {
        let coordinator = PlumbedTestCoordinator()
        let intent = PlumbedIntent.openDetail(id: 7)
        let baton = Baton(intent: intent, flow: NavFlow(source: "regression-#88"))

        coordinator.route(baton: baton)
        while coordinator.linkSwitcher.isBusy() { await Task.yield() }

        #expect(coordinator.nav.route.routeStack.routes == [PlumbedRoute.detail(id: 7)])
    }

    @Test func routeDispatchesPresentThroughPlumbedBase() async {
        let coordinator = PlumbedTestCoordinator()
        let intent = PlumbedIntent.openPreviewSheet
        let baton = Baton(intent: intent, flow: NavFlow(source: "regression-#88"))

        coordinator.route(baton: baton)
        while coordinator.linkSwitcher.isBusy() { await Task.yield() }

        #expect(coordinator.nav.sheet.routeSheet == PlumbedSheet.preview)
    }

    @Test func dispatchPushToAlreadyTopDeliversToWaitingHandoff() async {
        let coordinator = DispatchCoordinator()
        let route = TestRoute.detail(id: 1)
        let baton = Baton(intent: TestIntent(value: "wake-me"), flow: NavFlow(source: "f"))

        // Simulate "view already mounted and waiting": route is on top, a handoff
        // is registered, and a claimant is suspended on it.
        coordinator.stackNav.routeStack.push(route)
        let existingHandoff = coordinator.stackHandoffs.register(for: route)
        async let waited: Baton<TestIntent>? = existingHandoff.claim()
        await Task.yield()

        // Push to already-top — should deliver to the existing waiter, not
        // register a new handoff, not duplicate the stack.
        await coordinator.dispatch(
            .push(route),
            on: coordinator.nav,
            stackHandoffs: coordinator.stackHandoffs,
            sheetHandoffs: coordinator.sheetHandoffs,
            baton: baton
        )

        let received = await waited
        #expect(received?.intent == baton.intent)
        #expect(coordinator.stackNav.path == [route])
        // Registry auto-cleans entries on `.delivered`. The cleanup happens via
        // a MainActor task scheduled by the handoff actor, so it may or may
        // not have landed by the time we check. The invariant we care about is
        // "the entry was never replaced by a fresh handoff" — so either nil
        // (cleaned) or the same instance (not yet cleaned) are both fine; a
        // *different* handoff would be a regression.
        let current = coordinator.stackHandoffs.handoff(for: route)
        #expect(current == nil || current === existingHandoff,
                "auto-clean may have removed the entry, but a fresh handoff must never replace it post-delivery")
    }
}

private struct TestIntent: Sendable, Equatable {
    let value: String
}

private enum TestEffect: Sendable, Equatable {
    case first, second, third
}

private enum TestFlow: NavigationFlow {
    typealias Intent = TestIntent
    typealias SideEffect = TestEffect

    static func operations(intent: TestIntent) -> [Step<Never, Never, TestEffect>] {
        [.effect(.first), .effect(.second), .effect(.third)]
    }
}

@MainActor
private final class TestCoordinator: RouteCoordinator {
    typealias Intent = TestIntent
    typealias Flow = TestFlow

    let linkSwitcher = LatestWinsExecutor(policy: .links)

    var capturedFlow: NavFlow?
    var appliedSteps: [TestEffect] = []
    var completion: CheckedContinuation<Void, Never>?

    func apply(_ effect: TestEffect, _ baton: Baton<TestIntent>) async {
        capturedFlow = NavFlow.current
        appliedSteps.append(effect)
        if effect == .third {
            completion?.resume()
            completion = nil
        }
    }
}

private enum TestRoute: Hashable, Sendable {
    case detail(id: Int)
}

private enum TestSheetRoute: Identifiable, Hashable, Sendable {
    case preview

    var id: String {
        switch self {
        case .preview: "preview"
        }
    }
}

private enum DispatchFlow: NavigationFlow {
    typealias Intent = TestIntent
    typealias Route = TestRoute
    typealias SheetRoute = TestSheetRoute

    static func operations(intent: TestIntent) -> [Step<TestRoute, TestSheetRoute, Never>] { [] }
}

@MainActor
private final class DispatchCoordinator: RouteCoordinator {
    typealias Intent = TestIntent
    typealias Flow = DispatchFlow

    let linkSwitcher = LatestWinsExecutor(policy: .links)
    let stackNav = GenericRouteNavigator<TestRoute>()
    let sheetNav = GenericSheetNavigator<TestSheetRoute>()
    let stackHandoffs = HandoffRegistry<TestRoute, TestIntent>()
    let sheetHandoffs = HandoffRegistry<TestSheetRoute, TestIntent>()

    var nav: NavigationFacade<TestRoute, TestSheetRoute> {
        NavigationFacade(route: stackNav, sheet: sheetNav)
    }

    func apply(_ effect: Never, _ baton: Baton<TestIntent>) async {}
}

private extension GenericRouteNavigator where R == TestRoute {
    var path: [TestRoute] { routeStack.routes }
}

// MARK: - Plumbed regression fixture

private enum PlumbedIntent: Sendable, Equatable {
    case openDetail(id: Int)
    case openPreviewSheet
}

private enum PlumbedRoute: Hashable, Sendable {
    case detail(id: Int)
}

private enum PlumbedSheet: Identifiable, Hashable, Sendable {
    case preview

    var id: String {
        switch self {
        case .preview: "preview"
        }
    }
}

private enum PlumbedFlow: NavigationFlow {
    typealias Intent = PlumbedIntent
    typealias Route = PlumbedRoute
    typealias SheetRoute = PlumbedSheet
    typealias SideEffect = Never

    static func operations(intent: PlumbedIntent) -> [Step<PlumbedRoute, PlumbedSheet, Never>] {
        switch intent {
        case .openDetail(let id):
            return [.nav(.push(.detail(id: id)))]
        case .openPreviewSheet:
            return [.nav(.present(.preview))]
        }
    }
}

@MainActor
private final class PlumbedTestCoordinator: PlumbedCoordinatorBase<PlumbedFlow> {}
