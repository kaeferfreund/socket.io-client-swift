# Socket.IO-Client-Swift

[![Swift validation](https://github.com/kaeferfreund/socket.io-client-swift/actions/workflows/swift.yml/badge.svg?branch=master)](https://github.com/kaeferfreund/socket.io-client-swift/actions/workflows/swift.yml)

A Swift Socket.IO client for iOS, macOS, tvOS and watchOS. This fork uses Apple's
`URLSessionWebSocketTask` directly for WebSockets and a separate `URLSession` for
HTTP long-polling. **Starscream is no longer a dependency.**

The usual `SocketManager` / `SocketIOClient` API remains the entry point. No flag
or additional transport library is needed to use the native backend. The native
migration changes some 16.x APIs; see [migration notes](Documentation/NativeWebSocketTransport.md).

## Features

- HTTP long-polling, polling-to-WebSocket upgrades and WebSocket-only connections.
- Text and binary events, namespaces, acknowledgements, timeouts and optional retries.
- Automatic reconnection, authentication payloads/providers and Connection State Recovery when supported by the server.
- System TLS validation, certificate pinning, custom trust anchors and configurable incoming-packet limits.

## Requirements and server compatibility

| Requirement | Minimum |
| --- | --- |
| Swift tools | 5.5, using the package's Swift 5 language mode |
| iOS / tvOS | 15 |
| macOS | 12 |
| watchOS | 8 |

The public API is intended for Swift. Strict Swift 6 concurrency compatibility
and an Objective-C integration are not claimed.

| Socket.IO server | Client configuration | Engine.IO protocol |
| --- | --- | --- |
| 3.x / 4.x | `.version(.three)`, the default | 4 |
| 2.x | `.version(.two)` | 3 |

`.three` also selects the mode for Socket.IO 4.x servers; there is no `.four`
option. This is a **Socket.IO client**, not a client for an arbitrary WebSocket
endpoint. Compatibility details and known differences from the JavaScript client
are recorded in [PARITY.md](PARITY.md).

## Installation

Use **this fork**, rather than an upstream 16.x dependency. `master` is the
repository's default development branch. To evaluate changes from an unmerged
pull request, select that PR's head branch or commit instead of `master`.
Pin a reviewed commit for reproducible application builds.

### Swift Package Manager

In Xcode, add this package repository and select `master` or a specific commit:

```text
https://github.com/kaeferfreund/socket.io-client-swift.git
```

For a `Package.swift` manifest, add:

```swift
.package(
    url: "https://github.com/kaeferfreund/socket.io-client-swift.git",
    branch: "master"
)
```

Add `.product(name: "SocketIO", package: "socket.io-client-swift")` to the
application target's dependencies and declare the applicable deployment minimum.
To pin a commit in the manifest, replace `branch:` with `revision:` and its full
commit SHA. Import the library with `import SocketIO`.

### CocoaPods

Select the Git source explicitly in your `Podfile`:

```ruby
use_frameworks!

target 'YourApp' do
  pod 'Socket.IO-Client-Swift',
      :git => 'https://github.com/kaeferfreund/socket.io-client-swift.git',
      :branch => 'master'
end
```

Run `pod install`. For a pinned checkout, use `:commit` instead of `:branch`.

### Carthage

Add this fork to your application's `Cartfile`:

```text
github "kaeferfreund/socket.io-client-swift" "master"
```

Link/embed **SocketIO only**. Remove previous Starscream linkage or copy-frameworks
entries only when no other application dependency needs them.

## Quick start

Run this setup and subsequent client calls on **`DispatchQueue.main`**, the
default `manager.handleQueue`. Keep the manager as a property of your app or
another long-lived owner; a socket holds only a weak reference to its manager.
Replace the example URL and event names with those used by your Socket.IO server.

```swift
import Foundation
import SocketIO

let manager = SocketManager(
    socketURL: URL(string: "https://example.com")!,
    config: [.log(false)]
)
let socket = manager.defaultSocket

socket.on(clientEvent: .connect) { _, _ in
    print("Socket connected")
}

socket.on(clientEvent: .connectError) { data, _ in
    print("Connection failed:", data)
}

socket.on(clientEvent: .error) { data, _ in
    print("Socket error:", data)
}

socket.on("message") { data, _ in
    guard let message = data.first as? String else { return }
    print("Received:", message)
}

// Register handlers before opening the connection.
socket.connect()
```

To send an event, call `socket.emit("message", "Hello from Swift")` on the same
queue. Use `socket.disconnect()` when intentionally leaving the namespace.
Register handlers once, not inside a reconnect handler, to avoid duplicate delivery
to application callbacks.

For a custom `.handleQueue(...)`, use a **serial** queue and perform setup,
listener registration and client calls on it. Event handlers run on that queue;
move UI updates to the main queue as needed. The client is not generally
thread-safe, even though some individual APIs dispatch internally.

### Connection options

The default connection starts with polling and can upgrade to WebSocket. Use
`.forceWebsockets(true)` or `.forcePolling(true)` to select only one transport;
do not enable both. `.path("/socket.io/")` configures the HTTP endpoint, while
`manager.socket(forNamespace: "/orders")` selects a Socket.IO namespace.

`.autoConnect` defaults to `false`, so the explicit `connect()` above is enough.
`.autoConnect(true)` starts connection work during manager initialization for the
default namespace. Other namespaces still require their own `connect()`.

Automatic reconnection is enabled by default for recoverable connection loss.
The event stream matches the JavaScript client: the drop reports `.disconnect`
with the real reason, each retry reports `.reconnectAttempt` with its 1-based
attempt number, a failed retry reports `.reconnectError`, and the cycle ends
either with `.reconnect` (carrying the attempt number that succeeded, followed
by `.connect` once the namespace is re-joined) or with `.reconnectFailed`.
An intentional `disconnect()` requires an explicit `connect()` to rejoin.

```swift
socket.on(clientEvent: .disconnect)       { data, _ in print("dropped:", data.first ?? "") }
socket.on(clientEvent: .reconnectAttempt) { data, _ in print("attempt", data.first ?? "") }
socket.on(clientEvent: .reconnect)        { data, _ in print("back after attempt", data.first ?? "") }
socket.on(clientEvent: .reconnectFailed)  { _, _ in print("gave up") }
```

## Acknowledgements and retries

Use a finite timeout when waiting for a server acknowledgement. Timeout values
in this Swift API are in **seconds**, not JavaScript-style milliseconds.

```swift
socket.timeout(after: 5).emit("canUpdate", 12.5) { error, data in
    if let error = error {
        print("Acknowledgement failed:", error)
        return
    }

    print("Server acknowledged:", data)
}
```

The server must acknowledge the event for this callback to succeed. A local
`emit` completion is **not** a server acknowledgement. A timeout also does not
prove that the server failed to process an event.

`.ackTimeout(5)` sets a default acknowledgement timeout for the error-first
`emit(..., ack:)` API. `.retries(2)` enables an ordered retry queue with up to two
retries after the initial attempt. Pair retries with a finite acknowledgement
timeout, otherwise a missing acknowledgement can block the queue indefinitely.
Retries can deliver the same event more than once; use application-level IDs and
server-side deduplication for operations that must not be repeated.

The legacy `emitWithAck(...).timingOut(after:)` API remains available, but its
callback and timeout contract differs from the error-first and async APIs. See
[SocketTimedEmitter.swift](Source/SocketIO/Ack/SocketTimedEmitter.swift) and
[the parity notes](PARITY.md) before mixing those styles.

## Authentication and recovery

For Socket.IO 3.x/4.x servers that accept an authentication payload:

```swift
socket.connect(withPayload: ["token": "your-access-token"])
```

The server's namespace middleware must validate that payload. Use `.extraHeaders`
for HTTP headers or `.connectParams` for URL query parameters instead when required
by your server. Avoid putting credentials in URLs or enabling debug logging in
production. Auth providers are available through `setAuth(_:)`; see
[SocketIOClient.swift](Source/SocketIO/Client/SocketIOClient.swift).

### Connection State Recovery

With a `.version(.three)` manager and a Socket.IO server configured for
`connectionStateRecovery`, a reconnect after an abrupt transport loss can resume
a prior session and replay missed server-to-client events. Recovery depends on
the server accepting the saved session and offset; it is not guaranteed.
`.version(.two)` does not use recovery.

```swift
socket.on(clientEvent: .connect) { [weak socket] _, _ in
    guard let socket = socket else { return }
    if socket.recovered {
        print("Previous session recovered")
    } else {
        // Re-establish any application subscriptions/state needed for a fresh session.
        print("Fresh session")
    }
}
```

Register this handler before connecting. `socket.recovered` and the `recovered`
field in the `.connect` payload describe the latest successful connection.
Replay events received before that connection completes are buffered and delivered
through the existing event handlers.

Recovery, disconnected-send and retry state are in memory, not durable storage.
For an identity change, stop producing events for the old user, replace or clear
any installed auth provider, and clear the old socket's state before reconnecting:

```swift
socket.clearRecoveryState()
socket.disconnect()
socket.connect(withPayload: ["token": "new-access-token"])
```

`clearRecoveryState()` drops recovery state, buffered replay, queued sends and
retries, and fails affected timed acknowledgements with `SocketAckError.disconnected`.
It does not retract events already delivered to application handlers or by itself
close the live connection. Ensure disconnect/ack handlers do not reconnect using
the old credentials or enqueue new old-user work during the switch.

## Breaking changes in 17.0.0

This major prerelease moves behaviour that used to be Swift-specific onto the
JavaScript client's contract. Everything below changes an observable API; see
[the changelog](CHANGELOG.md) for the reasoning and
[the parity review](Documentation/ProtocolParityReview.md) for the ported tests.

| Change | Before | Now |
| --- | --- | --- |
| `.reconnect` | Fired when reconnection **started**, payload was the disconnect reason. | Fires when a reconnection **succeeded**, payload is the 1-based attempt number (JS `reconnect`). |
| `.reconnectAttempt` | Payload was the number of attempts **remaining**. | Payload is the 1-based number of the attempt being made (JS `reconnect_attempt`). |
| `.disconnect` on a retried drop | Not emitted; the reason arrived with `.reconnect`. | Emitted with the real reason (`transport close`, `ping timeout`, `parse error`, …), as JS `Socket.onclose` does. |
| Reconnect exhaustion | `.disconnect("Reconnect Failed")`. | New `.reconnectFailed` (no payload). The sockets already got their real `.disconnect`. |
| Per-attempt failure | Nothing. | New `.reconnectError` with the reason. |
| Unencodable emit payload | Silently sent a different packet with an empty payload (`2[]`). | Throws `SocketPacketError`: the `.error` client event carries it, any acknowledgement settles once with it, and no packet is written, buffered or queued. |
| `Date` in an emit | Not a `SocketData`, and unencodable if forced through. | Encodes as the ISO-8601 string `JSON.stringify` produces (`2024-01-02T03:04:05.678Z`), nested at any depth. |
| Non-finite `Double` in an emit | Made the whole payload unencodable. | Encodes as `null`, like `JSON.stringify(NaN)`. |
| `Data` through `rawEmitView` | Silently sent an empty payload. | Throws `SocketPacketError.unsupportedValue`; that view deliberately does not shred binary into attachments. |
| Server-URL query string | Discarded when the engine built its transport URLs. | Used as the connection query, unless `.connectParams` is set (JS `if (parsed.query && !opts.query)`). |
| JSON object key order | Arbitrary, varied between runs. | Sorted, so the wire output is reproducible. A Swift `Dictionary` has no insertion order to preserve, and JSON object order carries no meaning. |

Additions that are not breaking: `async` `socket.emitWithAck(_:_:)` and
`socket.timeout(after:).emitWithAck(_:_:)`, `SocketPacket.encodedPacketString()`
(the throwing encoder) and `SocketPacketError`.

## TLS and migration from Starscream

An `https://` URL uses normal system certificate validation for both polling and
WebSocket. No custom TLS configuration is needed for a normally trusted server.
For pinning or a private CA, configure `.security(...)` with
`SocketTLSConfiguration`. Its certificate data is DER-encoded; custom trust anchors
and pins do not disable hostname, validity-period or chain checks.
See [TLS configuration examples](Documentation/NativeWebSocketTransport.md#tls).

| Previous API/option | Native behavior |
| --- | --- |
| `.security(CertificatePinning)` | Migrate to `SocketTLSConfiguration`. |
| `SocketEngine.ws` / `SocketEngineSpec.ws` | Removed; the transport is internal. |
| `.useCustomEngine(...)` | Deprecated, has no effect; remove it. |
| `.compress` | Unsupported, produces a connection configuration error. |
| `.selfSigned(true)` | Unsupported; configure explicit custom trust anchors instead. |
| `.enableSOCKSProxy(true)` | Unsupported, produces a configuration error instead of silently connecting directly. |

External `.sessionDelegate` callbacks cannot override the configured server-trust
policy. Native compression controls, SOCKS routing and WebTransport are not
provided by this fork.

## Optional parser limits

No custom parser configuration is required for normal use. The current defaults
are defined in [SocketParserOptions](Source/SocketIO/Parse/SocketParsable.swift):

| Setting | Default |
| --- | --- |
| Binary attachments per packet | 10 |
| Socket.IO text packet bytes | `Int.max`, no configured byte cap |
| Combined binary reconstruction bytes | `Int.max`, no configured byte cap |
| JSON nesting depth | 512; configurable from 1 to 1024 |

The nesting check protects Foundation's JSON decoder from excessively deep input.
It is a deliberate acceptance limit, not a claim of identical JavaScript behavior.
All configured byte/count limits must be positive. Invalid settings are rejected
before connecting.

To opt into smaller packet budgets, pass `.parserOptions` when creating the manager:

```swift
let parserOptions = SocketParserOptions(
    maximumBinaryPacketBytes: 1 << 20,
    maximumTextPacketBytes: 1 << 20
)
let manager = SocketManager(
    socketURL: URL(string: "https://example.com")!,
    config: [.parserOptions(parserOptions)]
)
```

These optional 1 MiB limits apply to incoming Socket.IO packets on both transports.
They are **separate** from `.webSocketOptions`: by default the native WebSocket
transport limits each incoming message to 16 MiB and pending outgoing payload to
16 MiB, 1024 batches and 4096 messages. See
[SocketWebSocketOptions](Source/SocketIO/Engine/Transport/SocketWebSocketOptions.swift).
The server's Engine.IO `maxPayload` separately governs outgoing polling batches.

None of these settings is a total application-memory limit. In particular,
disconnected-send and retry queues can grow while offline; avoid producing an
unbounded stream of reliable events during long outages. Use `socket.volatile`
only for updates that may safely be dropped.

## Testing and JavaScript parity

From a macOS checkout with a Swift toolchain, Node/npm and OpenSSL available:

```sh
swift build
swift test
```

The suite includes unit tests and real Socket.IO / HTTPS / WSS fixture servers.
TLS tests generate temporary certificates without installing system trust roots.
Additional checks are available through:

```sh
bash scripts/test-native-transport.sh
bash scripts/test-native-distributions.sh
bash scripts/test-parser-safety.sh
```

The [Swift workflow](.github/workflows/swift.yml) also runs polling wire proofs
and a differential against a pinned official JavaScript implementation, in both
directions: the real upstream decoder reads seeded vectors alongside this
client's decoder, and the packets this client encodes are read back by that same
upstream decoder.
Check the CI run for the exact commit you use, not a historical test count.
SDK builds cover macOS and the iOS/tvOS/watchOS simulators; they do not replace
runtime testing in your application on physical devices and across network changes.

The complete upstream JavaScript test suite has **not** been ported, and full
behavioral equivalence has not been established. The finite decoder comparison
is not a guarantee for
all connection, acknowledgement or recovery scenarios. See [PARITY.md](PARITY.md),
[the test inventory](Documentation/JavaScriptTestInventory.csv) and
[the protocol review](Documentation/ProtocolParityReview.md) for the evidence,
known differences and outstanding work.

## Documentation and license

[Native migration guide](Documentation/NativeWebSocketTransport.md) ·
[Changelog](CHANGELOG.md) · [CodeRabbit audit](Documentation/CodeRabbitAudit.md)

The generated `docs/` HTML and older upstream examples describe the historical
16.x API. Use this checkout's Swift source and migration notes for current
transport and security APIs.

Based on [socketio/socket.io-client-swift](https://github.com/socketio/socket.io-client-swift).
Licensed under [MIT](LICENSE).
