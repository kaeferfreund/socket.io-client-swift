# Native WebSocket transport: foundation milestone

## Status and baseline

This is the first implementation milestone, **not an activated transport switch**.
`SocketEngine` still uses Starscream. No public option selects the new adapter yet.
Do not describe this branch as a completed Starscream removal or ship it as one.

Base: `feat/connect-timeout`, commit `adb686a93537fd4ea5bae66fe0a35ff5fa5238c0`.
This includes `6d35dff` and the subsequent test-brace correction. The manager,
connect-timeout/reconnect handling, polling upgrade barrier, maxPayload batching,
public API and existing configuration behavior are unchanged in this milestone.

## Implemented contract

`EngineWebSocketTransport` is internal, deliberately not a requirement of public
`SocketEngineSpec`. All methods, properties and callbacks are confined to the
provided serial engine queue. `connect()` is idempotent while connecting/open;
a reconnect requires terminating the old attempt first.

`URLSessionWebSocketTransport` implements:

- A whole-packet FIFO: submit the text header and all binary attachments in one
  `sendBatch`. Only one send is outstanding. Completion occurs exactly once after
  the entire batch, or once with failure; it is not a server acknowledgement.
- Exactly one receive operation, started only after WebSocket open. A WebSocket
  open event must NOT be forwarded as Engine.IO open without parsing its packet.
- Attempt generation plus connection identity checks. Per-operation tokens also
  reject duplicate/late callbacks within the same connection.
- A single terminal transition for receive/send/delegate errors, remote close,
  local close and abort. Pending batches fail once; partially sent batches are
  never replayed automatically.
- Explicit teardown; reentrant callbacks see detached old state. A weak delegate
  proxy avoids a session/delegate/transport retain cycle.
- A fresh native session/task for every attempt, independent of polling. The
  delegate proxy additionally validates the concrete session AND task identities.

`isWritable` means open with no pending batch. It is deliberately stricter than
"has a socket". The integration step must map this to `volatile` semantics.

## Limits and closing

Incoming complete-message default: 16 MiB (`maximumMessageSize`). This is NOT the
Engine.IO polling `maxPayload`. Outgoing defaults: 16 MiB retained payload bytes,
1024 pending batches and 4096 pending messages, including an in-flight batch.
UTF-8 byte counts, not character counts, determine text size. Message count also
bounds batches containing many empty messages. Rejected batches produce a local
`queueLimitExceeded` failure and are not partly sent. No automatic retry occurs.

An empty batch participates in FIFO completion order without a wire message.
`close` immediately stops accepting sends and fails unfinished batches; it does
not promise to flush pending application packets. An engine wishing to send an
Engine.IO close packet first must close from that batch's completion.

Local close supports Foundation's standard wire-sendable codes 1000, 1001, 1002,
1003, 1007, 1008, 1009, 1010 and 1011; reason length is at most 123 bytes. Invalid
codes/reasons cancel instead of transmitting an invalid frame. Application-defined
close codes are not supported by this initial internal contract.

## Security and compatibility boundary

The native initializer uses system TLS validation and preserves its prepared
URLRequest. It is guarded for iOS 13, macOS 10.15, tvOS 13 and watchOS 6; that is
compile availability, not a claim of tested runtime support on every platform.
The package's deployment floors are not raised in this additive milestone.

Custom pinning, session-delegate forwarding, self-signed policies, compression
parity and SOCKS routing are NOT migrated yet. They keep their existing behavior
because the existing engine remains active. Do not enable the new factory in
SocketEngine until unsupported configurations fail explicitly and trust policies
cover both polling and WebSocket, without a delegate bypass.

No Xcode project/Carthage integration or distribution dependency removal is
included yet. SwiftPM discovers these sources; the existing project build keeps
using the unchanged engine. The platform guards also allow the new sources to be
compiled by source-glob distributions without raising their current minimum OS.

## Verification

Run the existing full suite on macOS with `swift test`. The PR workflow now also
accepts `feat/connect-timeout` as a target branch.

For an offline, dependency-free check of just these added files:

```sh
./scripts/test-native-transport.sh
```

Initial local verification on Linux with Swift 6.2.1 in Swift 5 language mode:
22 deterministic XCTest cases passed, zero failures. They cover FIFO/multipart
ordering, once-only completions, send/receive failure, stale callbacks after
reconnect, duplicate callbacks, bounded queues, close/abort and reentrancy.
The native factory and Linux FoundationNetworking bridge were compiled as part
of this check. The tests use injected connections, NOT a real network server.
This does not establish Darwin runtime behavior, the full repository baseline,
TLS correctness or Socket.IO end-to-end compatibility.

## Remaining gates before activation/removal

1. Establish full macOS baseline and native real-server/Apple-platform tests.
2. Introduce the transitional Starscream adapter and wire the internal factory
   into concrete SocketEngine, without leaking it into SocketEngineSpec. Add
   manager connect-timeout and forced-WebSocket/Engine.IO-open regression tests.
3. Preserve Engine.IO heartbeat text packets, GET/POST upgrade barrier,
   upgrade-before-flush ordering and healthy-polling fallback after failed probe.
4. Migrate public send completions to once-per-packet behavior, audit callers,
   and implement common TLS/delegate/configuration validation for both transports.
5. Test EIO3/EIO4, headers/cookies, auth/namespaces/acks/recovery, upgrade failures,
   certificate/hostname/pinning failures and Apple simulator/device behavior.
6. Only then remove Starscream from public API, package/lockfiles, podspec,
   Carthage and Xcode project, and update versioning/migration documentation.
