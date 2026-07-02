// Copyright 2026 Async Digital Ltd. All rights reserved.

import Testing
@testable import Iris

@MainActor
struct NavFlowScopeTests {
    @Test func currentDefaultsToFreshTapOutsideAnyScope() {
        // Outside any `withScope`, every read of `current` returns a fresh
        // tap-sourced flow so navigator calls at tap sites get a real,
        // correlatable id without an explicit wrap.
        let first = NavFlow.current
        let second = NavFlow.current
        #expect(first.source == "tap")
        #expect(second.source == "tap")
        #expect(first.id != second.id, "each read outside a scope must produce a fresh id")
    }

    @Test func withScopeBindsCurrent() {
        let flow = NavFlow(source: "link")

        NavFlow.withScope(flow) {
            #expect(NavFlow.current == flow)
            #expect(NavFlow.current.source == "link")
        }
    }

    @Test func withScopeAsyncBindsCurrent() async {
        let flow = NavFlow(source: "link-async")

        await NavFlow.withScope(flow) {
            await Task.yield()
            #expect(NavFlow.current == flow)
        }
    }

    @Test func currentRevertsToFreshTapAfterScopeExit() {
        let flow = NavFlow(source: "transient")

        NavFlow.withScope(flow) {
            #expect(NavFlow.current == flow)
        }
        // After exit, no scope is bound: `current` returns a fresh tap flow
        // (not the previously-bound flow, not a stable sentinel).
        let after = NavFlow.current
        #expect(after.source == "tap")
        #expect(after != flow)
    }

    @Test func nestedScopesOverrideAndRestore() {
        let outer = NavFlow(source: "outer")
        let inner = NavFlow(source: "inner")

        NavFlow.withScope(outer) {
            #expect(NavFlow.current == outer)
            NavFlow.withScope(inner) {
                #expect(NavFlow.current == inner)
            }
            #expect(NavFlow.current == outer)
        }
    }

    @Test func withScopeReturnsBodyValue() {
        let flow = NavFlow(source: "compute")

        let result = NavFlow.withScope(flow) {
            NavFlow.current.id
        }
        #expect(result == flow.id)
    }

    @Test func tapBindsCurrentWithTapSource() {
        NavFlow.tap {
            #expect(NavFlow.current.source == "tap")
        }
    }

    @Test func tapGivesFreshIdPerInvocation() {
        let first = NavFlow.tap { NavFlow.current.id }
        let second = NavFlow.tap { NavFlow.current.id }
        #expect(first != second)
    }
}

@MainActor
struct NavigatorAmbientFlowTests {
    @Test func defaultParameterPicksUpAmbientFlow() {
        let navigator = FlowCapturingRouteNavigator()
        let flow = NavFlow(source: "link-test")

        NavFlow.withScope(flow) {
            navigator.push("home")
        }

        #expect(navigator.capturedFlows.count == 1)
        #expect(navigator.capturedFlows.first == flow)
    }

    @Test func explicitFlowOverridesAmbient() {
        let navigator = FlowCapturingRouteNavigator()
        let ambient = NavFlow(source: "ambient")
        let explicit = NavFlow(source: "explicit")

        NavFlow.withScope(ambient) {
            navigator.push("home", explicit)
        }

        #expect(navigator.capturedFlows.first == explicit)
    }

    @Test func defaultParameterOutsideScopeIsFreshTap() {
        let navigator = FlowCapturingRouteNavigator()

        navigator.push("home")
        navigator.push("settings")

        #expect(navigator.capturedFlows.count == 2)
        #expect(navigator.capturedFlows[0].source == "tap")
        #expect(navigator.capturedFlows[1].source == "tap")
        #expect(navigator.capturedFlows[0].id != navigator.capturedFlows[1].id,
                "each tap-site call outside a scope must get a fresh flow id")
    }
}

@MainActor
private final class FlowCapturingRouteNavigator {
    var capturedFlows: [NavFlow] = []

    func push(_ route: String, _ flow: NavFlow = .current) {
        capturedFlows.append(flow)
    }
}
