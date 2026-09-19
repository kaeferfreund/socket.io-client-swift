<a id="socketio-client-for-swift"></a>
<h1 align="center">Socket.IO Client for Swift</h1>

<p align="center">
  <strong>Real-time events. Native Apple networking.</strong><br>
  Socket.IO 4 for iOS, macOS, tvOS and watchOS, built on URLSession.<br>
  No third-party Swift dependencies.
</p>

<p align="center">
  <a href="https://github.com/kaeferfreund/socket.io-client-swift/actions/workflows/swift.yml?query=branch%3Amaster"><img src="https://github.com/kaeferfreund/socket.io-client-swift/actions/workflows/swift.yml/badge.svg?branch=master" alt="CI on master"></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&amp;logoColor=white" alt="Swift 6.4 toolchain"></a>
  <a href="#installation"><img src="https://img.shields.io/badge/SPM-only-2E7D32" alt="Swift Package Manager only"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-0969DA" alt="MIT License"></a>
</p>

<p align="center">
  <a href="#quick-start"><strong>Quick start</strong></a> ·
  <a href="Documentation/README.md">Documentation</a> ·
  <a href="#why-this-fork">Why this fork?</a> ·
  <a href="Documentation/Guides/Migration.md">Migration</a> ·
  <a href="PARITY.md">JavaScript parity</a>
</p>

---

Send and receive named events, exchange binary payloads, request acknowledgements
and reconnect after interruptions. HTTP long-polling and WebSocket upgrades are
handled by the client; your application works with `SocketManager` and `SocketIOClient`.

**This is a Socket.IO client, not a general-purpose WebSocket library.** It needs a
Socket.IO server. This repository is an independent community fork, not an official
Socket.IO release.

## Why this fork?

The [official Swift client](https://github.com/socketio/socket.io-client-swift) is
the foundation of this project and **already supports Socket.IO 4**. The reason for
this fork is more specific: our target stack needs native Apple transports, an
explicit Swift 6 language-mode baseline, and additional modern client behavior
that the inspected upstream implementation does not provide together.

| What we need | What this fork provides |
| --- | --- |
| **Native networking without Starscream** | `URLSession` for polling and `URLSessionWebSocketTask` for WebSocket, with no third-party Swift dependencies. |
| **A Swift 6 baseline** | Swift 6.4 tooling, Swift 6 language mode and concurrency checks in CI, with explicit queue-ownership rules. |
| **Recovery and acknowledgement control** | Connection state recovery, dynamic authentication, ordered retries and cancellable async/await acknowledgements. |
| **Reviewable compatibility evidence** | Native regression tests, pinned JavaScript test mappings and parser comparisons, with explicit scope and exclusions. |

These are requirements for this fork, not a claim that every application must
leave upstream. See **[the source-linked comparison and trade-offs](Documentation/Guides/WhyThisFork.md)**
for the inspected revisions, what is shared, and when the official client may
still fit better. Existing applications should read the [17.x migration guide](Documentation/Guides/Migration.md).

## Requirements

| Component | Minimum / supported range |
| --- | --- |
| Toolchain | Swift 6.4, **Swift 6 language mode**; Xcode 27 for Apple SDKs |
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

<details>
<summary><strong>Using a Package.swift manifest instead?</strong></summary>

Add the dependency and the product to the appropriate arrays:

```swift
// In Package.dependencies:
.package(
    url: "https://github.com/kaeferfreund/socket.io-client-swift.git",
    from: "17.0.0"
)

// In your target's dependencies:
.product(name: "SocketIO", package: "socket.io-client-swift")
```

</details>

A version requirement installs a **published release**, not the development branch
you are viewing. To evaluate unreleased changes, explicitly select the reviewed
branch or commit in Xcode/SPM. The [17.0.0 release notes](Documentation/Release17.md)
describe the published release.

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

CI compiles and initializes this example as an independent Swift Package consumer.
The [getting-started guide](Documentation/Guides/GettingStarted.md) expands the walkthrough;
the [acknowledgement guide](Documentation/Guides/Acknowledgements.md) covers callbacks,
async/await, timeouts and retries.

<!-- Preserve former README deep links beside their new guide destinations. -->
## Find the right guide

| Task | Guide |
| --- | --- |
| Compare this fork with the official Swift client | [Why this fork?](Documentation/Guides/WhyThisFork.md) |
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

## Validation you can inspect

The [Swift workflow](.github/workflows/swift.yml) runs the native regression suite,
checks mapped JavaScript contracts against actual passed tests, and exercises
Thread Sanitizer, strict concurrency, four Apple SDK builds and an independent
SPM consumer. It also checks documentation links and compiles the README example.

The badge above reports **`master`**, not whichever branch or release you are
reading. Check [Actions](https://github.com/kaeferfreund/socket.io-client-swift/actions)
for the exact revision you plan to use. [PARITY.md](PARITY.md) separates supported
behavior from API/platform differences and unsupported features. Passing tests or
high line coverage do **not** establish universal JavaScript parity, and Apple SDK
builds do not replace physical-device runtime validation.

## Important boundaries

Recovery requires a configured Socket.IO 4.6+ server and is not guaranteed. Retries
can deliver an event more than once, so deduplicate non-idempotent operations on the server.
WebTransport, custom JavaScript transport constructors, compression switches and
custom SOCKS routing are not exposed by this native client.
See [PARITY.md](PARITY.md) for the supported scope and explicit exclusions.

## Contributing

Bug reports, focused fixes and documentation improvements are welcome. Start with
[CONTRIBUTING.md](CONTRIBUTING.md) for the workflow and
[the testing guide](Documentation/Development/Testing.md) for reproducible checks.
Please report fork-specific issues in [this repository](https://github.com/kaeferfreund/socket.io-client-swift/issues).

## Credits

Forked from [howardsun-tw/socket.io-client-swift](https://github.com/howardsun-tw/socket.io-client-swift),
based on [socketio/socket.io-client-swift](https://github.com/socketio/socket.io-client-swift).
Thanks to Erik Little and the upstream contributors for the original client and
the work this continuation builds on. Applicable copyright and license notices
are retained in [LICENSE](LICENSE).

## License

[MIT](LICENSE). Provided **as is**, subject to the terms and limitations in the license.
