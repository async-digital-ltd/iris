# URL parsing

Turn an incoming URL into a strongly-typed intent the rest of the library
can dispatch on.

## Overview

A link arrives as a `URL`. Before it can drive navigation, it must
be parsed into a value the consumer's flow understands. Iris
calls this value the **intent**.

The protocol is deliberately one method:

```swift
public protocol URLParsing: Sendable {
    associatedtype Intent: Sendable & Equatable
    func parse(_ url: URL) -> Intent
}
```

Malformed URLs are handled inside the codec, typically by returning a
fallback intent (`.unknown`, `.openHome`, etc.). Throwing isn't part of
the contract; the parser is expected to always return *something*.

## Writing a codec

For one-off apps the most direct approach is a custom type that switches
on the URL's host and path:

```swift
struct MyURLCodec: URLParsing {
    func parse(_ url: URL) -> MyIntent {
        switch url.host {
        case "inbox":   return .showInbox
        case "profile": return .showProfile(id: url.lastPathComponent)
        default:        return .unknown
        }
    }
}
```

That's fine for two or three URL shapes. Past that the manual switch
starts to drift, and the parsing side ends up out of sync with whatever
emits URLs back out (sharing, restoration, debug overlays).

## Using URLPathRouter

For more than a handful of URL shapes, ``URLPathRouter`` co-locates
parse and emit in a single table:

```swift
let router = URLPathRouter<MyIntent>(
    scheme: "myapp",
    routes: [
        URLRoute(
            "conversation/:id",
            parse: { c in .openConversation(.init(rawValue: c["id"]!)) },
            emit: { intent in
                if case .openConversation(let id) = intent {
                    return URLEmission(id.rawValue)
                }
                return nil
            }
        ),
        URLRoute(
            "search?q",
            parse: { c in .search(query: c["q"] ?? "") },
            emit: { intent in
                if case .search(let q) = intent {
                    return URLEmission(queryItems: [.init(name: "q", value: q)])
                }
                return nil
            }
        ),
    ]
)
```

The router walks the list in order:

- **Parsing**: first matching ``URLPattern`` wins; the pattern's
  captures arrive in the route's `parse` closure as ``URLCaptures``.
- **Emitting**: first non-nil ``URLEmission`` wins.

Because parse and emit share a `URLRoute` value, an intent that the
parser knows about can't silently lose its emit case (or vice versa).
That's the whole reason the type exists.

### Pattern grammar

``URLPattern`` understands four shapes:

| Pattern | Meaning |
| --- | --- |
| `host` | Bare host, no path or query. |
| `host/seg1/seg2` | Host plus literal path segments. |
| `host/:name` | `:name` becomes a captured value in ``URLCaptures``. |
| `host?q&r` | Query parameter names that become captures. |

Query captures are always optional from the matcher's perspective:
absence means no entry in ``URLCaptures``.

### Encoding

``URLPathRouter`` percent-encodes path components segment-by-segment, so
a capture value containing `/`, `?`, `#`, spaces, or non-ASCII
characters survives the round trip. `parse(_:)` decodes from
`percentEncodedPath` segment-by-segment as well: an encoded `/`
(`%2F`) inside a single segment isn't accidentally treated as a path
separator. Query items are encoded by `URLComponents`.

## Rejecting unresolved targets

Some intents carry an identifier that has to resolve against real state: a
conversation, a profile, a record fetched from wherever the app keeps its
data. Nothing in ``URLParsing`` or ``URLPathRouter`` checks that
automatically; matching a URL pattern only proves the *shape* of the URL is
right, not that its target still exists.

Checking existence inside the parser, rather than downstream, means every
consumer of the intent can assume it's the real thing:

```swift
struct MyURLCodec: URLParsing {
    func parse(_ url: URL) -> MyIntent {
        guard let intent = Self.router.parse(url) else { return .unknown }
        guard Self.resolves(intent) else { return .unknown }
        return intent
    }

    private static func resolves(_ intent: MyIntent) -> Bool {
        switch intent {
        case .openConversation(let id): ConversationStore.exists(id)
        default: true
        }
    }

    private static let router = URLPathRouter<MyIntent>(/* ... */)
}
```

A URL for a conversation deleted since the link was generated (or shared from
another device, or just malformed) is dropped at this gate rather than
reaching the coordinator as a valid-looking intent for a row that isn't
there. The coordinator, the flow, and every view downstream can assume an
`.openConversation` intent always has a real conversation behind it. The
alternative is handled once, at the parsing boundary, instead of re-checked
by every consumer.

This is the same always-return-something discipline as malformed URLs
above: an unresolved target is just another shape of "this URL doesn't mean
anything to us right now."

## Multicasting parsed batons

When more than one part of the app cares about the same link
(say, both the active screen and an analytics observer), wrap the codec
in a ``Broadcaster``:

```swift
let broadcaster = Broadcaster(urlCodec: MyURLCodec())
```

The broadcaster parses the URL, wraps the intent in a ``Baton``,
and yields it to every active subscriber. New subscribers receive the
last baton on attach by default (replay-last), so a late-mounting
observer still sees the link that arrived during launch.

## Topics

### Protocols

- ``URLParsing``

### Table-based routing

- ``URLPathRouter``
- ``URLRoute``
- ``URLPattern``
- ``URLCaptures``
- ``URLEmission``

### Broadcasting

- ``Broadcaster``
