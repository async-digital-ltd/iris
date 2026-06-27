// Copyright 2026 Async Digital Ltd. All rights reserved.

import Foundation

public extension Task where Success == Never, Failure == Never {
    /// Sleeps for ``MainRunLoopTick/duration`` so SwiftUI commits a pending
    /// view-hierarchy transition (e.g. a `NavigationStack` push or `.sheet`
    /// presentation) before execution continues.
    ///
    /// Despite the name, this is a `Task.sleep`, not a `Task.yield()`.
    /// `Task.yield()` may stay in the same main-actor turn — SwiftUI applies
    /// navigation changes asynchronously, so we need a real suspension that
    /// reliably pushes execution to the next iteration. The duration lives on
    /// ``MainRunLoopTick`` as a single source of truth.
    ///
    /// - SeeAlso: ``MainRunLoopTick/duration``.
    static func waitOneTick() async {
        try? await Task.sleep(for: MainRunLoopTick.duration)
    }
}

/// Duration of one "main run-loop tick" pause used by `Task.waitOneTick()`.
///
/// Centralised so the chosen duration is auditable in one place rather than
/// scattered across navigator/coordinator call sites. The 1ms default works on
/// every device tested so far; revisit if a transaction-completion-signal
/// alternative is investigated later.
public enum MainRunLoopTick {
    public static let duration: Duration = .milliseconds(1)
}
