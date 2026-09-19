# Why this fork?

[Documentation index](../README.md) · [Project overview](../../README.md) · [Migration](Migration.md)

## The short explanation

We need the familiar `SocketManager` / `SocketIOClient` model with native Apple
networking, a Swift 6 language-mode baseline, and client-side recovery, retry and
async acknowledgement behavior. The official Swift client supplies the foundation,
but the inspected upstream implementation does not supply that combination.
This fork maintains those changes together rather than requiring applications to
carry their own transport and lifecycle patches.

**The official Swift client already supports Socket.IO 4 and Swift Package Manager.**
Neither is, by itself, a reason to fork. The comparison below describes concrete
implementation differences, not a claim that upstream is unusable, abandoned or
unsafe. This is an independent community continuation, not an official Socket.IO
release or an endorsement by the upstream maintainers.

## What was compared

Reviewed on **2026-09-19** against these source snapshots:

- Official Swift client: [`42da871`](https://github.com/socketio/socket.io-client-swift/tree/42da871d9369f290d6ec4930636c40672143905b), the upstream `master` head inspected for this review.
- This fork: [`f66c451`](https://github.com/kaeferfreund/socket.io-client-swift/tree/f66c45180cc5903f0bdc9314d8206c769b7d2bf5), before this documentation-only revision.

The references below are pinned so later upstream changes do not silently alter
what the comparison describes. They are not a prediction about future releases.
The separate [JavaScript parity audit](../../PARITY.md) compares a pinned
`socketio/socket.io` JavaScript implementation, not the official Swift repository.

## The differences that matter

| Area | Official Swift snapshot | This fork's snapshot |
| --- | --- | --- |
| Server compatibility | Advertises Socket.IO 2.x, 3.x and 4.x support. [README][upstream-readme] | Supports and tests Socket.IO 4.x / Engine.IO 4 only. [Migration][fork-migration] |
| WebSocket implementation | Declares a Starscream dependency starting at 4.0.8. [Manifest][upstream-package] | Uses `URLSessionWebSocketTask` and a separate polling `URLSession`; no third-party Swift dependencies. [Transport][fork-transport], [manifest][fork-package] |
| Swift baseline | Declares tools version 5.4; no explicit Swift 6 language-mode setting in the manifest. [Manifest][upstream-package] | Declares tools version 6.4 and `swiftLanguageModes: [.v6]`. [Manifest][fork-package] |
| Acknowledgements and delivery | Callback-based `emitWithAck(...).timingOut(after:)`; no ordered retry queue or async acknowledgement entry point in the inspected client. [Client][upstream-client] | Callback, async and legacy acknowledgement entry points, ordered retries and cancellation handling. [Client][fork-client], [async emitter][fork-emitter] |
| Session recovery and authentication | Connect payload handling; no recovery `pid`/offset state or per-CONNECT auth-provider API in the inspected client. [Client][upstream-client] | Recovery state and `recovered`, plus a dynamic auth provider for initial connection and reconnects. [Client][fork-client] |

A tools-version declaration is **not** a maximum supported compiler version.
The upstream manifest alone does not prove that an application using a newer
compiler cannot build the package. Our requirement is that the library itself
uses Swift 6 language mode and is checked accordingly. That also does not make
`SocketManager` or `SocketIOClient` generally thread-safe or `Sendable`; access
still belongs to the manager's serial `handleQueue`.

## What this means for an application

**Native transport ownership.** Applications that require Apple's URLSession
networking stack do not need to retain Starscream solely for this client. This
changes transport configuration too: review the [native transport migration](../NativeWebSocketTransport.md)
for TLS, cookies and removed settings. Dependency removal is an architectural
choice, not a measured performance advantage or a security certification.

**Recovery and delivery are explicit.** The [connection guide](Connections.md)
explains recovery and dynamic authentication; the [acknowledgement guide](Acknowledgements.md)
explains timeouts, retries and cancellation. Recovery needs server-side support
and can fail. Retry delivery can produce duplicates, so application protocols
must handle deduplication where necessary. Neither feature provides an
unconditional delivery guarantee.

**Compatibility claims have a defined scope.** This fork's [CI workflow][fork-ci]
checks native regressions, mapped JavaScript test assertions, parser comparisons,
concurrency and package builds. [PARITY.md](../../PARITY.md) records exclusions
and deliberate differences. An SDK build is not a device test, line coverage is
not semantic equivalence, and executing upstream JavaScript tests alone would
not validate the Swift implementation.

## When staying with upstream makes sense

An existing application may already be well served by the official client's
transport, API and supported platform range. Older toolchains or legacy server
requirements can also make this fork's narrower support policy unsuitable.
Check the exact release requirements rather than migrating just because a fork
exists.

This fork requires Swift 6.4 / Xcode 27 and iOS 15, macOS 12, tvOS 15 or watchOS 9.
It does not offer WebTransport, JavaScript compression controls or custom
JavaScript transport constructors. Version 17 removes legacy APIs and changes
some reconnect and acknowledgement behavior; **changing the package URL is not
a complete migration plan**. Start with [Migration](Migration.md).

Published releases and development branches are separate choices. Follow
[Getting started](GettingStarted.md) for the published 17.x package, select a
reviewed revision explicitly for unreleased changes, and inspect CI for that
exact revision. Physical-device runtime validation is not established by the
recorded SDK builds.

## Provenance

The direct parent is [howardsun-tw/socket.io-client-swift](https://github.com/howardsun-tw/socket.io-client-swift),
which derives from [socketio/socket.io-client-swift](https://github.com/socketio/socket.io-client-swift).
This project builds on Erik Little's original client and the upstream
contributors' work. See [LICENSE](../../LICENSE) for applicable terms and notices.

[upstream-readme]: https://github.com/socketio/socket.io-client-swift/blob/42da871d9369f290d6ec4930636c40672143905b/README.md
[upstream-package]: https://github.com/socketio/socket.io-client-swift/blob/42da871d9369f290d6ec4930636c40672143905b/Package.swift
[upstream-client]: https://github.com/socketio/socket.io-client-swift/blob/42da871d9369f290d6ec4930636c40672143905b/Source/SocketIO/Client/SocketIOClient.swift
[fork-package]: https://github.com/kaeferfreund/socket.io-client-swift/blob/f66c45180cc5903f0bdc9314d8206c769b7d2bf5/Package.swift
[fork-client]: https://github.com/kaeferfreund/socket.io-client-swift/blob/f66c45180cc5903f0bdc9314d8206c769b7d2bf5/Source/SocketIO/Client/SocketIOClient.swift
[fork-emitter]: https://github.com/kaeferfreund/socket.io-client-swift/blob/f66c45180cc5903f0bdc9314d8206c769b7d2bf5/Source/SocketIO/Ack/SocketTimedEmitter.swift
[fork-transport]: https://github.com/kaeferfreund/socket.io-client-swift/blob/f66c45180cc5903f0bdc9314d8206c769b7d2bf5/Documentation/NativeWebSocketTransport.md
[fork-migration]: https://github.com/kaeferfreund/socket.io-client-swift/blob/f66c45180cc5903f0bdc9314d8206c769b7d2bf5/Documentation/SocketIO4Swift6Migration.md
[fork-ci]: https://github.com/kaeferfreund/socket.io-client-swift/blob/f66c45180cc5903f0bdc9314d8206c769b7d2bf5/.github/workflows/swift.yml
