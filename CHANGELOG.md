## 17.0.0-native.1 (unreleased)

- Replace the WebSocket backend with URLSessionWebSocketTask; remove the third-party dependency from every build definition.
- Integrate ordered native sends, once-only completion/close handling, stale-callback isolation and real writable/backpressure state.
- Preserve the polling GET+POST upgrade barrier, maxPayload batching, manager timeouts and reconnect behavior.
- Add shared explicit TLS policy, certificate pinning/private anchors and fail-closed configuration migration.
- Breaking: remove concrete `ws` API; migrate `security`; reject unsupported compression, trust-all and SOCKS options. See `Documentation/NativeWebSocketTransport.md`.

# Unreleased

## Fixes

- An undecodable packet now closes the engine with reason "parse error" (sockets get `.disconnect("parse error")`, reconnection starts if enabled) instead of being dropped silently; JS-aligned with `Manager.ondata`/`onclose` in `socket.io-client/lib/manager.ts`. Found by porting the JS client's own scenario "should close the engine upon decoding exception".
- Every long-polling request (handshake GET, polls, POSTs) now carries a unique `t=` cache-busting query parameter, JS-aligned with `Polling.uri()` in engine.io-client; the WebSocket URL carries it only when explicitly enabled. New options `.timestampRequests(Bool)` / `.timestampParam(String)` with JS defaults (polling stamped, WebSocket not; param name `"t"`). Previously the client relied on `URLRequest.cachePolicy = .reloadIgnoringLocalCacheData`, which only bypasses the local cache — proxies, CDNs, and corporate caches in between could still serve a stale response to a long-poll.
- A CONNECT packet without a `sid` on a `.three` manager now fires `.connectError` with the JS message about reaching a Socket.IO server in v2.x instead of connecting, JS-aligned with `onpacket` in `socket.io-client/lib/socket.ts`; `.two` managers are unaffected since the v2 protocol carries no sid. Found by porting the JS client's own scenario "should emit a connect_error event when reaching a Socket.IO server in v2.x".
- A namespace the server refused (CONNECT_ERROR) is no longer rejoined on the next engine open. `SocketManager` re-sent CONNECT for any socket still in `.connecting`, so a server rejecting an expired token was asked again on every reconnect, indefinitely. The rejoin now requires `socket.active`, which is what that flag was introduced for. JS `destroy()`s the socket on CONNECT_ERROR and waits for an explicit `connect()`. Found by porting the JS client's own `should not try to reconnect after a middleware failure`.
- Emits made while disconnected are no longer lost: they are buffered and flushed in order on the next CONNECT, with the outgoing any-listeners firing at flush time as they do in JS `emitBuffered()`. Acks behave as in JS `_clearAcks`: an ack whose packet is still buffered survives the disconnect, while a timed-out ack drops its packet from the buffer so a reconnect does not deliver an emit the caller already gave up on. The legacy `emitWithAck(...).timingOut(after:)` path keeps its documented behavior. `clearRecoveryState()` discards the buffer instead of keeping it: that is the identity-swap path, where delivering the previous user's queued events into the successor session would leak them across identities.
- The polling transport is paused before the WebSocket upgrade. Previously only the outstanding long-poll was awaited; a POST still on the wire reached the server after it had switched transports, which answers it with HTTP 400 and drops the packet without surfacing an error. JS-aligned with `pause()` in engine.io-client's polling transport.
- Polling POSTs now respect the `maxPayload` the server advertises in the handshake. Previously the whole queue went out in one request; above the limit the server answers HTTP 413 and discards every packet it carried, while the session stays open. The batch is now cut at the limit and the rest follows in the next POST, JS-aligned with `getWritablePackets()` in engine.io-client. A single packet larger than the limit is still sent on its own, as in the reference client. engine.io v3 is unaffected — those servers advertise no limit.
- New `SocketEnginePollable.maxPayload: Int?` — additive protocol requirement with a `nil` default, so existing conformers keep the previous unbounded behavior.
- With `.autoConnect(true)`, `socket(forNamespace:)` now re-connects a cached socket that is no longer active, JS-aligned with `Manager.socket()`; without `autoConnect` nothing changes.
- After the reconnect budget is exhausted, a later `connect()` starts a fresh reconnection cycle with a fresh budget (previously the manager stayed flagged as reconnecting forever). JS-aligned with `Manager.reconnect()`; found via the JS scenario "should attempt reconnects after a failed reconnect".
- The engine now ignores responses and packets that belong to a previous session and reports its close only once; previously a handshake completing after a timeout-close re-opened the reused engine with a stale sid, so the manager saw two "opened" sessions and started a spurious reconnect cycle (JS-aligned: engine.io-client uses a fresh transport per attempt). Found via the JS scenario "should attempt reconnects after a failed reconnect".

## Features

- New `.ackTimeout(Double)` option / `SocketManager.ackTimeout` (seconds, default `nil`) plus new `SocketIOClient.emit(_:_:ack:)` / `emit(_:with:ack:)` overloads with err-first callbacks, JS-aligned with `_registerAckCallback` in `socket.io-client/lib/socket.ts`. When the default is set, the emit behaves exactly like `timeout(after: ackTimeout).emit(...)`: the callback fires with `SocketAckError.timeout` when the timer fires (and the packet is dropped from the send buffer) and with `SocketAckError.disconnected` on disconnect unless the packet is still buffered. When unset, the callback is a plain ack registered with no timer — it fires as `ack(nil, data)` on the server ack and is never called with an error, not on disconnect either.
- New `.connectTimeout(Double)` / `SocketManager.connectTimeout` (default 20 s, `.infinity` disables), JS-aligned with `Manager.open()` in `socket.io-client/lib/manager.ts`. If the engine.io handshake has not completed in time, every socket gets `.connectError` with `"timeout"`, the engine is closed, and the reconnect loop starts if enabled.
- New `SocketClientEvent.connectError` (fires as `"connect_error"`), JS-aligned with `connect_error` in `socket.io-client/lib/socket.ts`. It replaces `.error` for connection/join failures: a server CONNECT_ERROR refusal, a v2.x server detected on a `.three` manager, an engine/transport error while the socket is not connected (an error under an established connection keeps firing `.error`), and the connection timeout. Payload-serialization and v2-auth-bypass reports keep firing `.error` — those are client-side failures, not connection refusals.
- Connection State Recovery support for `.version(.three)` managers talking to Socket.IO 4.x servers with `connectionStateRecovery` enabled. `SocketIOClient` exposes `recovered: Bool` and the `.connect` event payload carries a `"recovered": Bool` key. After an abrupt transport drop, the client can resume the prior session when the server still has recovery state available.
- New `SocketIOClient.clearRecoveryState()` method. Call it before reconnecting on an identity change to prevent resuming a prior user's session.
- New `SocketIOClientOption.autoConnect(Bool)`. When `true`, `SocketManager.init` calls `defaultSocket.connect()` and opens the engine before returning, so the default namespace socket is auto-joined. Default `false` preserves existing behavior. JS `Manager` defaults to `true`; Swift inverts to avoid silently changing legacy callers. Only the `defaultSocket` is auto-CONNECTed; non-default namespaces created via `manager.socket(forNamespace:)` still require explicit `socket.connect()`. Engine I/O begins synchronously inside `init`, matching JS.
- Reserved event names (`connect`, `connect_error`, `disconnect`, `disconnecting`) emitted by user code are now intercepted at the internal emit funnel: a `.error` client-event fires and the packet is dropped before it reaches the wire. JS-aligned with `socket.io-client/lib/socket.ts` `emit()` throw — Swift surfaces via `.error` because the emit signature cannot throw without breaking back-compat. DEBUG builds (outside XCTest) additionally trigger `assertionFailure` so misuse surfaces loudly during development. `SocketRawView.emit` is also covered.
- New `SocketIOClient.active: Bool` lifecycle property. Mirrors JS `socket.active` (`!!this.subs`): flipped `true` at the start of `connect()` and `false` only inside the user-facing `disconnect()`. Survives engine-close + reconnect cycles (`didDisconnect(reason:)` does not clear it). Distinct from `socket.status.active` which reports the current status enum's liveness.
- `SocketIOClient.addAnyListener(_:)` / `prependAnyListener(_:)` / `removeAnyListener(id:)` / `removeAllAnyListeners()` / `anyListenerCount` — multi-listener catch-all family matching JS `socket.onAny` API. Returns `UUID` handle for removal (closures lack identity in Swift). Listeners fire in registration order after the legacy single-handler `onAny(_:)`. Mutators serialize via `handleQueue.async`; dispatch iterates a snapshot so self-removal mid-dispatch is safe.
- `SocketIOClient.addAnyOutgoingListener(_:)` / `prependAnyOutgoingListener(_:)` / `removeAnyOutgoingListener(id:)` / `removeAllAnyOutgoingListeners()` / `anyOutgoingListenerCount` — outgoing-side catch-all listener family matching JS `socket.onAnyOutgoing`. Fires only on actual `engine.send` (after the connected-state guard); ack response frames bypass; disconnected emits do NOT fire (JS-aligned per `socket.io-client/lib/socket.ts` `emit()` body). Mutators serialize via `handleQueue.async`.
- `SocketIOClient.send(_:completion:)` / `send(with:completion:)` / `sendWithAck(_:)` / `sendWithAck(with:)` — JS-aligned shortcuts for `emit("message", ...)` / `emitWithAck("message", ...)`. Server-side reception via existing `socket.on("message", ...)`. The legacy `OnAckCallback.timingOut` chain on `sendWithAck` still uses the magic-string `SocketAckStatus.noAck` for timeouts and is NOT cleared on disconnect — Phase 9's `socket.timeout(after:).emit(...)` provides typed errors and disconnect-clearing.
- `SocketIOClient.volatile.emit(...)` chain. Drops packet if `engine.writable == false`; no `.error`, no outgoing-listener fire, no buffering. JS-aligned per `socket.io-client/lib/socket.ts` `emit()` body which gates `discardPacket = volatile && !transport.writable`. No volatile-with-ack overload (JS allows it but the callback orphans on drop — Swift omits the API).
- `SocketEngineSpec.writable: Bool { get }` — additive protocol requirement with fail-safe `false` default. Concrete `SocketEngine.writable` returns `true` when connected and (WebSocket-mode with active ws) OR (polling-mode with no in-flight POST).
- `SocketIOClient.setAuth(_:)` — install a callback-form auth provider invoked on `handleQueue` for every CONNECT (initial + reconnect). JS-aligned with `socket.io-client/lib/socket.ts onopen()`. Multi-callback sends multiple CONNECT packets (parity with JS).
- `SocketIOClient.setAuth(_:)` async/throws overload (iOS 13+ / macOS 10.15+). On throw, fires `.error` clientEvent with the localized error description; CONNECT is not sent (fail-closed). Stale results from a generation-mismatched provider are silently dropped.
- `SocketIOClient.clearAuth()` — removes the installed provider and cancels any in-flight async resolution Task.
- v2 manager guard: installing a provider on a `.version(.two)` manager fires `.error` per CONNECT attempt with a clear bypass message; the provider is never invoked on v2 (where the underlying connect path drops payloads).
- `SocketIOClient.timeout(after:) -> SocketTimedEmitter` — per-emit ack with typed `SocketAckError.timeout` / `.disconnected` (err-first callback `(Error?, [Any]) -> Void`). JS-aligned with `socket.io-client` `socket.timeout(N).emit(...)`. Atomic one-shot fire across timer / server-ack / cancel paths.
- Async/throws overload of `SocketTimedEmitter.emit(...)` (iOS 13+ / macOS 10.15+) with `Task.cancel()` support — cancellation surfaces as `CancellationError` thrown from the await.
- `SocketAckManager` parallel `timedAcks` storage and 4 internal APIs (`addTimedAck` / `executeTimedAck` / `cancelTimedAck(fireWith:)` / `clearTimedAcks(reason:)`). Legacy `acks` storage and `emitWithAck.timingOut(after:)` path are untouched.
- `SocketIOClient.didDisconnect` clears `timedAcks` with `.disconnected` (matches JS `_clearAcks` for `withError` callbacks).

## Breaking

- An engine handshake that never completes now fails after 20 s (`.error` with `"timeout"`, engine closed, reconnect loop starts if enabled) instead of waiting indefinitely; set `.connectTimeout(.infinity)` to restore the old behaviour.
- An `emit` made while the socket is not connected is now **buffered and sent on the next CONNECT** instead of being dropped with a `Tried emitting when not connected` `.error`. JS-aligned with `sendBuffer` in `socket.io-client/lib/socket.ts` (`emit()` / `emitBuffered()`). Callers that treated that `.error` as "this event is lost, handle it yourself" will no longer see it, and the event will arrive after the reconnect. Like JS, the buffer has no upper bound. Ack *responses* (`emitAck`) are unaffected and still report the error.

## Breaking (.three managers only)

- `SocketManager.connectSocket` now emits `.error` and aborts when the caller's `connectPayload` cannot be JSON-encoded. Previously the connect was sent with an empty payload, silently dropping user auth. Callers must supply a JSON-serializable dict. No change for v2 managers.

## Divergences from socket.io-client JS 4.8.x (documented)

- `_lastOffset` is capped at 256 UTF-8 bytes (D1).
- Payload JSON failure is surfaced as `.error` (D2).
- `clearRecoveryState()` is a new API (D3).
- `setAuth(_:)` async/throws overload + v2 `.error` channel + generation-token stale-result discard are Swift additions (D4).
- `SocketTimedEmitter.cancelTimedAck(_:fireWith:)` surfaces `Task.cancel()` as the user-callback's err parameter (so the one-shot guarantee lives in the `fired` flag, not in continuation racing). Pure Swift addition (D5).
- Legacy `emitWithAck(...).timingOut(after:)` is NOT cleared on disconnect — only the new `timeout(after:).emit` path is. Preserved for backwards compatibility.

# v16.1.0

- Remove support for iOS 11.
- Update to Starscream 4.0.6

# v16.0.0

- Removed Objective-C support. It's time for you to embrace Swift.
- Socket.io 3 support.

# v15.3.0

- Add `==` operators for `SocketAckStatus` and `String`

# v15.2.0

- Small fixes.

# v15.1.0

- Add ability to enable websockets SOCKS proxy.
- Fix emit completion callback not firing on websockets [#1178](https://github.com/socketio/socket.io-client-swift/issues/1178)

# v15.0.0

- Swift 5

# v14.0.0

- Minimum version of the client is now Swift 4.2.
- Add exponential backoff for reconnects, with `reconnectWaitMax` and `randomizationFactor` options [#1149](https://github.com/socketio/socket.io-client-swift/pull/1149)
- `statusChange` event's data format adds a second value, the raw value of the status. This is for use in Objective-C. [#1147](https://github.com/socketio/socket.io-client-swift/issues/1147)

# v13.4.0

- Add emits with write completion handlers. [#1096](https://github.com/socketio/socket.io-client-swift/issues/1096)
- Add ability to listen for when a websocket upgrade happens

# v13.3.1

- Fixes various bugs. [#857](https://github.com/socketio/socket.io-client-swift/issues/857), [#1078](https://github.com/socketio/socket.io-client-swift/issues/1078)

# v13.3.0

- Copy cookies from polling to WebSockets ([#1057](https://github.com/socketio/socket.io-client-swift/issues/1057), [#1058](https://github.com/socketio/socket.io-client-swift/issues/1058))

# v13.2.1

- Fix packets getting lost when WebSocket upgrade fails. [#1033](https://github.com/socketio/socket.io-client-swift/issues/1033)
- Fix bad unit tests. [#794](https://github.com/socketio/socket.io-client-swift/issues/794)

# v13.2.0

- Add ability to bypass Data inspection in emits. [#992]((https://github.com/socketio/socket.io-client-swift/issues/992))
- Allow `SocketEngine` to be subclassed

# v13.1.3

- Fix setting reconnectAttempts [#989]((https://github.com/socketio/socket.io-client-swift/issues/989))


# v13.1.2

- Fix [#950](https://github.com/socketio/socket.io-client-swift/issues/950)
- Conforming to `SocketEngineWebsocket` no longer requires conforming to `WebsocketDelegate`


# v13.1.1

- Fix [#923](https://github.com/socketio/socket.io-client-swift/issues/923)
- Fix [#894](https://github.com/socketio/socket.io-client-swift/issues/894)

# v13.1.0

- Allow setting `SocketEngineSpec.extraHeaders` after init.
- Deprecate `SocketEngineSpec.websocket` in favor of just using the `SocketEngineSpec.polling` property.
- Enable bitcode for most platforms.
- Fix [#882](https://github.com/socketio/socket.io-client-swift/issues/882). This adds a new method
`SocketManger.removeSocket(_:)` that should be called if when you no longer wish to use a socket again.
This will cause the engine to no longer keep a strong reference to the socket and no longer track it.

# v13.0.1

- Fix not setting handleQueue on `SocketManager`

# v13.0.0

Checkout out the migration guide in Usage Docs for a more detailed guide on how to migrate to this version.

What's new:
---

- Adds a new `SocketManager` class that multiplexes multiple namespaces through a single engine.
- Adds `.sentPing` and `.gotPong` client events for tracking ping/pongs.
- watchOS support.

Important API changes
---

- Many properties that were previously on `SocketIOClient` have been moved to the `SocketManager`.
- `SocketIOClientOption.nsp` has been removed. Use `SocketManager.socket(forNamespace:)` to create/get a socket attached to a specific namespace.
- Adds `.sentPing` and `.gotPong` client events for tracking ping/pongs.
- Makes the framework a single target.
- Updates Starscream to 3.0
