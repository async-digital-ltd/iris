// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

import Foundation
import os

/// A correlation identifier that ties together every step of a single navigation
/// event -- from URL parse (or button tap) through to final screen presentation.
///
/// A link can trigger actions spanning multiple coordinators and intent-type
/// boundaries. `NavFlow` gives each event a stable identity so that `#if DEBUG`
/// log lines printing `[FLOW <id>]` can be grepped end-to-end.
///
/// `NavFlow` does **not** propagate cancellation. Cancellation is handled by
/// Swift's cooperative task tree via ``LatestWinsExecutor``. `NavFlow`'s role
/// is purely observational -- it identifies *which* event was cancelled.
///
/// A `NavFlow` is created once per originating event, stored inside a
/// ``Baton``, and carried forward unchanged across the flow.
public struct NavFlow: Sendable, Equatable {
    /// Unique identifier for this navigation event.
    public let id: UUID

    /// Human-readable label for the event origin (e.g. `"link"`, `"tap"`).
    public let source: String

    public init(
        id: UUID = UUID(),
        source: String
    ) {
        self.id = id
        self.source = source
    }
}

extension NavFlow {
    /// Internal TaskLocal backing for ``current``. The bound value is what
    /// ``withScope(_:_:)`` sets; outside any scope it carries the
    /// ``unboundSentinel`` value, which the public ``current`` translates to
    /// a fresh tap flow per read.
    @TaskLocal static var scopedCurrentStorage: NavFlow = .unboundSentinel

    /// Internal sentinel marking "no scope is currently bound." Used as the
    /// `@TaskLocal` default for ``scopedCurrentStorage``; reads of ``current``
    /// translate this to a fresh tap flow rather than surfacing the sentinel.
    static let unboundSentinel = NavFlow(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        source: "_unbound_"
    )

    /// The ambient `NavFlow` for the current task.
    ///
    /// Inside ``withScope(_:_:)`` returns the bound flow. Outside any scope
    /// returns a *fresh* `NavFlow(source: "tap")` per read, so navigator calls
    /// at tap sites get a correlatable flow id without an explicit
    /// ``NavFlow/tap(_:)`` wrap. Multi-call sequences that need to share a
    /// single flow id should still wrap in ``withScope(_:_:)`` or
    /// ``tap(_:)-(_)`` so every read returns the same value.
    public static var current: NavFlow {
        let bound = scopedCurrentStorage
        return bound == .unboundSentinel ? NavFlow(source: "tap") : bound
    }

    /// Runs `body` with ``current`` bound to `flow`.
    ///
    /// Use at link entry points so navigator calls inside `body` can omit
    /// the explicit `flow:` argument and pick up the ambient value. The async
    /// overload inherits the caller's actor isolation, so `body` can stay on
    /// `@MainActor` (or any other actor) without an extra hop.
    ///
    /// - Parameters:
    ///   - flow: The flow to bind for the duration of `body`.
    ///   - isolation: Caller isolation, inherited via `#isolation`.
    ///   - body: The asynchronous work to run within the scope.
    public static func withScope<R>(
        _ flow: NavFlow,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> R
    ) async rethrows -> R {
        try await $scopedCurrentStorage.withValue(
            flow,
            operation: body,
            isolation: isolation
        )
    }

    /// Synchronous variant of ``withScope(_:isolation:_:)``.
    public static func withScope<R>(
        _ flow: NavFlow,
        _ body: () throws -> R
    ) rethrows -> R {
        try $scopedCurrentStorage.withValue(flow, operation: body)
    }

    /// Runs `body` within a fresh `NavFlow` whose `source` is `"tap"`.
    ///
    /// Sugar for `withScope(NavFlow(source: "tap")) { … }`. Use when multiple
    /// navigator calls inside the closure should share a single flow id for
    /// log correlation. For a single navigator call, the wrap is no longer
    /// needed: ``current`` already returns a fresh tap flow outside any
    /// scope.
    @discardableResult
    public static func tap<R>(_ body: () throws -> R) rethrows -> R {
        try withScope(NavFlow(source: "tap"), body)
    }

    /// Asynchronous variant of ``tap(_:)``.
    @discardableResult
    public static func tap<R>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> R
    ) async rethrows -> R {
        try await withScope(NavFlow(source: "tap"), isolation: isolation, body)
    }
}
