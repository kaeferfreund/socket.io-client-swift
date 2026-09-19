# Socket.IO Client for Swift

A native Swift client for Socket.IO 4.x on iOS, macOS, tvOS and watchOS.

Built on Apple's URLSession, with native HTTP long-polling and URLSessionWebSocketTask transports. No Starscream and no third-party Swift runtime dependencies.

17.0.0 is currently being prepared and has not been published yet.
Until the release tag is available, use a reviewed commit from master for reproducible builds. See [Release 17 status](Documentation/Release17.md).

## At a glance

- Socket.IO 4.x / Engine.IO 4
- HTTP long-polling and WebSocket
- Automatic polling → WebSocket upgrades
- Native URLSessionWebSocketTask
- Text and binary events
- Namespaces
- Acknowledgements, timeouts and retries
- async/await acknowledgement APIs
- Automatic reconnection with Socket.IO-compatible backoff semantics
- Dynamic authentication providers
- Connection State Recovery with compatible Socket.IO 4.6+ servers
- Volatile events
- TLS system trust, certificate pinning and private trust anchors
- Swift 6 concurrency checking
- No third-party Swift dependencies

This library implements the Socket.IO protocol. It is not a generic WebSocket client.

## Requirements

| Minimum | |
| --- | --- |
| Swift toolchain | Swift 6.4 |
| Swift language mode | Swift 6 |
| Xcode | Xcode 27 |
| iOS | 15 |
| macOS | 12 |
| tvOS | 15 |
| watchOS | 9 |
| Socket.IO server | 4.x |
| Engine.IO protocol | 4 |

Socket.IO 2.x and earlier protocol modes are no longer supported.

Socket.IO 3.x shares much of the modern wire protocol, but it is outside the supported and tested server range of this client.

## Transport support

| Transport | Support |
| --- | --- |
| HTTP long-polling | ✅ |
| WebSocket | ✅ |
| Polling → WebSocket upgrade | ✅ |
| WebSocket-only | ✅ |
| WebTransport | ❌ |

## Installation

Swift Package Manager is the recommended and supported installation method.

In Xcode, choose:

**File → Add Package Dependencies**

and enter:

```text
https://github.com/kaeferfreund/socket.io-client-swift.git
```

While 17.0.0 is unreleased, pin a reviewed commit for reproducible builds.

For a Package.swift:

```swift
dependencies: [
    .package(
        url: "https://github.com/kaeferfreund/socket.io-client-swift.git",
        revision: "<commit-sha>"
    )
]
```

Then add the library to your target:

```swift
.product(
    name: "SocketIO",
    package: "socket.io-client-swift"
)
```

After v17.0.0 is published, use the stable version range instead of a branch or revision:

```swift
.package(
    url: "https://github.com/kaeferfreund/socket.io-client-swift.git",
    from: "17.0.0"
)
```

Import the package with:

```swift
import SocketIO
```

## Quick start

Keep the SocketManager alive for as long as you use its sockets.

```swift
import Foundation
import SocketIO

final class RealtimeClient {
    private let manager: SocketManager
    private let socket: SocketIOClient

    init() {
        manager = SocketManager(
            socketURL: URL(string: "https://example.com")!,
            config: [
                .log(false)
            ]
        )

        socket = manager.defaultSocket

        socket.on(clientEvent: .connect) { _, _ in
            print("Connected")
        }

        socket.on(clientEvent: .disconnect) { data, _ in
            print("Disconnected:", data.first ?? "")
        }

        socket.on(clientEvent: .connectError) { data, _ in
            print("Connection failed:", data)
        }

        socket.on(clientEvent: .error) { data, _ in
            print("Socket error:", data)
        }

        socket.on("message") { data, _ in
            print("Received:", data)
        }
    }

    func connect() {
        socket.connect()
    }

    func disconnect() {
        socket.disconnect()
    }

    func send(_ message: String) {
        socket.emit("message", message)
    }
}
```

Register listeners before connecting.

autoConnect defaults to false, so the socket only connects when you call:

```swift
socket.connect()
```

## Receiving events

Register a listener with on:

```swift
socket.on("chatMessage") { data, ack in
    guard
        let message = data.first as? [String: Any],
        let text = message["text"] as? String
    else {
        return
    }

    print(text)
}
```

Use once for a single invocation:

```swift
socket.once("ready") { data, ack in
    print("Server is ready")
}
```

on and once return an identifier that can later remove exactly that listener:

```swift
let listener = socket.on("message") { data, _ in
    print(data)
}

socket.off(id: listener)
```

Remove all listeners for an event with:

```swift
socket.off("message")
```

## Sending events

Send an event with one or more SocketData values:

```swift
socket.emit("message", "Hello from Swift")
socket.emit(
    "updateProfile",
    [
        "name": "Ada",
        "active": true
    ]
)
```

Supported payload values include the usual JSON-compatible Swift/Foundation values, binary Data, and Date.

Date is encoded as an ISO-8601 timestamp compatible with JavaScript's Date.prototype.toJSON() representation.

You can also use Socket.IO's "message" shortcut:

```swift
socket.send("Hello")
```

which is equivalent to:

```swift
socket.emit("message", "Hello")
```

### Custom payload types

Your own types can conform to SocketData:

```swift
struct User: SocketData {
    let id: Int
    let name: String

    func socketRepresentation() -> SocketData {
        [
            "id": id,
            "name": name
        ]
    }
}
```

Then emit them normally:

```swift
socket.emit("user", User(id: 42, name: "Ada"))
```

## Acknowledgements

Socket.IO acknowledgements let the server confirm or respond to an event.

For new code, prefer the typed timeout API or the async API.

### Callback

```swift
socket.timeout(after: 5).emit("createOrder", ["item": "coffee"]) { error, data in
    if let error {
        print("Acknowledgement failed:", error)
        return
    }

    print("Server response:", data)
}
```

Timeout values in the Swift API are specified in seconds.

A timeout means that no acknowledgement was received in time. It does not prove that the server did not process the event.

### async / await

```swift
do {
    let response = try await socket
        .timeout(after: 5)
        .emitWithAck("createOrder", ["item": "coffee"])

    print(response)
} catch SocketAckError.timeout {
    print("Server did not acknowledge in time")
} catch SocketAckError.disconnected {
    print("Socket disconnected before the acknowledgement")
} catch is CancellationError {
    print("Task was cancelled")
} catch {
    print("Acknowledgement failed:", error)
}
```

You can also use:

```swift
let response = try await socket.emitWithAck("event", "value")
```

When no explicit timeout is supplied, this uses the effective ackTimeout configured for the socket.

### Default acknowledgement timeout

Configure a default:

```swift
let manager = SocketManager(
    socketURL: URL(string: "https://example.com")!,
    config: [
        .ackTimeout(5)
    ]
)
```

Or override it for one namespace:

```swift
socket.ackTimeout = 3
```

### Automatic retries

Socket.IO-style ordered retries are available with:

```swift
let manager = SocketManager(
    socketURL: URL(string: "https://example.com")!,
    config: [
        .ackTimeout(5),
        .retries(2)
    ]
)
```

This means:

- one initial attempt
- up to two retries
- retries occur when the required acknowledgement does not arrive

Retries may cause an event to reach the server more than once.

For operations that must be idempotent, include an application-level event ID and deduplicate on the server.

A namespace can override the manager defaults:

```swift
socket.ackTimeout = 2
socket.retries = 1
```

Restore the manager defaults with:

```swift
socket.resetDeliveryOptions()
```

### Legacy acknowledgement API

The historical API remains available:

```swift
socket.emitWithAck("event", "value")
    .timingOut(after: 5) { data in
        print(data)
    }
```

New code should generally prefer timeout(after:) or the async acknowledgement API because they provide typed errors and clearer disconnect semantics.

### Acknowledging incoming events

A server may request an acknowledgement from the client.

```swift
socket.on("question") { data, ack in
    guard ack.expected else { return }

    ack.with("received")
}
```

## Authentication

### Static connection payload

For a simple authentication payload:

```swift
socket.connect(
    withPayload: [
        "token": accessToken
    ]
)
```

The payload is sent in the Socket.IO namespace CONNECT packet.

This is different from HTTP headers and URL query parameters.

### Dynamic authentication

When credentials can change between reconnects, use an auth provider.

Callback provider:

```swift
socket.setAuth { callback in
    callback([
        "token": accessToken
    ])
}
```

The provider is evaluated for every CONNECT, including reconnects.

Async provider:

```swift
socket.setAuth {
    let token = try await tokenProvider.accessToken()

    return [
        "token": token
    ]
}
```

If the async provider throws, the connection attempt fails closed and an .error client event is emitted.

Remove the provider with:

```swift
socket.clearAuth()
```

### HTTP headers

If your server expects HTTP authentication instead:

```swift
let manager = SocketManager(
    socketURL: URL(string: "https://example.com")!,
    config: [
        .extraHeaders([
            "Authorization": "Bearer \(accessToken)"
        ])
    ]
)
```

Use .connectParams(...) only when your server intentionally expects URL query parameters.

Avoid putting long-lived credentials into URLs.

## Namespaces

A single SocketManager can multiplex multiple Socket.IO namespaces over one Engine.IO connection.

```swift
let manager = SocketManager(
    socketURL: URL(string: "https://example.com")!
)

let chat = manager.socket(forNamespace: "/chat")
let notifications = manager.socket(forNamespace: "/notifications")

chat.on("message") { data, _ in
    print("Chat:", data)
}

notifications.on("notification") { data, _ in
    print("Notification:", data)
}

chat.connect()
notifications.connect()
```

Calling socket(forNamespace:) repeatedly with the same namespace returns the same managed socket.

Keep a strong reference to the manager. The socket itself does not own the manager.

## Reconnection

Automatic reconnection is enabled by default.

Default reconnect behavior:

| Option | Default |
| --- | --- |
| reconnects | true |
| reconnectAttempts | unlimited |
| reconnectWait | 1 second |
| reconnectWaitMax | 5 seconds |
| randomizationFactor | 0.5 |
| connectTimeout | 20 seconds |

The reconnect backoff follows the modern Socket.IO client behavior.

Useful lifecycle events:

```swift
socket.on(clientEvent: .disconnect) { data, _ in
    print("Disconnected:", data.first ?? "")
}

socket.on(clientEvent: .reconnectAttempt) { data, _ in
    print("Reconnect attempt:", data.first ?? "")
}

socket.on(clientEvent: .reconnectError) { data, _ in
    print("Reconnect attempt failed:", data.first ?? "")
}

socket.on(clientEvent: .reconnect) { data, _ in
    print("Transport reconnected after attempt:", data.first ?? "")
}

socket.on(clientEvent: .reconnectFailed) { _, _ in
    print("Reconnect attempts exhausted")
}
```

A successful transport reconnection emits .reconnect, followed by .connect after the Socket.IO namespace has been joined again.

An intentional:

```swift
socket.disconnect()
```

does not immediately start an automatic reconnect. Call connect() again when you want to rejoin.

## Connection State Recovery

Socket.IO 4.6+ can optionally recover a previous Socket.IO session after a temporary connection loss.

The server must have connectionStateRecovery configured.

Check:

```swift
socket.on(clientEvent: .connect) { [weak socket] _, _ in
    guard let socket else { return }

    if socket.recovered {
        print("Previous session recovered")
    } else {
        print("Fresh session")
    }
}
```

When recovery succeeds, missed server-to-client events can be replayed by the server.

Recovery is not guaranteed. Application code must still handle a completely fresh connection.

### Changing authenticated users

Recovery state belongs to the current logical session.

When switching identities, clear it before reconnecting:

```swift
socket.clearRecoveryState()
socket.disconnect()

socket.connect(
    withPayload: [
        "token": newAccessToken
    ]
)
```

clearRecoveryState() also discards pending buffered/retry state associated with the previous identity.

## Volatile events

Volatile events are useful for frequently updated state where dropping an event is preferable to buffering stale data.

Examples include:

- cursor positions
- live location updates
- typing indicators
- telemetry
- continuously changing UI state

```swift
socket.volatile.emit(
    "cursor",
    [
        "x": 120,
        "y": 240
    ]
)
```

If the current transport cannot write the event immediately, a volatile event is dropped instead of being placed in the normal send buffer.

## Catch-all listeners

Listen to arbitrary incoming application events:

```swift
socket.onAny { event in
    print(event.event, event.items ?? [])
}
```

For multiple independently removable catch-all listeners:

```swift
let id = socket.addAnyListener { event in
    print(event.event)
}

socket.removeAnyListener(id: id)
```

Outgoing application events can also be observed:

```swift
let id = socket.addAnyOutgoingListener { event in
    print("Sending:", event.event)
}

socket.removeAnyOutgoingListener(id: id)
```

## Transport configuration

The default connection starts with HTTP long-polling and upgrades to WebSocket when possible.

For most applications, no transport configuration is necessary.

### WebSocket only

```swift
let manager = SocketManager(
    socketURL: URL(string: "https://example.com")!,
    config: [
        .forceWebsockets(true)
    ]
)
```

### Polling only

```swift
let manager = SocketManager(
    socketURL: URL(string: "https://example.com")!,
    config: [
        .forcePolling(true)
    ]
)
```

Do not enable both simultaneously.

### Explicit transport order

```swift
let manager = SocketManager(
    socketURL: URL(string: "https://example.com")!,
    config: [
        .transports([
            .websocket,
            .polling
        ]),
        .tryAllTransports(true)
    ]
)
```

tryAllTransports(true) lets the client try the next configured transport when the initial transport cannot establish the connection.

rememberUpgrade(true) can prefer WebSocket on later connections after WebSocket has previously succeeded.

## Common configuration

```swift
let manager = SocketManager(
    socketURL: URL(string: "https://example.com")!,
    config: [
        .path("/socket.io/"),
        .connectTimeout(20),
        .reconnects(true),
        .reconnectAttempts(-1),
        .reconnectWait(1),
        .reconnectWaitMax(5),
        .randomizationFactor(0.5),
        .log(false)
    ]
)
```

Frequently used options:

| Option | Purpose |
| --- | --- |
| .autoConnect(Bool) | Connect automatically when the manager/socket is created |
| .path(String) | Socket.IO HTTP endpoint |
| .connectParams(...) | Connection query parameters |
| .extraHeaders(...) | Additional HTTP headers |
| .connectTimeout(Double) | Engine.IO handshake timeout |
| .reconnects(Bool) | Enable/disable automatic reconnect |
| .reconnectAttempts(Int) | Reconnect attempt budget, -1 = unlimited |
| .reconnectWait(Int) | Initial reconnect delay |
| .reconnectWaitMax(Int) | Maximum reconnect delay |
| .randomizationFactor(Double) | Reconnect jitter |
| .ackTimeout(Double) | Default server acknowledgement timeout |
| .retries(Int) | Automatic acknowledgement-based retry count |
| .forceWebsockets(Bool) | WebSocket only |
| .forcePolling(Bool) | Polling only |
| .transports(...) | Ordered initial transport candidates |
| .tryAllTransports(Bool) | Fall back to another transport on opening failure |
| .rememberUpgrade(Bool) | Prefer WebSocket after previous WebSocket success |
| .withCredentials(Bool) | Accept and resend server cookies |
| .log(Bool) | Debug logging |
| .handleQueue(DispatchQueue) | Serial queue owning client interaction |

For the complete set, see SocketIOClientOption.

## Cookies

Automatic server cookie handling is opt-in:

```swift
let manager = SocketManager(
    socketURL: URL(string: "https://example.com")!,
    config: [
        .withCredentials(true)
    ]
)
```

When enabled, the engine maintains its own isolated cookie jar.

The application's shared cookie store is not used automatically.

Explicit .cookies(...) and explicit Cookie headers remain available when your application wants to control cookies directly.

## Threading and Swift concurrency

SocketManager and SocketIOClient use an explicit serial-queue ownership model.

The default handleQueue is:

```swift
DispatchQueue.main
```

All client interaction should happen on the manager's configured handleQueue.

If you provide your own queue:

```swift
let socketQueue = DispatchQueue(label: "com.example.socket")

let manager = SocketManager(
    socketURL: URL(string: "https://example.com")!,
    config: [
        .handleQueue(socketQueue)
    ]
)
```

it must be serial.

Event handlers execute on that queue.

Move UI work to the main queue when necessary:

```swift
socket.on("message") { data, _ in
    DispatchQueue.main.async {
        // Update UI
    }
}
```

SocketManager and SocketIOClient deliberately do not claim general Sendable semantics.

The async acknowledgement APIs safely bridge their returned wire values across the Swift concurrency boundary, but that does not make arbitrary concurrent mutation of the socket or its payload objects safe.

## TLS

For normal HTTPS/WSS servers, no TLS configuration is required.

```swift
let manager = SocketManager(
    socketURL: URL(string: "https://example.com")!
)
```

Apple's normal system trust validation is used for both polling and WebSocket.

### Certificate pinning

Use:

```swift
.security(
    .certificatePinning([
        certificateData
    ])
)
```

Certificates are DER-encoded.

### Private CA / private trust anchor

Use:

```swift
.security(
    .customTrust(
        anchors: [caCertificateData],
        pins: []
    )
)
```

Custom trust does not disable hostname, validity-period or chain checks.

For detailed TLS examples, see [Native transport and TLS configuration](Documentation/NativeWebSocketTransport.md#tls).

## Resource limits

Normal applications do not need to configure protocol limits.

The library nevertheless provides opt-in resource controls for environments that need explicit bounds.

There are three independent layers:

- SocketParserOptions — individual Socket.IO packets and binary reconstruction
- SocketWebSocketOptions — native WebSocket messages and pending WebSocket writes
- SocketBufferLimits — retained queues and pipeline backlogs

Example:

```swift
let manager = SocketManager(
    socketURL: URL(string: "https://example.com")!,
    config: [
        .parserOptions(
            SocketParserOptions(
                maximumBinaryPacketBytes: 1 << 20,
                maximumTextPacketBytes: 1 << 20
            )
        )
    ]
)
```

Pipeline-wide limits are intentionally unlimited by default where Socket.IO's JavaScript client also has no equivalent bound.

For applications processing untrusted or unusually high-volume input, see:

- SocketParserOptions
- SocketWebSocketOptions
- SocketBufferLimits

## Migrating from 16.x to 17

17.0 is a breaking release.

The major architectural change is the move from Starscream and historical compatibility modes to a native Swift 6 / Socket.IO 4 implementation.

The most important changes are:

- Socket.IO 4 / Engine.IO 4 only
- Swift 6.4 toolchain, Swift 6 language mode
- Starscream removed
- URLSessionWebSocketTask is the WebSocket backend
- .version(...) and SocketIOVersion removed
- .useCustomEngine(...) removed
- .compress removed
- .selfSigned(...) removed
- .enableSOCKSProxy(...) removed
- Reconnection events now follow modern JavaScript client semantics
- Encoding failures are reported instead of silently sending altered packets
- Modern acknowledgement timeout/retry APIs added
- Connection State Recovery added
- Transport selection/fallback behavior brought closer to the JavaScript client

Do not rely on a short README summary for a production migration.

Read:

- [Socket.IO 4 / Swift 6 migration guide](Documentation/SocketIO4Swift6Migration.md)

and:

- [Native URLSession transport migration](Documentation/NativeWebSocketTransport.md)

The complete release status and publication gates are tracked in:

- [Release 17](Documentation/Release17.md)

## JavaScript client parity

This project intentionally tracks the semantics of the official JavaScript socket.io-client where those semantics can be implemented safely and meaningfully on Apple's networking stack.

The test suite includes:

- Swift unit tests
- real Socket.IO server integration tests
- HTTP/HTTPS and WebSocket/WSS fixtures
- transport upgrade tests
- parser/encoder differential tests against a pinned official JavaScript implementation
- protocol wire checks
- strict Swift concurrency validation
- Apple SDK builds

Run the main suite with:

```sh
swift build
swift test
```

Additional validation is available through the scripts in scripts/.

Parity does not mean that every JavaScript browser/Node capability exists on Apple platforms.

Notable intentional boundaries include:

- WebTransport is unsupported
- JavaScript custom transport constructors do not have a direct native equivalent
- native compression controls are not exposed
- custom SOCKS routing is unsupported
- some Swift/platform APIs necessarily differ from the JavaScript API

For the detailed audit, supported mappings and known differences, see:

- [PARITY.md](PARITY.md)
- [Protocol parity review](Documentation/ProtocolParityReview.md)
- [JavaScript test inventory](Documentation/JavaScriptTestInventory.csv)

Always use the CI result for the exact commit you intend to ship rather than relying on historical test counts.

## Debugging

Enable logging during development:

```swift
let manager = SocketManager(
    socketURL: URL(string: "https://example.com")!,
    config: [
        .log(true)
    ]
)
```

Do not enable verbose socket logging in production when authentication data or sensitive application payloads may appear in logs.

When debugging connection problems, check these first:

- Is the endpoint actually a Socket.IO 4 server rather than a raw WebSocket server?
- Is the configured .path(...) identical to the server's Socket.IO path?
- Can HTTP long-polling reach the server?
- Can the server upgrade that session to WebSocket?
- Is a reverse proxy forwarding both polling and WebSocket traffic correctly?
- Is authentication expected in the Socket.IO auth payload, HTTP headers or query parameters?
- If forcing WebSocket, does the infrastructure allow direct WebSocket handshakes?
- Does the problem reproduce without .forceWebsockets(true)?

.connectError is generally the first event to inspect for failures while establishing a connection:

```swift
socket.on(clientEvent: .connectError) { data, _ in
    print(data)
}
```

For failures after an established connection, inspect both .error and .disconnect.

## Architecture

At a high level:

```text
SocketIOClient
      │
      │ namespace / events / acks
      ▼
SocketManager
      │
      │ Socket.IO protocol
      ▼
SocketEngine
      │
      │ Engine.IO 4
      ├───────────────┐
      ▼               ▼
HTTP Polling      WebSocket
(URLSession)      (URLSessionWebSocketTask)
```

A SocketManager owns the Engine.IO connection and can multiplex multiple SocketIOClient namespaces over it.

Most applications should interact only with:

- SocketManager
- SocketIOClient
- SocketIOClientOption

Direct Engine.IO classes are implementation-level APIs for specialized use and testing.

## Documentation

| Topic | Documentation |
| --- | --- |
| 17.0 release status | [Release17.md](Documentation/Release17.md) |
| Socket.IO 4 / Swift 6 migration | [SocketIO4Swift6Migration.md](Documentation/SocketIO4Swift6Migration.md) |
| Native WebSocket / TLS migration | [NativeWebSocketTransport.md](Documentation/NativeWebSocketTransport.md) |
| JavaScript parity | [PARITY.md](PARITY.md) |
| Detailed protocol review | [ProtocolParityReview.md](Documentation/ProtocolParityReview.md) |
| Changelog | [CHANGELOG.md](CHANGELOG.md) |

## License

Licensed under the MIT License.

This repository is based on the original
socketio/socket.io-client-swift
project and retains its applicable copyright and license notices.
