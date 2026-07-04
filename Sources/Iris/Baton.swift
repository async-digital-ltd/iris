// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

import Foundation

/// A single link intent carrier passed down a workflow.
///
/// Carries both the intent and the ``NavFlow`` correlation context so that
/// every step in the navigation chain can be traced end-to-end.
///
/// Identity semantics: `Equatable` and `Hashable` are **by `id` only**. Two
/// batons with identical `intent` and `flow` compare unequal because each
/// `init` generates a fresh `id`; a baton is a one-shot event reference,
/// not a value. Use ``intent`` and ``flow`` directly if you need to compare
/// payloads.
public struct Baton<Intent: Sendable & Equatable>: Sendable, Equatable, Identifiable, Hashable, CustomDebugStringConvertible {
    public let id = UUID()
    public let intent: Intent
    public let flow: NavFlow

    public init(intent: Intent, flow: NavFlow) {
        self.intent = intent
        self.flow = flow
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public var debugDescription: String {
        "Baton(id:\(id.uuidString), intent:\(String(reflecting: intent)))"
    }
}

/// A one-shot handoff coordinator that delivers a single ``Baton`` to
/// exactly one consumer.
///
/// Supports two patterns:
/// - **Producer-first**: `deliver(_:)` buffers until a consumer calls `claim()`.
/// - **Consumer-first**: `claim()` suspends until a producer calls `deliver(_:)`.
///
/// Create a new instance per incoming link to keep workflows independent.
public actor Handoff<Intent: Sendable & Equatable> {
    private enum State: CustomDebugStringConvertible {
        case initial
        case waiting(CheckedContinuation<Baton<Intent>?, Never>)
        case buffered(Baton<Intent>)
        case delivered

        var debugDescription: String {
            switch self {
            case .initial:
                return "initial"
            case .waiting:
                return "waiting"
            case .buffered:
                return "buffered"
            case .delivered:
                return "delivered"
            }
        }
    }

    private var state: State = .initial

    /// Called exactly once, when the handoff first transitions to `.delivered`,
    /// from any path (waiter resumed, buffered baton claimed, waiter
    /// cancelled). Set by ``HandoffRegistry`` so the registry can auto-clean
    /// the entry. The closure receives an ``ObjectIdentifier`` so the
    /// registry can compare identity before removing (a fresh registration
    /// for the same route may have replaced the entry while the callback
    /// dispatched). `ObjectIdentifier` is `Sendable`; passing the actor
    /// reference itself would risk a cross-isolation send.
    private let onDelivered: (@Sendable (ObjectIdentifier) -> Void)?

    /// Public init; instances created this way have no auto-clean callback.
    public init() {
        self.onDelivered = nil
    }

    /// Internal init used by ``HandoffRegistry`` to wire auto-clean on
    /// delivery.
    init(onDelivered: @escaping @Sendable (ObjectIdentifier) -> Void) {
        self.onDelivered = onDelivered
    }

    private func fireOnDeliveredOnce() {
        guard let onDelivered else { return }
        onDelivered(ObjectIdentifier(self))
    }

    // MARK: Posting

    /// Post the baton exactly once.
    ///
    /// - If no consumer is waiting, the baton is buffered.
    /// - If a consumer is already waiting, it is resumed immediately.
    /// - If already posted or delivered, the call is ignored.
    ///
    /// - Returns: `true` if a consumer received the baton immediately.
    @discardableResult
    public func deliver(_ baton: Baton<Intent>) -> Bool {
        switch state {
        case .initial:
            state = .buffered(baton)
            return false

        case .waiting(let cont):
            state = .delivered
            cont.resume(returning: baton)
            fireOnDeliveredOnce()
            return true

        case .buffered, .delivered:
            return false
        }
    }

    // MARK: Claiming

    /// Claim the baton once; suspends until available if not yet posted.
    ///
    /// If the awaiting task is cancelled while suspended, the handoff transitions
    /// to `.delivered` and the call returns `nil`. Subsequent ``deliver(_:)`` calls
    /// are no-ops; handoffs are one-shot.
    ///
    /// - Returns: The baton if this caller is the sole claimant; otherwise `nil`.
    public func claim() async -> Baton<Intent>? {
        switch state {
        case .buffered(let baton):
            state = .delivered
            fireOnDeliveredOnce()
            return baton

        case .initial:
            return await withTaskCancellationHandler {
                await withCheckedContinuation { (cont: CheckedContinuation<Baton<Intent>?, Never>) in
                    if Task.isCancelled {
                        state = .delivered
                        fireOnDeliveredOnce()
                        cont.resume(returning: nil)
                    } else {
                        state = .waiting(cont)
                    }
                }
            } onCancel: {
                Task { @concurrent in await self.cancelWaiter() }
            }

        case .waiting, .delivered:
            return nil
        }
    }

    private func cancelWaiter() {
        switch state {
        case .waiting(let cont):
            state = .delivered
            cont.resume(returning: nil)
            fireOnDeliveredOnce()
        case .initial:
            state = .delivered
            fireOnDeliveredOnce()
        case .buffered, .delivered:
            break
        }
    }
}

/// Multicast broadcaster for URL-based links.
///
/// Parses URLs into intents via a ``URLParsing`` codec, wraps them in
/// ``Baton`` values, and multicasts to all active subscribers. New
/// subscribers receive the last baton by default (replay-last).
public actor Broadcaster<URLCodec: URLParsing> {
    private var subs: [UUID: AsyncStream<Baton<URLCodec.Intent>>.Continuation] = [:]
    private var last: Baton<URLCodec.Intent>?
    private let urlCodec: URLCodec

    public init(urlCodec: URLCodec) {
        self.urlCodec = urlCodec
    }

    /// Create a new subscription stream.
    ///
    /// - Parameter replayLast: If `true` (default), the last baton is
    ///   immediately yielded to the new subscriber.
    public func makeStream(replayLast: Bool = true) -> AsyncStream<Baton<URLCodec.Intent>> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            subs[id] = continuation
            if replayLast, let last { continuation.yield(last) }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id: id) }
            }
        }
    }

    private func removeSubscriber(id: UUID) {
        subs.removeValue(forKey: id)
    }

    /// Parse a URL and broadcast the resulting baton to all subscribers.
    ///
    /// - Parameters:
    ///   - url: The link URL to parse.
    ///   - flow: The navigation flow context for this routing session.
    /// - Returns: The baton that was broadcast.
    @discardableResult
    public func handle(url: URL, flow: NavFlow) -> Baton<URLCodec.Intent> {
        let intent = urlCodec.parse(url)
        let baton = Baton(intent: intent, flow: flow)
        send(baton)
        return baton
    }

    private func send(_ baton: Baton<URLCodec.Intent>) {
        last = baton
        for continuation in subs.values { continuation.yield(baton) }
    }
}
