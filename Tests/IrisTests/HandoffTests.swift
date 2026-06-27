// Copyright 2026 Async Digital Ltd. All rights reserved.

import Testing
@testable import Iris

struct HandoffTests {
    private func makeBaton(
        intent: String = "test",
        source: String = "unit-test"
    ) -> Baton<String> {
        Baton(
            intent: intent,
            flow: NavFlow(source: source)
        )
    }

    // MARK: - Deliver then claim (producer-first)

    @Test func deliverThenClaimReturnsBaton() async {
        let handoff = Handoff<String>()
        let baton = makeBaton()

        let delivered = await handoff.deliver(baton)
        #expect(!delivered) // buffered, no waiter

        let claimed = await handoff.claim()
        #expect(claimed == baton)
    }

    // MARK: - Claim then deliver (consumer-first)

    @Test func claimThenDeliverResumesSuspendedClaimer() async {
        let handoff = Handoff<String>()
        let baton = makeBaton()

        // Start a claimer that will suspend.
        async let claimedFuture = handoff.claim()

        // Allow the claim task to suspend.
        await Task.yield()

        let delivered = await handoff.deliver(baton)
        #expect(delivered) // resumed the waiter

        let claimed = await claimedFuture
        #expect(claimed == baton)
    }

    // MARK: - Single-delivery semantics

    @Test func secondClaimAfterDeliveryReturnsNil() async {
        let handoff = Handoff<String>()
        let baton = makeBaton()

        await handoff.deliver(baton)
        _ = await handoff.claim() // first claim succeeds

        let second = await handoff.claim()
        #expect(second == nil)
    }

    @Test func secondDeliverIsIgnored() async {
        let handoff = Handoff<String>()
        let first = makeBaton(intent: "first")
        let second = makeBaton(intent: "second")

        await handoff.deliver(first)
        let ignoredResult = await handoff.deliver(second)
        #expect(!ignoredResult) // ignored because already buffered

        let claimed = await handoff.claim()
        #expect(claimed?.intent == "first")
    }

    @Test func deliverAfterDeliveredStateIsIgnored() async {
        let handoff = Handoff<String>()
        let baton = makeBaton()

        await handoff.deliver(baton)
        _ = await handoff.claim() // transitions to .delivered

        let late = makeBaton(intent: "late")
        let result = await handoff.deliver(late)
        #expect(!result) // ignored
    }

    // MARK: - Claim on fresh handoff with no delivery returns via waiting

    @Test func claimWhenAlreadyWaitingReturnsNil() async {
        let handoff = Handoff<String>()

        // First claimer suspends.
        async let firstClaim = handoff.claim()

        await Task.yield()

        // Second claimer should get nil because one is already waiting.
        let secondClaim = await handoff.claim()
        #expect(secondClaim == nil)

        // Deliver to unblock the first claimer.
        let baton = makeBaton()
        await handoff.deliver(baton)

        let result = await firstClaim
        #expect(result == baton)
    }

    // MARK: - Cancellation

    @Test func cancellingSuspendedClaimReturnsNil() async {
        let handoff = Handoff<String>()

        let claimer = Task {
            await handoff.claim()
        }

        // Allow the claim to suspend in `.waiting`.
        await Task.yield()

        claimer.cancel()

        let result = await claimer.value
        #expect(result == nil)
    }

    @Test func claimOnAlreadyCancelledTaskReturnsNil() async {
        let handoff = Handoff<String>()

        let claimer = Task {
            // Yield first so the outer can cancel before claim runs.
            await Task.yield()
            return await handoff.claim()
        }

        claimer.cancel()

        let result = await claimer.value
        #expect(result == nil)
    }

    @Test func deliverAfterCancelledClaimIsIgnored() async {
        let handoff = Handoff<String>()

        let claimer = Task {
            await handoff.claim()
        }

        await Task.yield()
        claimer.cancel()
        _ = await claimer.value

        // Handoff is now spent; further deliveries are no-ops.
        let late = makeBaton(intent: "late")
        let delivered = await handoff.deliver(late)
        #expect(!delivered)

        let secondClaim = await handoff.claim()
        #expect(secondClaim == nil)
    }
}
