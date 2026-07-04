// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

import Foundation

/// Converts link URLs into strongly-typed intent values.
///
/// Implementations should handle malformed URLs gracefully, typically by
/// returning a default or fallback intent.
public protocol URLParsing: Sendable {
    associatedtype Intent: Sendable & Equatable

    /// Parses a link URL into an intent.
    func parse(_ url: URL) -> Intent
}
