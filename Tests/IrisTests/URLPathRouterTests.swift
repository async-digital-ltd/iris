// Copyright (c) 2026 Async Digital Ltd
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import Iris

struct URLPathRouterTests {
    enum Intent: Sendable, Equatable {
        case openConversation(String)
        case openProfile(String)
        case showMessage(conversation: String, message: String)
        case search(query: String)
        case openSettings
    }

    static let router = URLPathRouter<Intent>(
        scheme: "demo",
        routes: [
            URLRoute(
                "conversation/:cid/message/:mid",
                parse: { captures in
                    guard let cid = captures["cid"], let mid = captures["mid"] else { return nil }
                    return .showMessage(conversation: cid, message: mid)
                },
                emit: { intent in
                    if case .showMessage(let cid, let mid) = intent {
                        return URLEmission(cid, "message", mid)
                    }
                    return nil
                }
            ),
            URLRoute(
                "conversation/:id",
                parse: { captures in captures["id"].map(Intent.openConversation) },
                emit: { intent in
                    if case .openConversation(let id) = intent {
                        return URLEmission(id)
                    }
                    return nil
                }
            ),
            URLRoute(
                "profile/:id",
                parse: { captures in captures["id"].map(Intent.openProfile) },
                emit: { intent in
                    if case .openProfile(let id) = intent {
                        return URLEmission(id)
                    }
                    return nil
                }
            ),
            URLRoute(
                "search?q",
                parse: { captures in .search(query: captures["q"] ?? "") },
                emit: { intent in
                    if case .search(let query) = intent {
                        return URLEmission(queryItems: [URLQueryItem(name: "q", value: query)])
                    }
                    return nil
                }
            ),
            URLRoute(
                "settings",
                parse: { _ in .openSettings },
                emit: { intent in
                    if case .openSettings = intent { return URLEmission() }
                    return nil
                }
            )
        ]
    )

    // MARK: parse

    @Test func parsesSingleCaptureRoute() {
        let url = URL(string: "demo://conversation/scrum")!
        #expect(Self.router.parse(url) == .openConversation("scrum"))
    }

    @Test func parsesMultiCaptureRouteBeforeFallback() {
        // The two-capture route is listed first; the single-capture route
        // mustn't accidentally win.
        let url = URL(string: "demo://conversation/scrum/message/sc7")!
        #expect(Self.router.parse(url) == .showMessage(conversation: "scrum", message: "sc7"))
    }

    @Test func parsesQueryCapture() {
        let url = URL(string: "demo://search?q=mock")!
        #expect(Self.router.parse(url) == .search(query: "mock"))
    }

    @Test func parsesHostOnly() {
        let url = URL(string: "demo://settings")!
        #expect(Self.router.parse(url) == .openSettings)
    }

    @Test func mismatchedSchemeReturnsNil() {
        let url = URL(string: "other://conversation/scrum")!
        #expect(Self.router.parse(url) == nil)
    }

    @Test func unknownHostReturnsNil() {
        let url = URL(string: "demo://unknown/path")!
        #expect(Self.router.parse(url) == nil)
    }

    @Test func wrongPathLengthReturnsNil() {
        // pattern is "conversation/:id" (host + 1 segment), so three segments
        // means the multi-capture pattern doesn't match either.
        let url = URL(string: "demo://conversation/scrum/extra")!
        #expect(Self.router.parse(url) == nil)
    }

    @Test func trailingSlashOnHostOnlyURLStillMatches() {
        let url = URL(string: "demo://settings/")!
        #expect(Self.router.parse(url) == .openSettings)
    }

    @Test func emptyHostReturnsNil() {
        let url = URL(string: "demo:///conversation/abc")!
        #expect(Self.router.parse(url) == nil)
    }

    @Test func encodedSlashInCaptureRoundTrips() {
        // A capture value containing a `/` would split into two path
        // segments unless percent-encoded by the emit side. Confirms emit
        // encodes and parse decodes symmetrically.
        let intent = Intent.openConversation("conv/with/slashes")
        guard let url = Self.router.url(for: intent) else {
            Issue.record("emit returned nil"); return
        }
        #expect(Self.router.parse(url) == intent)
    }

    // MARK: emit

    @Test func emitsSingleCaptureURL() {
        let url = Self.router.url(for: Intent.openConversation("scrum"))
        #expect(url?.absoluteString == "demo://conversation/scrum")
    }

    @Test func emitsMultiCaptureURL() {
        let url = Self.router.url(for: Intent.showMessage(conversation: "scrum", message: "sc7"))
        #expect(url?.absoluteString == "demo://conversation/scrum/message/sc7")
    }

    @Test func emitsHostOnly() {
        let url = Self.router.url(for: Intent.openSettings)
        #expect(url?.absoluteString == "demo://settings")
    }

    @Test func emitsQuery() {
        let url = Self.router.url(for: Intent.search(query: "mock"))
        #expect(url?.absoluteString == "demo://search?q=mock")
    }

    // MARK: round trip

    @Test func roundTripPreservesEveryRoute() {
        let cases: [Intent] = [
            .openConversation("scrum"),
            .openProfile("design"),
            .showMessage(conversation: "scrum", message: "sc7"),
            .search(query: "mock"),
            .openSettings
        ]
        for intent in cases {
            guard let url = Self.router.url(for: intent) else {
                Issue.record("emit returned nil for \(intent)")
                continue
            }
            #expect(Self.router.parse(url) == intent, "round-trip mismatch on \(intent)")
        }
    }

    /// `URLQueryItem` does the encoding for us; this confirms a query with
    /// URL-significant characters survives parse → emit → parse.
    @Test func searchQueryWithSpecialCharactersRoundTrips() {
        let intent = Intent.search(query: "mock & roll#1")
        guard let url = Self.router.url(for: intent) else {
            Issue.record("emit returned nil"); return
        }
        #expect(Self.router.parse(url) == intent)
    }
}
