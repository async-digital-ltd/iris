// Copyright 2026 Async Digital Ltd. All rights reserved.

import SwiftUI

/// Consumes values from a lazily-created `AsyncStream`, cancelling when the
/// view disappears.
private struct OnEvents<Value>: ViewModifier {
    let makeStream: () async -> AsyncStream<Value>
    let consume: @MainActor (Value) async -> Void

    func body(content: Content) -> some View {
        content.task {
            for await value in await makeStream() {
                await consume(value)
            }
        }
    }
}

public extension View {
    /// Listens to a lazily-created `AsyncStream` and runs `consume` for every event.
    ///
    /// The handler runs serially in arrival order. The stream is cancelled when
    /// the view disappears: SwiftUI tears down `.task`, which exits the
    /// `for await` loop and fires the stream's termination handler. Subscriptions
    /// against an upstream actor (e.g. ``Broadcaster``) are released at
    /// that point; mounting `N` views creates `N` subscriptions until they
    /// disappear.
    func onEvents<Value>(
        from makeStream: @escaping () async -> AsyncStream<Value>,
        consume: @escaping @MainActor (Value) async -> Void
    ) -> some View {
        modifier(OnEvents(makeStream: makeStream, consume: consume))
    }
}
