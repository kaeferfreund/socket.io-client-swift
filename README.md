> **Native transport prerelease:** This fork now uses Apple's `URLSessionWebSocketTask` directly. There is no Starscream dependency or runtime fallback. Requires iOS 13 / macOS 10.15 / tvOS 13 / watchOS 6. See [migration and compatibility notes](Documentation/NativeWebSocketTransport.md) before adopting this major prerelease.

[![Swift validation](https://github.com/kaeferfreund/socket.io-client-swift/actions/workflows/swift.yml/badge.svg?branch=feat/native-urlsession-transport)](https://github.com/kaeferfreund/socket.io-client-swift/actions/workflows/swift.yml)

# Socket.IO-Client-Swift
Socket.IO-client for iOS/OS X.

## Example
```swift
import SocketIO

let manager = SocketManager(socketURL: URL(string: "http://localhost:8080")!, config: [.log(true)])
let socket = manager.defaultSocket

socket.on(clientEvent: .connect) {data, ack in
    print("socket connected")
}

socket.on("currentAmount") {data, ack in
    guard let cur = data[0] as? Double else { return }
    
    socket.emitWithAck("canUpdate", cur).timingOut(after: 0) {data in
        if data.first as? String ?? "passed" == SocketAckStatus.noAck {
            // Handle ack timeout 
        }

        socket.emit("update", ["amount": cur + 2.50])
    }

    ack.with("Got your currentAmount", "dude")
}

socket.connect()
```

## Features
- Supports Socket.IO server 2.0+/3.0+/4.0+ (see the [compatibility table](https://nuclearace.github.io/Socket.IO-Client-Swift/Compatibility.html))
- Supports Binary
- Supports Polling and WebSockets
- Supports TLS/SSL

### Auto-connect on `init`

```swift
let manager = SocketManager(socketURL: url, config: [.autoConnect(true)])
manager.defaultSocket.on(clientEvent: .connect) { _, _ in
    print("default socket connected")
}
```

Pass `.autoConnect(true)` to make `SocketManager.init` call `defaultSocket.connect()` and open the engine before returning. Defaults to `false` (Swift back-compat — JS reference defaults to `true`). Only the default namespace is auto-joined; namespaces created later via `manager.socket(forNamespace:)` still require explicit `socket.connect()`. Engine I/O begins synchronously inside `init`, matching JS.

### Connection State Recovery
When using a `.version(.three)` manager (the client/protocol mode for Socket.IO 3.x/4.x servers) against a Socket.IO 4.x server with `connectionStateRecovery` enabled, an abrupt transport drop followed by a reconnect can resume the prior session. If the server reports the session as recovered, missed server-to-client events replay on existing handlers and your event listeners fire as if the transport had never dropped.

Recovery is only attempted by v3 managers. v2 managers ignore the feature entirely.

#### Detecting recovery
The `connect` client event payload includes `recovered: Bool`. The same flag is also exposed as `socket.recovered` after the CONNECT ack.

```swift
socket.on(clientEvent: .connect) { data, _ in
    guard let payload = data.dropFirst().first as? [String: Any] else { return }

    if payload["recovered"] as? Bool == true {
        // Previous session resumed; missed events have replayed on existing handlers
    } else {
        // Fresh session; re-issue any subscription state the server needs
    }
}
```

#### How it works
- On every successful CONNECT ack the client stores the server-assigned private session id (`pid`) and, for each subsequent event, captures the server's trailing `String` offset argument (bounded to 256 UTF-8 bytes via `SocketIOClient.socketStateRecoveryMaxOffsetBytes`; oversized offsets are dropped with a log line).
- When the client reconnects it merges `{pid, offset}` into the CONNECT payload. Keys in your own `connectPayload` win on collision with the reserved `pid` / `offset` keys (a log line is emitted if this happens), matching `socket.io-client` JS.
- Event packets that arrive on the wire *before* the reconnect CONNECT ack are buffered and flushed in order once the ack arrives, so no replayed event is lost to the connect race.

#### Identity changes
In-memory recovery state is tied to the socket, not to the authenticated user. When the logged-in identity changes, call `clearRecoveryState()` before reconnecting so the next CONNECT does not resume the previous user's stream:

```swift
socket.clearRecoveryState()
socket.disconnect()
socket.connect(withPayload: ["token": newToken])
```

`clearRecoveryState()` resets `_pid`, `_lastOffset`, `recovered`, and any buffered replay packets. It is an *in-memory* clear only — it does not fence packets already dispatched to handlers, nor packets the server will deliver on the still-live transport before the next CONNECT ack. For a hard identity boundary, also `disconnect()` and reconnect (or create a fresh socket).

As a Swift-only side effect (no JS counterpart), `clearRecoveryState()` fails any outstanding `socket.timeout(after:).emit(...)` callbacks with `SocketAckError.disconnected`, since a successor session would never deliver an ack for an id issued by the prior session.

If you override `disconnect()` in a subclass and want auto-clear, call `clearRecoveryState()` **before** `super.disconnect()` — the `.disconnect` client event fires synchronously from super, and any observer that reconnects from that callback would otherwise send stale `pid`/`offset`.

## FAQS
Checkout the [FAQs](https://nuclearace.github.io/Socket.IO-Client-Swift/faq.html) for commonly asked questions.


Checkout the [12to13](https://nuclearace.github.io/Socket.IO-Client-Swift/12to13.html) guide for migrating to v13+ from v12 below.

Checkout the [15to16](https://nuclearace.github.io/Socket.IO-Client-Swift/15to16.html) guide for migrating to v16+ from v15.

## Installation

This native prerelease requires iOS 13, macOS 10.15, tvOS 13 or watchOS 6,
and a Swift 5-compatible toolchain supporting the package's Swift tools 5.4
manifest. The checked-in framework project builds against all four Apple SDKs.
Device/runtime support, particularly watchOS, must still be exercised by adopters.

Use **this fork**, not an upstream 16.x dependency. No native release tag has
been published yet. The examples below select the development branch; pin the
reviewed commit in application lockfiles or dependency declarations before use.

### Swift Package Manager

Add this dependency to your package:

```swift
.package(
    url: "https://github.com/kaeferfreund/socket.io-client-swift.git",
    .branch("feat/native-urlsession-transport")
)
```

Add `.product(name: "SocketIO", package: "socket.io-client-swift")` to your
target dependencies, and ensure your package declares the appropriate deployment
minimum. In Xcode, add the same repository URL and select this branch or a
reviewed commit. Import the module using `import SocketIO`.

### Carthage

Use this fork in the application's `Cartfile`:

```text
github "kaeferfreund/socket.io-client-swift" "feat/native-urlsession-transport"
```

Build with your supported Carthage/Xcode toolchain. Add **only SocketIO** to the
application. Remove any former Starscream linkage, copy-frameworks entry or
embedded framework that no other dependency needs. The repository's `Cartfile`
has no transitive framework dependencies.

### CocoaPods

Select the fork explicitly instead of the upstream published pod:

```ruby
use_frameworks!

target 'YourApp' do
    pod 'Socket.IO-Client-Swift',
        :git => 'https://github.com/kaeferfreund/socket.io-client-swift.git',
        :branch => 'feat/native-urlsession-transport'
end
```

Run `pod install` and import `SocketIO` from Swift. The prerelease podspec and
SPM manifest use the same deployment minimums. The fork has not been published
to the CocoaPods registry. The API is Swift-only; Objective-C integration is
not supported.

## Native transport configuration and documentation

Read [NativeWebSocketTransport.md](Documentation/NativeWebSocketTransport.md)
for the actual runtime architecture, TLS migration, resource limits and breaking
changes. No configuration flag is needed to activate the native backend.
Remove `.compress` and `.useCustomEngine(...)` from normal configurations. Migrate
custom `.security(...)` values to `SocketTLSConfiguration`; unsupported legacy
SOCKS and trust-all requests are explicitly rejected rather than ignored.

### Parser limits (`.parserOptions`)

The defaults decode everything the JavaScript client decodes: only
`maximumAttachments` (10) is a limit JS itself has, and the byte limits are
unlimited. Opt into hardening against a hostile peer by passing your own
limits:

```swift
let manager = SocketManager(socketURL: url, config: [
    .parserOptions(SocketParserOptions(maximumTextPacketBytes: 1 << 20,
                                       maximumBinaryPacketBytes: 1 << 20))
])
```

`maximumNestingDepth` (default 512, hard cap 1024) is the one limit that is on
by default and a deliberate deviation from JS: `JSONSerialization` can overflow
the stack on deeply nested input. An invalid option set is rejected before
connecting. See the "Deliberate deviations" section of
[PARITY.md](PARITY.md).

The checked-in generated `docs/` HTML and the
[upstream API reference](https://nuclearace.github.io/Socket.IO-Client-Swift/index.html)
are **historical 16.x documentation**, not an API contract for this prerelease.
In particular, their concrete `ws`, pinning and compression examples do not
apply. Use this fork's Swift source documentation and migration guide for the
changed APIs; generated HTML will need regeneration for a tagged release.

## Validation

`swift test` executes the complete unit and real-server suite. Node is required
for Socket.IO fixture servers, and OpenSSL generates temporary TLS certificates.
No roots are installed in the system trust store. `scripts/test-native-transport.sh`
provides an isolated transport regression suite. On macOS,
`scripts/test-native-distributions.sh` verifies dependency removal and builds the
framework with the macOS, iOS Simulator, tvOS Simulator and watchOS Simulator SDKs.
The CI runs these checks without writing source files or requiring a migration
step before building.

## Detailed Example
A more detailed example can be found [here](https://github.com/nuclearace/socket.io-client-swift-example)

An example using the Swift Package Manager can be found [here](https://github.com/nuclearace/socket.io-client-swift-spm-example)

## License
MIT
