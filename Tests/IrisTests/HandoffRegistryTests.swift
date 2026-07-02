// Copyright 2026 Async Digital Ltd. All rights reserved.

import Testing
@testable import Iris

@MainActor
struct HandoffRegistryTests {
    private enum Route: Hashable {
        case inbox
        case badges
        case detail(Int)
    }

    // MARK: - Register and retrieve

    @Test func registerCreatesHandoff() {
        let registry = HandoffRegistry<Route, String>()
        let retrieved = registry.register(for: .inbox)
        #expect(registry.handoff(for: .inbox) === retrieved)
    }

    @Test func handoffReturnsRegisteredInstance() {
        let registry = HandoffRegistry<Route, String>()
        let registered = registry.register(for: .badges)
        let retrieved = registry.handoff(for: .badges)
        #expect(retrieved === registered)
    }

    @Test func handoffForUnregisteredRouteReturnsNil() {
        let registry = HandoffRegistry<Route, String>()
        let result = registry.handoff(for: .inbox)
        #expect(result == nil)
    }

    // MARK: - Replace on re-register

    @Test func registerReplacesExistingHandoff() {
        let registry = HandoffRegistry<Route, String>()
        let first = registry.register(for: .inbox)
        let second = registry.register(for: .inbox)
        #expect(first !== second)

        let current = registry.handoff(for: .inbox)
        #expect(current === second)
    }

    // MARK: - Auto-clean on delivered

    @Test func autoCleanRemovesEntryAfterDeliverResumesWaiter() async {
        let registry = HandoffRegistry<Route, String>()
        let handoff = registry.register(for: .inbox)

        // Suspend a claimant, then deliver: claimant resumes, registry should
        // auto-clean. Auto-clean dispatches via a Task to MainActor; await it.
        async let waited: Baton<String>? = handoff.claim()
        await Task.yield()
        await handoff.deliver(Baton(intent: "msg", flow: NavFlow(source: "test")))
        _ = await waited
        await waitForAutoClean()

        #expect(registry.handoff(for: .inbox) == nil)
    }

    @Test func autoCleanRemovesEntryAfterBufferedBatonClaimed() async {
        let registry = HandoffRegistry<Route, String>()
        let handoff = registry.register(for: .inbox)

        // Producer-first: deliver buffers, then claim drains and transitions
        // to .delivered → auto-clean fires.
        await handoff.deliver(Baton(intent: "msg", flow: NavFlow(source: "test")))
        _ = await handoff.claim()
        await waitForAutoClean()

        #expect(registry.handoff(for: .inbox) == nil)
    }

    @Test func autoCleanDoesNotRemoveFreshRegistrationForSameRoute() async {
        let registry = HandoffRegistry<Route, String>()
        let first = registry.register(for: .inbox)

        // Deliver the first: schedules auto-clean. Re-register before the
        // clean lands; the identity check must prevent the clean from
        // removing the FRESH handoff.
        async let waitedFirst: Baton<String>? = first.claim()
        await Task.yield()
        await first.deliver(Baton(intent: "msg", flow: NavFlow(source: "test")))
        _ = await waitedFirst

        let second = registry.register(for: .inbox)
        await waitForAutoClean()

        #expect(registry.handoff(for: .inbox) === second,
                "fresh registration must survive the prior handoff's auto-clean")
    }

    // Waits one MainActor turn for the auto-clean Task scheduled from the
    // handoff actor to land.
    private func waitForAutoClean() async {
        for _ in 0..<5 { await Task.yield() }
    }

    // MARK: - Multiple routes are independent

    @Test func differentRoutesHaveIndependentHandoffs() {
        let registry = HandoffRegistry<Route, String>()
        let inboxHandoff = registry.register(for: .inbox)
        let badgesHandoff = registry.register(for: .badges)
        #expect(inboxHandoff !== badgesHandoff)
        #expect(registry.handoff(for: .inbox) === inboxHandoff)
        #expect(registry.handoff(for: .badges) === badgesHandoff)
    }
}
