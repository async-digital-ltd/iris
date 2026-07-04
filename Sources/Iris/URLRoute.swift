// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

import Foundation

/// A single URL ↔ intent rule, co-locating parse and emit for one URL shape.
///
/// Both directions live in the same value so the parse/emit pair can't drift
/// apart silently. ``URLPathRouter`` walks an ordered list of routes for both
/// directions: parse takes the first match; emit takes the first non-nil.
///
/// ```swift
/// URLRoute<Intent>(
///     "conversation/:id",
///     parse: { c in .openConversation(.init(rawValue: c["id"]!)) },
///     emit: { intent in
///         if case .openConversation(let id) = intent {
///             return URLEmission(id.rawValue)
///         }
///         return nil
///     }
/// )
/// ```
///
/// `URLEmission` carries only the path segments AFTER the host, because
/// ``URLPathRouter`` already knows the host from the pattern. For
/// `"conversation/:id"`, `URLEmission(id.rawValue)` produces
/// `myapp://conversation/<id>`, not `myapp://conversation/conversation/<id>`.
public struct URLRoute<Intent: Sendable & Equatable>: Sendable {
    public let pattern: URLPattern
    public let parse: @Sendable (URLCaptures) -> Intent?
    public let emit: @Sendable (Intent) -> URLEmission?

    /// Pattern grammar:
    /// - `host/seg1/seg2`: host is the first segment; following segments are
    ///   literals.
    /// - `host/:name`: `:name` is a named capture available via ``URLCaptures``.
    /// - `host?q&r`: query parameter names; values surface in `URLCaptures`
    ///   under those names. All query captures are optional from the matcher's
    ///   perspective: absence means the entry is missing from `URLCaptures`.
    /// - `host`: bare host with no path or query.
    ///
    /// Examples:
    /// - `"conversation/:id"`
    /// - `"conversation/:cid/message/:mid"`
    /// - `"settings"`
    /// - `"search?q"`
    public init(
        _ pattern: String,
        parse: @escaping @Sendable (URLCaptures) -> Intent?,
        emit: @escaping @Sendable (Intent) -> URLEmission?
    ) {
        self.pattern = URLPattern(pattern)
        self.parse = parse
        self.emit = emit
    }
}

/// Parsed pattern from ``URLRoute``'s pattern-string init.
public struct URLPattern: Sendable {
    public enum PathSegment: Sendable, Equatable {
        case literal(String)
        case capture(String)
    }

    public let host: String
    public let path: [PathSegment]
    public let captureQueryNames: [String]

    public init(_ pattern: String) {
        let (pathPart, queryNames) = Self.splitQuery(pattern)
        let segments = pathPart.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        self.host = segments.first ?? ""
        self.path = segments.dropFirst().map { segment in
            if segment.hasPrefix(":") {
                return .capture(String(segment.dropFirst()))
            } else {
                return .literal(segment)
            }
        }
        self.captureQueryNames = queryNames
    }

    private static func splitQuery(_ pattern: String) -> (path: String, queries: [String]) {
        guard let queryStart = pattern.firstIndex(of: "?") else {
            return (pattern, [])
        }
        let path = String(pattern[..<queryStart])
        let query = String(pattern[pattern.index(after: queryStart)...])
        let names = query.split(separator: "&").map { item -> String in
            if let eq = item.firstIndex(of: "=") { return String(item[..<eq]) }
            return String(item)
        }
        return (path, names)
    }
}

/// Captured values from a matched URL.
///
/// String-keyed by capture name. Consumers convert the values to their own
/// strongly-typed identifiers (`Tagged`, `RawRepresentable`, etc.) at the
/// parse site; the library doesn't impose an ID type on the consumer.
public struct URLCaptures: Sendable {
    private let values: [String: String]

    init(_ values: [String: String]) {
        self.values = values
    }

    /// Returns the captured value for `name`, or `nil` if the capture is
    /// absent (a query-only capture whose key wasn't in the URL).
    public subscript(_ name: String) -> String? { values[name] }
}

/// Components ``URLRoute/emit`` produces when an intent matches its case.
///
/// Path components are joined onto the host with `/`. Query items are
/// optional; pass an empty array (the default) when the URL has no query.
public struct URLEmission: Sendable {
    public let pathComponents: [String]
    public let queryItems: [URLQueryItem]

    public init(_ pathComponents: String..., queryItems: [URLQueryItem] = []) {
        self.pathComponents = pathComponents
        self.queryItems = queryItems
    }
}

/// Allowed characters within a single path segment. Like `.urlPathAllowed`
/// but excluding `/` so a capture value containing a `/` is percent-encoded
/// (`%2F`) rather than treated as a segment separator.
private let pathSegmentAllowed: CharacterSet = {
    var set = CharacterSet.urlPathAllowed
    set.remove(charactersIn: "/")
    return set
}()

/// Walks an ordered list of ``URLRoute`` rules to convert between URLs and
/// intents. The single table eliminates the parallel parse/emit switches the
/// pre-table consumers had to keep in sync by eyeball.
public struct URLPathRouter<Intent: Sendable & Equatable>: Sendable {
    public let scheme: String
    public let routes: [URLRoute<Intent>]

    public init(scheme: String, routes: [URLRoute<Intent>]) {
        self.scheme = scheme
        self.routes = routes
    }

    /// Returns the intent for `url`, or `nil` if no route matches (or the
    /// scheme doesn't match).
    public func parse(_ url: URL) -> Intent? {
        guard url.scheme == scheme else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard let host = components.host, !host.isEmpty else { return nil }

        // Use `percentEncodedPath` then split on the literal `/` separator so
        // `%2F` (encoded `/`) inside a single segment is preserved. Decode
        // each segment after the split. `URL.pathComponents` would split
        // pre-decoded, silently merging the encoded slashes.
        let pathSegments = components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .compactMap { String($0).removingPercentEncoding }
        let queryItems = components.queryItems ?? []

        for route in routes {
            guard let captures = match(host: host, path: pathSegments, query: queryItems, against: route.pattern) else {
                continue
            }
            if let intent = route.parse(captures) {
                return intent
            }
        }
        return nil
    }

    /// Returns the URL for `intent`, or `nil` if no route emits it.
    ///
    /// Path components are percent-encoded individually so a capture value
    /// containing `/`, `?`, `#`, spaces, or non-ASCII characters survives
    /// the round trip. `parse(_:)` decodes back from `percentEncodedPath`
    /// segment-by-segment so the encoded `/` (`%2F`) inside a single
    /// segment isn't accidentally treated as a path separator. Query items
    /// are encoded by `URLComponents`.
    public func url(for intent: Intent) -> URL? {
        for route in routes {
            guard let emission = route.emit(intent) else { continue }
            var components = URLComponents()
            components.scheme = scheme
            components.host = route.pattern.host
            if !emission.pathComponents.isEmpty {
                let encoded = emission.pathComponents.map { segment in
                    segment.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? segment
                }
                components.percentEncodedPath = "/" + encoded.joined(separator: "/")
            }
            if !emission.queryItems.isEmpty {
                components.queryItems = emission.queryItems
            }
            return components.url
        }
        return nil
    }

    private func match(
        host: String,
        path: [String],
        query: [URLQueryItem],
        against pattern: URLPattern
    ) -> URLCaptures? {
        guard pattern.host == host else { return nil }
        guard pattern.path.count == path.count else { return nil }
        var captures: [String: String] = [:]
        for (segment, value) in zip(pattern.path, path) {
            switch segment {
            case .literal(let literal):
                guard literal == value else { return nil }
            case .capture(let name):
                captures[name] = value
            }
        }
        for name in pattern.captureQueryNames {
            if let value = query.first(where: { $0.name == name })?.value {
                captures[name] = value
            }
        }
        return URLCaptures(captures)
    }
}
