# Socket.IO Client for Swift

A native Swift client for **Socket.IO 4.x** on iOS, macOS, tvOS and watchOS.
Built on Apple's `URLSession` and `URLSessionWebSocketTask`, with **no third-party Swift dependencies**.

HTTP long-polling, WebSocket upgrades, namespaces, binary events, acknowledgements,
async/await, ordered retries, reconnection and connection state recovery are included.
This is a **Socket.IO client**, not a general-purpose WebSocket library.

[Documentation](Documentation/README.md) · [Migration](Documentation/Guides/Migration.md) · [JavaScript parity](PARITY.md) · [Contributing](CONTRIBUTING.md)

## Requirements

| Component | Minimum / supported range |
| --- | --- |
| Toolchain | Swift 6.4, Swift 6 language mode; Xcode 27 for Apple SDKs |
| Platforms | iOS 15, macOS 12, tvOS 15, watchOS 9 |
| Server | Socket.IO 4.x, Engine.IO 4 |
| Transports | HTTP long-polling and WebSocket; no WebTransport |

See [compatibility](Documentation/Guides/Compatibility.md) for protocol boundaries
and [the package manifest](Package.swift) for deployment targets.

## Installation

**Swift Package Manager is the only supported installation method.**
In Xcode, choose **File → Add Package Dependencies**, enter the URL below and select
**Up to Next Major Version** from **17.0.0**. Add the **SocketIO** product to your app target.

```text
https://github.com/kaeferfreund/socket.io-client-swift.git
```

For a `Package.swift`, add the dependency and the product to the appropriate arrays:

```swift
// In Package.dependencies:
.package(
    url: "https://github.com/kaeferfreund/socket.io-client-swift.git",
    from: "17.0.0"
)

// In your target's dependencies:
.product(name: "SocketIO", package: "socket.io-client-swift")
```

A version requirement resolves a release, not this development branch. To evaluate
unreleased changes, explicitly select the reviewed branch or commit in Xcode/SPM.
The [17.0.0 release notes](Documentation/Release17.md) describe the published release.

## Quick start

Keep the manager alive, register listeners before connecting, and use the socket on
its serial `handleQueue`. The default queue is the main queue, so this example keeps
application-side access on `@MainActor`.

<!-- quick-start:begin -->
```swift
import Foundation
import SocketIO

@MainActor
final class RealtimeClient {
    private let manager: SocketManager
    private let socket: SocketIOClient

    init(url: URL) {
        manager = SocketManager(socketURL: url, config: [.log(false)])
        socket = manager.defaultSocket

        socket.on(clientEvent: .connect) { _, _ in
            print("Connected")
        }
        socket.on(clientEvent: .disconnect) { data, _ in
            print("Disconnected:", data)
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

    func connect() { socket.connect() }
    func disconnect() { socket.disconnect() }
    func send(_ message: String) { socket.emit("message", message) }
}
```
<!-- quick-start:end -->

Retain a `RealtimeClient` in your app, initialize it with your Socket.IO server URL,
and call `connect()` when ready. `autoConnect` is **false** by default.
The wrapper does not change the library's queue-ownership contract or make its objects Sendable.

CI compiles the marked example as an independent Swift Package consumer. See
[getting started](Documentation/Guides/GettingStarted.md) for the expanded walkthrough.

<!-- Preserve former README deep links beside their new guide destinations. -->
## Find the right guide

| Task | Guide |
| --- | --- |
| <a id="catch-all-listeners"></a><a id="custom-payload-types"></a><a id="receiving-events"></a><a id="sending-events"></a><a id="volatile-events"></a>Receive/send events, binary payloads, catch-all listeners | [Events and payloads](Documentation/Guides/Events.md) |
| <a id="acknowledgements"></a><a id="acknowledging-incoming-events"></a><a id="async--await"></a><a id="automatic-retries"></a><a id="callback"></a><a id="default-acknowledgement-timeout"></a><a id="legacy-acknowledgement-api"></a>Request acknowledgements, set timeouts, retry safely | [Acknowledgements and delivery](Documentation/Guides/Acknowledgements.md) |
| <a id="authentication"></a><a id="changing-authenticated-users"></a><a id="connection-state-recovery"></a><a id="dynamic-authentication"></a><a id="http-headers"></a><a id="namespaces"></a><a id="reconnection"></a><a id="static-connection-payload"></a>Authenticate, use namespaces, reconnect and recover state | [Connection lifecycle](Documentation/Guides/Connections.md) |
| <a id="certificate-pinning"></a><a id="common-configuration"></a><a id="cookies"></a><a id="explicit-transport-order"></a><a id="polling-only"></a><a id="private-ca--private-trust-anchor"></a><a id="resource-limits"></a><a id="threading-and-swift-concurrency"></a><a id="tls"></a><a id="transport-configuration"></a><a id="websocket-only"></a>Configure transports, queues, cookies, TLS and limits | [Configuration and concurrency](Documentation/Guides/Configuration.md) |
| <a id="migrating-from-16x-to-17"></a><a id="breaking-changes-in-1700"></a>Upgrade an existing application | [Migration overview](Documentation/Guides/Migration.md) |
| <a id="debugging"></a>Diagnose connection or event problems | [Troubleshooting](Documentation/Guides/Troubleshooting.md) |
| <a id="architecture"></a><a id="javascript-client-parity"></a>Build, test or contribute to the library | [Contributing](CONTRIBUTING.md) |

<a id="at-a-glance"></a><a id="documentation"></a><a id="transport-support"></a>
The [documentation index](Documentation/README.md) also includes architecture,
release procedures, the API source reference and the complete retained review evidence.

## Important boundaries

Recovery requires a configured Socket.IO 4.6+ server and is not guaranteed. Retries
can deliver an event more than once, so deduplicate non-idempotent operations on the server.
WebTransport, custom JavaScript transport constructors, compression switches and
custom SOCKS routing are not exposed by this native client.
See [PARITY.md](PARITY.md) for the supported scope and explicit exclusions.

## License

Licensed under the MIT License. See [LICENSE](LICENSE) for the complete retained notices.

This repository is based on the original
socketio/socket.io-client-swift
project and retains its applicable copyright and license notices.
