// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

import Foundation

/// Ensures only the most recent task executes, cancelling any in-flight
/// predecessor.
///
/// Supports two policies via ``LatestTaskPolicy``:
/// - ``LatestTaskPolicy/fireAndForgetCancel``: immediately cancels and replaces.
/// - ``LatestTaskPolicy/waitForDrain(timeout:)``: waits for the previous task
///   to finish (with optional timeout) before starting the new one.
@MainActor
public final class LatestWinsExecutor {
    /// Callbacks for observing task replacement and drain timeouts.
    public struct Hooks: Sendable {
        /// Called when a new task replaces an existing one.
        let onReplace: (@Sendable (_ hadPrevious: Bool) -> Void)?

        /// Called when the drain timeout expires before the previous task finishes.
        let onTimeout: (@Sendable () -> Void)?

        public init(
            onReplace: (@Sendable (_ hadPrevious: Bool) -> Void)? = nil,
            onTimeout: (@Sendable () -> Void)? = nil
        ) {
            self.onReplace = onReplace
            self.onTimeout = onTimeout
        }
    }

    private var current: Task<Void, Never>?
    private var currentID: UInt64 = 0
    private let policy: LatestTaskPolicy
    private let hooks: Hooks

    public init(
        policy: LatestTaskPolicy,
        hooks: Hooks = .init()
    ) {
        self.policy = policy
        self.hooks = hooks
    }

    /// Executes an operation, cancelling any previous one in progress.
    ///
    /// `current` holds the work task directly (not a bridge wrapper), so
    /// `previous?.cancel()` propagates into `operation()`'s `await` points,
    /// which is what the "latest wins" name implies. Earlier implementations cancelled
    /// a bridge that *awaited* the work task, leaving the work task running.
    public func run(
        _ operation: @Sendable @escaping () async -> Void
    ) {
        let previous = current
        previous?.cancel()
        hooks.onReplace?(previous != nil)

        currentID &+= 1
        let myID = currentID

        let work = Task<Void, Never> { [policy, hooks, weak self] in
            if case .waitForDrain(let timeout) = policy {
                let drained = await waitForDrain(of: previous, timeout: timeout)
                if !drained { hooks.onTimeout?() }
            }
            if !Task.isCancelled {
                await operation()
            }
            await self?.finishIfLatest(id: myID)
        }

        current = work
    }

    /// Clears `current` only if this task is still the latest.
    private func finishIfLatest(id: UInt64) {
        if currentID == id {
            current = nil
        }
    }

    /// Cancels the current task without replacing it.
    public func cancelCurrent() {
        current?.cancel()
        current = nil
    }

    /// Whether a task is currently in progress.
    public func isBusy() -> Bool {
        current != nil
    }

    deinit {
        current?.cancel()
        current = nil
    }
}

// MARK: - Drain helper

/// Waits for a task to complete, with optional timeout.
///
/// - Returns: `true` if the task completed (or was `nil`), `false` on timeout.
private func waitForDrain(
    of task: Task<Void, Never>?,
    timeout: DrainTimeout
) async -> Bool {
    guard let task else { return true }

    switch timeout {
    case .never:
        if task.isCancelled { return true }
        await task.value
        return true

    case .finite(let duration):
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { await task.value; return true }
            group.addTask { try? await Task.sleep(for: duration); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}

/// How a ``LatestWinsExecutor`` handles the transition between tasks.
public enum LatestTaskPolicy: Sendable {
    /// Waits for the previous task to finish (or timeout) before starting the new one.
    case waitForDrain(timeout: DrainTimeout)

    /// Immediately cancels the previous task and starts the new one.
    case fireAndForgetCancel
}

public extension LatestTaskPolicy {
    /// Waits up to 250ms for the previous navigation to complete.
    static var links: LatestTaskPolicy { .waitForDrain(timeout: .finite(.milliseconds(250))) }

    /// Immediately cancels previous operations for instant UI feedback.
    static var ui: LatestTaskPolicy { .fireAndForgetCancel }
}

/// How long to wait for a task to drain before starting a new one.
public enum DrainTimeout: Sendable, Equatable {
    /// Wait up to the given duration.
    case finite(Duration)

    /// Wait indefinitely.
    ///
    /// - Warning: Can hang if the previous task never completes.
    case never
}
