# Native WebSocket migration

## Runtime architecture

`SocketEngine` now instantiates `URLSessionWebSocketTransport` for every
WebSocket connection. The sole network backend is `URLSessionWebSocketTask`.
There is no Starscream adapter, dependency, runtime fallback or feature flag.
HTTP polling remains a separate URLSession. SocketManager and SocketIOClient
retain auth, namespaces, acks, reconnect backoff and state recovery.

The native adapter serializes complete text/binary batches, has one in-flight
send and receive, and ignores stale generation/session/task/operation callbacks.
Engine callbacks independently verify the current transport and attempt. HTTP
callbacks verify the concrete polling session before mutating state. Shutdown
is terminal once; old polling sessions and native tasks are explicitly retired.

An RFC6455 open callback does not mark Engine.IO connected. Only its `0{...}`
packet opens the engine. Engine.IO heartbeat/probe packets remain text, not
WebSocket control-frame pings. Upgrade still waits for both GET and POST to
settle. The native FIFO receives `5` before held polling/application packets.
An unsuccessful optional upgrade resumes healthy polling; failure on the active
WebSocket closes the engine and lets the existing manager decide about reconnect.

## Compatibility changes (major prerelease)

Normal SocketManager/SocketIOClient use does not require a backend selection.
Minimum deployment versions: iOS 15, macOS 12, tvOS 15, watchOS 8. These are
compile baselines, not a claim that every runtime/device has been exercised.

* `SocketEngine.ws`, `SocketEngineSpec.ws` and the Starscream event delegate
  entry point have been removed. The native transport is deliberately internal.
* `.security(...)` now takes `SocketTLSConfiguration`, not CertificatePinning.
* `.useCustomEngine(...)` is deprecated; both values select the sole native path.
* `.compress`, `.selfSigned(true)` and `.enableSOCKSProxy(true)` fail connection
  validation with an explicit error, before any request. No proxy request silently
  becomes a direct connection. False legacy booleans remain accepted.
* WebSocket send completions run once per complete packet after all local sends
  finish, or once on failure/cancellation. They are NOT server acknowledgements.
  A partially sent packet is never transparently replayed.
* Native `writable` reflects backpressure and is false while probing/upgrading.
  Its snapshot is synchronized onto engineQueue for reads from the manager queue.
* Invalid security-related dictionary values produce a connection error instead
  of silently dropping a failed type cast.

## TLS

Default `.security(.systemDefault)` leaves normal platform validation active.
Pinning adds a required matching DER leaf certificate to normal system trust:

```swift
let manager = SocketManager(socketURL: URL(string: "https://example.com")!, config: [
    .security(.certificatePinning([leafCertificateDER]))
])
```

A private PKI/development server uses explicit trust anchors, with optional leaf
pins. Hostname, expiry and certificate chain validation still apply:

```swift
.security(.customTrust(anchors: [privateCADER], pins: [serverLeafDER]))
```

Empty pin lists in certificatePinning, empty custom trust-anchor lists, malformed
DER and custom TLS policies on cleartext connections are rejected. Pinning is
identical for polling and WebSocket. External `.sessionDelegate` callbacks cover
non-server-trust authentication, redirects, invalidation, completion, metrics and
WebSocket open/close. Server-trust challenges belong exclusively to the TLS policy;
an external delegate cannot weaken it. Redirects cannot downgrade HTTPS/WSS to
HTTP/WS. Custom Apple TLS policies are explicitly unsupported on non-Apple builds.

## Resource limits

`.webSocketOptions(SocketWebSocketOptions(...))` configures complete incoming
message size and outgoing queue bounds. Defaults are 16 MiB per incoming message,
16 MiB of retained outgoing payload, 1024 batches and 4096 outgoing messages.
Zero-length messages still count. Every limit must be positive. Limits are
independent of Engine.IO's polling `maxPayload`. Queue overflow is surfaced as a
transport failure rather than silently dropping a nonvolatile application packet.

`.parserOptions(SocketParserOptions(...))` is a separate, Socket.IO-level policy
and is **not** part of these transport limits. `maximumAttachments` defaults to
10, matching JS `maxAttachments`; the byte limits are opt-in. The nesting-depth
limit remains enabled by default at 512 and may reject packets accepted by the
JavaScript parser. See the
"Deliberate deviations" section of `PARITY.md`.

## Distribution and release

SPM, CocoaPods and Xcode/Carthage definitions contain no Starscream dependency.
The podspec points to this fork's development branch with prerelease version
17.0.0-native.1. No release tag has been created. Before publishing, select and
create an immutable tag, change the podspec source to that tag, and revalidate.
Consumers testing this PR should pin its commit rather than a moving branch.

## Validation

`swift test` runs the complete existing suite plus native engine/TLS regressions.
`scripts/test-native-transport.sh` runs the deterministic transport tests without
third-party packages (the Linux path tests FoundationNetworking compilation, not
Apple runtime behavior). CI results must be tied to a specific commit.

Coverage added for WebSocket-open vs Engine.IO-open, multipart completion, EIO3
binary prefix, text heartbeat, stale callbacks, duplicate terminal events,
backpressure, failed upgrade fallback, the GET+POST barrier, option validation,
request header/cookie precedence and the manager's actual connect timeout.
Security tests cover explicit anchors, hostname/expiry/pin failure and real TLS
connections in polling and WebSocket modes. Existing real-server E2E suites retain
auth/acks/namespaces/recovery/parser and EIO3/EIO4 regression coverage.

No physical iPhone/Apple Watch runtime validation is implied by a passing macOS
suite or platform SDK build. Compression and SOCKS have not been declared
feature-equivalent; the migration deliberately rejects those legacy requests.
