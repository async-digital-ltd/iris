// Copyright 2026 Async Digital Ltd. All rights reserved.

import SwiftUI

/// Claims a link baton from a handoff exactly once per handoff identity.
private struct OnLinkModifier<Intent: Sendable & Equatable>: ViewModifier {
    let handoff: Handoff<Intent>
    let consume: @MainActor (Baton<Intent>) async -> Void

    func body(content: Content) -> some View {
        content
            .task(id: ObjectIdentifier(handoff)) {
                if let baton = await handoff.claim() {
                    await consume(baton)
                }
            }
    }
}

public extension View {
    /// Claims a baton from the handoff exactly once and invokes `consume`.
    ///
    /// - Parameters:
    ///   - handoff: The handoff to claim from.
    ///   - consume: Called with the baton if successfully claimed.
    func onLink<Intent: Sendable & Equatable>(
        from handoff: Handoff<Intent>,
        consume: @escaping @MainActor (Baton<Intent>) async -> Void
    ) -> some View {
        modifier(OnLinkModifier(handoff: handoff, consume: consume))
    }

    /// Optional-handoff variant. If `nil`, the view is returned unchanged.
    @ViewBuilder
    func onLink<Intent: Sendable & Equatable>(
        from handoff: Handoff<Intent>?,
        consume: @escaping @MainActor (Baton<Intent>) async -> Void
    ) -> some View {
        if let handoff {
            modifier(OnLinkModifier(handoff: handoff, consume: consume))
        } else {
            self
        }
    }
}
