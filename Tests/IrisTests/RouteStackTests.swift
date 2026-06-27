// Copyright 2026 Async Digital Ltd. All rights reserved.

import Testing
@testable import Iris

struct RouteStackTests {
    // MARK: - Initial state

    @Test func newStackIsEmpty() {
        let stack = RouteStack<String>()
        #expect(stack.isEmpty)
        #expect(stack.currentRoute == nil)
        #expect(stack.routes.isEmpty)
    }

    // MARK: - Push

    @Test func pushAddsRouteToTop() {
        var stack = RouteStack<String>()
        stack.push("A")
        #expect(stack.currentRoute == "A")
        #expect(stack.routes == ["A"])
    }

    @Test func pushMultipleRoutesPreservesOrder() {
        var stack = RouteStack<String>()
        stack.push("A")
        stack.push("B")
        stack.push("C")
        #expect(stack.routes == ["A", "B", "C"])
        #expect(stack.currentRoute == "C")
    }

    // MARK: - PopLast

    @Test func popLastRemovesTopRoute() {
        var stack = RouteStack<String>()
        stack.push("A")
        stack.push("B")
        stack.popLast()
        #expect(stack.routes == ["A"])
        #expect(stack.currentRoute == "A")
    }

    @Test func popLastOnEmptyStackIsNoOp() {
        var stack = RouteStack<String>()
        stack.popLast()
        #expect(stack.isEmpty)
    }

    // MARK: - PopToRoot

    @Test func popToRootClearsStack() {
        var stack = RouteStack<String>()
        stack.push("A")
        stack.push("B")
        stack.popToRoot()
        #expect(stack.isEmpty)
        #expect(stack.currentRoute == nil)
    }

    // MARK: - PopTo(count:)

    @Test func popToCountRetainsFirstNRoutes() {
        var stack = RouteStack<String>()
        stack.push("A")
        stack.push("B")
        stack.push("C")
        let changed = stack.popTo(count: 1)
        #expect(changed)
        #expect(stack.routes == ["A"])
    }

    @Test func popToCountZeroClearsStack() {
        var stack = RouteStack<String>()
        stack.push("A")
        let changed = stack.popTo(count: 0)
        #expect(changed)
        #expect(stack.isEmpty)
    }

    @Test func popToCountNegativeClearsStack() {
        var stack = RouteStack<String>()
        stack.push("A")
        let changed = stack.popTo(count: -5)
        #expect(changed)
        #expect(stack.isEmpty)
    }

    @Test func popToCountGreaterThanSizeLeavesUnchanged() {
        var stack = RouteStack<String>()
        stack.push("A")
        let changed = stack.popTo(count: 10)
        #expect(!changed)
        #expect(stack.routes == ["A"])
    }

    @Test func popToCountEqualToSizeLeavesUnchanged() {
        var stack = RouteStack<String>()
        stack.push("A")
        stack.push("B")
        let changed = stack.popTo(count: 2)
        #expect(!changed)
        #expect(stack.routes == ["A", "B"])
    }

    @Test func popToCountZeroOnEmptyReturnsFalse() {
        var stack = RouteStack<String>()
        let changed = stack.popTo(count: 0)
        #expect(!changed)
    }

    // MARK: - ReplaceTop

    @Test func replaceTopSwapsTopRoute() {
        var stack = RouteStack<String>()
        stack.push("A")
        stack.push("B")
        stack.replaceTop(with: "Z")
        #expect(stack.routes == ["A", "Z"])
    }

    @Test func replaceTopOnEmptyStackPushes() {
        var stack = RouteStack<String>()
        stack.replaceTop(with: "X")
        #expect(stack.routes == ["X"])
    }

    // MARK: - Reset

    @Test func resetReplacesEntireStack() {
        var stack = RouteStack<String>()
        stack.push("A")
        stack.reset(to: ["X", "Y", "Z"])
        #expect(stack.routes == ["X", "Y", "Z"])
        #expect(stack.currentRoute == "Z")
    }

    @Test func resetToEmptyArrayClearsStack() {
        var stack = RouteStack<String>()
        stack.push("A")
        stack.reset(to: [])
        #expect(stack.isEmpty)
    }

    // MARK: - PushIfNeeded

    @Test func pushIfNeededSkipsDuplicateTop() {
        var stack = RouteStack<String>()
        stack.push("A")
        stack.pushIfNeeded("A")
        #expect(stack.routes == ["A"])
    }

    @Test func pushIfNeededPushesDifferentRoute() {
        var stack = RouteStack<String>()
        stack.push("A")
        stack.pushIfNeeded("B")
        #expect(stack.routes == ["A", "B"])
    }

    @Test func pushIfNeededPushesOntoEmptyStack() {
        var stack = RouteStack<String>()
        stack.pushIfNeeded("A")
        #expect(stack.routes == ["A"])
    }

    // MARK: - EnsureTop

    @Test func ensureTopPushesMissingRoute() {
        var stack = RouteStack<String>()
        stack.push("A")
        stack.ensureTop("B")
        #expect(stack.routes == ["A", "B"])
    }

    @Test func ensureTopReplacesMatchingTop() {
        var stack = RouteStack<String>()
        stack.push("A")
        stack.ensureTop("A")
        #expect(stack.routes == ["A"])
        #expect(stack.currentRoute == "A")
    }

    @Test func ensureTopPushesOntoEmptyStack() {
        var stack = RouteStack<String>()
        stack.ensureTop("X")
        #expect(stack.routes == ["X"])
    }

    @Test func isEmptyReflectsState() {
        var stack = RouteStack<String>()
        #expect(stack.isEmpty)
        stack.push("A")
        #expect(!stack.isEmpty)
        stack.popLast()
        #expect(stack.isEmpty)
    }
}
