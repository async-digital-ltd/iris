// Copyright 2026 Async Digital Ltd. All rights reserved.

import Testing
@testable import Iris

@MainActor
struct LatestWinsExecutorTests {
    @Test func runInvokesOperation() async {
        let executor = LatestWinsExecutor(policy: .fireAndForgetCancel)
        let outcome = Outcome()

        executor.run { await outcome.markReached() }

        // Give the operation time to complete.
        try? await Task.sleep(for: .milliseconds(50))

        let reached = await outcome.reached
        #expect(reached == true)
    }

    @Test func fireAndForgetCancelInterruptsPreviousOperation() async {
        let executor = LatestWinsExecutor(policy: .fireAndForgetCancel)
        let outcome = Outcome()

        // First operation sleeps for 300ms then marks reached (unless cancelled).
        executor.run {
            try? await Task.sleep(for: .milliseconds(300))
            // After cancellation, Task.sleep throws and is swallowed by try?,
            // but Task.isCancelled is true, so we know the cancel propagated.
            if !Task.isCancelled {
                await outcome.markReached()
            }
        }

        // Let the first task enter its sleep.
        try? await Task.sleep(for: .milliseconds(50))

        // Replace: should propagate cancellation into the first operation.
        executor.run {}

        // Wait well past when the first sleep would have completed naturally.
        try? await Task.sleep(for: .milliseconds(500))

        let reached = await outcome.reached
        #expect(reached == false)
    }

    @Test func onReplaceFiresWithHadPreviousFalseOnFirstRun() async {
        let log = HookLog()
        let executor = LatestWinsExecutor(
            policy: .fireAndForgetCancel,
            hooks: .init(onReplace: { hadPrevious in
                Task { await log.record(hadPrevious: hadPrevious) }
            })
        )

        executor.run {}
        try? await Task.sleep(for: .milliseconds(50))

        let events = await log.events
        #expect(events == [false])
    }

    @Test func onReplaceFiresWithHadPreviousTrueOnSecondRun() async {
        let log = HookLog()
        let executor = LatestWinsExecutor(
            policy: .fireAndForgetCancel,
            hooks: .init(onReplace: { hadPrevious in
                Task { await log.record(hadPrevious: hadPrevious) }
            })
        )

        executor.run { try? await Task.sleep(for: .milliseconds(300)) }
        try? await Task.sleep(for: .milliseconds(50))
        executor.run {}
        try? await Task.sleep(for: .milliseconds(50))

        let events = await log.events
        #expect(events == [false, true])
    }

    @Test func cancelCurrentInterruptsInflightOperation() async {
        let executor = LatestWinsExecutor(policy: .fireAndForgetCancel)
        let outcome = Outcome()

        executor.run {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled {
                await outcome.markReached()
            }
        }

        try? await Task.sleep(for: .milliseconds(50))
        executor.cancelCurrent()
        try? await Task.sleep(for: .milliseconds(500))

        let reached = await outcome.reached
        #expect(reached == false)
    }
}

private actor Outcome {
    var reached = false
    func markReached() { reached = true }
}

private actor HookLog {
    var events: [Bool] = []
    func record(hadPrevious: Bool) { events.append(hadPrevious) }
}
