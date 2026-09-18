# Parity with the JavaScript client

This fork exists to behave like [socket.io-client](https://github.com/socketio/socket.io)
does, and the only honest way to say how close it is, is to measure it against
that client's own tests rather than against our reading of its source.

This file tracks every scenario in `socket.io/packages/socket.io-client/test`
at **v4.8.3** — 116 of them — and what this client does about it.

| Status | Meaning | Count |
|---|---|---|
| ✅ covered | an existing Swift test asserts the same behaviour | 41 |
| ✅ ported | the JS scenario itself is now a Swift test | 36 |
| 🔧 fixed | the port found a divergence and it was fixed | 8 |
| ❌ gap | a known divergence, not yet addressed | 9 |
| ➖ n/a | not applicable to Swift or to a non-browser platform | 22 |
| ❓ unassessed | not yet checked | 0 |

Every scenario has been assessed. "Parity" here means: **85 of the
94 applicable scenarios pass a Swift test that encodes the JS
expectation; 9 are known divergences, each named below with its reason.**

## What porting has found

- **`should not try to reconnect after a middleware failure`** — after the
  server refused a namespace, this client re-sent CONNECT on *every* subsequent
  engine open. A server rejecting an expired token would be asked again on each
  reconnect, forever. `SocketManager._engineDidOpen` now skips sockets whose
  `active` is false, which is what the flag was introduced for; nothing had been
  reading it.
- **`should emit a connect_error event when reaching a Socket.IO server in v2.x`**
  — a CONNECT packet without a `sid` on a `.three` manager connected the socket.
  JS recognises it as a v2 server and fires `connect_error` with a message
  pointing at the migration guide; this client now does the same via
  `.connectError`. A v3 client against a v2 server previously looked connected
  while nothing worked.

- **`should attempt reconnects after a failed reconnect`** — after the
  reconnect budget was exhausted the manager stayed flagged as reconnecting,
  so a later `connect()` never started a new cycle; and a handshake completing
  after a timeout-close revived the reused engine with a stale session. Both
  fixed with the connection-timeout work.

Gaps closed since the first matrix: connection timeout (`.connectTimeout`),
undecodable data closes the engine, `Manager.socket()` reopens an inactive
socket, the `t=` cache buster, `ackTimeout` with err-first `emit(_:_:ack:)`,
and the `connect_error` client event (see below).

Worth recording because they did **not** show up: a transport dropping under an
established connection does not raise a client-side error here, and a
`disconnect(); connect()` bounce surfaces exactly one `.disconnect`. An app that
reports the server as unreachable in those situations is doing so on its own
account.

## Open gaps

- **`.reconnect` means the opposite of JS `reconnect`.** Here it fires when
  reconnection *starts* (`setReconnecting`); in JS it fires on *success*. A
  successful reconnect here is observed as another `.connect`. Nothing fires on
  the manager (2 scenarios).
- **No `retries` option** and no packet queue behind it (4 scenarios).
- **No per-emit `compress(_:)` chain** — `.compress` is a manager-wide option
  (2 scenarios).
- Plus, from the engine side: disconnect reasons that are not the JS strings
  (`io server disconnect`, `ping timeout`, …). (The missing `t=` cache buster
  on polling requests is closed: every long-polling request now carries one.)

## How to add to this

The fixture server under `Tests/TestSocketIO/E2E/Fixtures/server.js` mirrors
`test/support/server.ts` where the ported scenarios need it — same namespace
names (`/no`, `/with-data`, `/foo`, `/asd`, `/valid`, `/abc`), same error
strings, same `echo`, `false` and `abuff1`/`abuff2` handlers. Port a scenario
into `JSParityE2ETest` (or `JSParityUnitTest` when no server is needed), keep
the JS title in a `MARK` comment, and let CI decide whether it passes.

Force a reconnect with `/admin/kill-transport`, never with
`engine.disconnect(reason:)` — the latter is a clean shutdown and does not
reliably reconnect, which silently turns a "this must not happen" test into one
that proves nothing. And wait for `.connect`, not `.reconnect`, to observe a
successful reconnection.

## The matrix

### `connection.ts`

| Scenario | Status | Where |
|---|---|---|
| should connect to localhost | ✅ covered | `HarnessSanityTest`, every E2E `connect` expectation |
| should not connect when autoConnect option set to false | ✅ covered | `AutoConnectE2ETest` |
| should start two connections with same path | ➖ n/a | tests JS `io()`'s Manager cache (`forceNew`/`multiplex`); every Swift `SocketManager` is its own connection, and Swift's `.forceNew` only forces a new engine |
| should start two connections with same path and different querystrings | ➖ n/a | tests JS `io()`'s Manager cache (`forceNew`/`multiplex`); every Swift `SocketManager` is its own connection, and Swift's `.forceNew` only forces a new engine |
| should start two connections with different paths | ➖ n/a | tests JS `io()`'s Manager cache (`forceNew`/`multiplex`); every Swift `SocketManager` is its own connection, and Swift's `.forceNew` only forces a new engine |
| should start a single connection with different namespaces | ✅ ported | `testTwoNamespacesSendOneConnectFrameEach` |
| should work with acks | ✅ ported | `testEmitWithAckRoundTrip` |
| should receive date with ack | ➖ n/a | JS `Date` has no Swift equivalent on the wire; `SocketData` is the Swift contract |
| should work with false | ✅ ported | `testFalseSurvivesTheRoundTrip` |
| should receive utf8 multibyte characters | ✅ ported | `testUtf8MultibyteCharactersSurviveTheRoundTrip` |
| should connect to a namespace after connection established | ✅ ported | `testJoinANamespaceAfterTheConnectionIsEstablished` |
| should open a new namespace after connection gets closed | ✅ ported | `testJoinANewNamespaceAfterTheConnectionWasClosed` |
| should reconnect by default | ✅ covered | `SocketMangerTest` |
| should reconnect manually | ✅ ported | `testReconnectManually` |
| should reconnect automatically after reconnecting manually | ✅ ported | `testReconnectAutomaticallyAfterReconnectingManually` — note Swift `.reconnect` fires when reconnection *starts*; success is another `.connect` |
| should attempt reconnects after a failed reconnect | ✅ ported | `testAttemptReconnectsAfterAFailedReconnect` (connect timeout PR) |
| reconnect delay should increase every time | ✅ covered | exponential backoff, `SocketMangerTest` |
| should not reconnect when force closed | ✅ ported | `testNoReconnectWhenForceClosedDuringTimeout` |
| should stop reconnecting when force closed | ✅ ported | `testStopReconnectingWhenForceClosed` |
| should reconnect after stopping reconnection | ✅ ported | `testReconnectAfterStoppingReconnection` |
| should stop reconnecting on a socket and keep to reconnect on another | ✅ ported | `testStopReconnectingOnOneSocketButNotTheOther` |
| should try to reconnect twice and fail when requested two attempts with immediate timeout and reconnect enabled | ✅ ported | `testReconnectTwiceThenFailWithImmediateTimeout` |
| should fire reconnect_* events on manager | ❌ gap | Swift fires `.reconnect` / `.reconnectAttempt` on the socket; the manager has no event channel — and `.reconnect` marks the *start* of reconnection, not success |
| should fire reconnecting (on manager) with attempts number when reconnecting twice | ❌ gap | same: no manager-level events |
| should not try to reconnect and should form a connection when connecting to correct port with default timeout | ✅ ported | `testNoReconnectAttemptWhenConnectingToCorrectPort` |
| should connect while disconnecting another socket | ✅ ported | `testConnectWhileDisconnectingAnotherSocket` |
| should emit a connect_error event when reaching a Socket.IO server in v2.x | 🔧 fixed | **found by this port** — `JSParityUnitTest.testConnectPacketWithoutPayloadFiresConnectError`; a CONNECT without `sid` used to connect the socket |
| should not close the connection when disconnecting a single socket | ✅ ported | `testDisconnectingOneNamespaceKeepsTheOtherConnected` |
| should stop trying to reconnect | ✅ ported | `testStopTryingToReconnect` |
| should try to reconnect twice and fail when requested two attempts with incorrect address and reconnect enabled | ✅ ported | `testReconnectTwiceThenFailWithIncorrectAddress` |
| should not try to reconnect with incorrect port when reconnection disabled | ✅ ported | `testNoReconnectWhenDisabledWithIncorrectPort` |
| should still try to reconnect twice after opening another socket asynchronously | ✅ ported | `testReconnectTwiceAfterOpeningAnotherSocketAsynchronously` |
| should use overridden setTimeout by default | ➖ n/a | JS timer-injection idiom |
| should use native setTimeout with useNativeSetTimers | ➖ n/a | JS timer-injection idiom |
| should emit date as string | ➖ n/a | JS `Date` serialisation |
| should emit date in object | ➖ n/a | JS `Date` serialisation |
| should get base64 data as a last resort | ✅ covered | `SocketBasicPacketTest`, `SocketParserTest` |
| should get binary data (as an ArrayBuffer) | ✅ covered | `Data` in `SocketBasicPacketTest` |
| should send binary data (as an ArrayBuffer) | ✅ covered | `Data` in `SocketBasicPacketTest` |
| should send binary data (as an ArrayBuffer) mixed with json | ✅ covered | `SocketBasicPacketTest` |
| should send events with ArrayBuffers in the correct order | ✅ ported | `testBinaryEventsArriveInOrder` |
| should send binary data (as a Blob) | ➖ n/a | browser-only type |
| should send binary data (as a Blob) mixed with json | ➖ n/a | browser-only type |
| should send events with Blobs in the correct order | ➖ n/a | browser-only type |
| should reopen a cached socket | 🔧 fixed | **gap closed** — `socket(forNamespace:)` re-connects an inactive socket when `autoConnect` is on; `testReopenACachedSocket` |
| should not reopen a cached but active socket | ✅ ported | `testFetchingTheSameNamespaceTwiceSendsOneConnectFrame` |
| should not reopen an already active socket | ✅ ported | `testTwoNamespacesSendOneConnectFrameEach` |
| should close the engine upon decoding exception | 🔧 fixed | **gap closed** — undecodable data closes the engine with "parse error"; `testParseErrorClosesEngineAndReconnectsWithFreshSession`, `SocketParseErrorTest` |

### `socket.ts`

| Scenario | Status | Where |
|---|---|---|
| should have an accessible socket id equal to the server-side socket id (default namespace) | ✅ ported | `testSocketIdIsClearedOnDisconnect` |
| should have an accessible socket id equal to the server-side socket id (custom namespace) | ✅ ported | `testSocketIdOnACustomNamespace` |
| clears socket.id upon disconnection | ✅ ported | `testSocketIdIsClearedOnDisconnect` |
| doesn't fire an error event if we force disconnect in opening state | ✅ ported | `testNoErrorWhenDisconnectingWhileStillOpening` |
| fire a connect_error event when the connection cannot be established | 🔧 fixed | **gap closed** — `.connectError` client event (`.engineDidError` while not connected) |
| fire a connect_error event on open timeout (polling) | 🔧 fixed | **gap closed** — `.connectTimeout`, `testConnectErrorOnOpenTimeoutPolling` |
| fire a connect_error event on open timeout (websocket) | 🔧 fixed | **gap closed** — `.connectTimeout`, `testConnectErrorOnOpenTimeoutWebsocket` |
| doesn't fire a connect_error event when the connection is already established | ✅ ported | `testNoErrorEventWhenAnEstablishedConnectionDrops` |
| should change socket.id upon reconnection | ✅ ported | `testSocketIdChangesOnReconnection` |
| should enable compression by default | ❌ gap | no per-emit `compress(_:)` chain in Swift; `.compress` is a manager option |
| should disable compression | ❌ gap | no per-emit `compress(_:)` chain in Swift |
| should accept an object (default namespace) | ✅ covered | `SocketIOClientConfigurationTest` (`connectParams`) |
| should accept a query string (default namespace) | ✅ covered | `SocketIOClientConfigurationTest` |
| should accept an object | ✅ covered | `SocketAuthProviderTest` / `SocketAuthProviderE2ETest` |
| should accept a query string | ✅ covered | `SocketIOClientConfigurationTest` |
| should properly encode the parameters | ✅ ported | `testQueryParametersAreProperlyEncoded` |
| should accept an object | ✅ covered | `SocketAuthProviderTest` / `SocketAuthProviderE2ETest` |
| should accept an function | ✅ covered | `setAuth(_:)`, `SocketAuthProviderE2ETest` |
| should fire an error event on middleware failure from custom namespace | ✅ ported | `testMiddlewareFailureOnCustomNamespaceIsReported` |
| should fire a connect_error event with error data on middleware failure | ✅ ported | `testMiddlewareFailureCarriesItsErrorData` |
| should not try to reconnect after a middleware failure | 🔧 fixed | **found by this port** — `testNoRejoinAfterAMiddlewareFailure` |
| should properly disconnect then reconnect | ✅ ported | `testDisconnectThenReconnect` |
| should throw on reserved event | ✅ covered | `SocketReservedEventTest`, `ReservedEventE2ETest` (`.error` instead of `throw`) |
| should emit events in order | ✅ covered | `SocketSendBufferTest.testBufferedEmitsKeepTheirOrder` |
| should emit an event and wait for the acknowledgement | ✅ covered | `SocketTimedEmitterTest` async overload |
| should discard a volatile packet when the socket is not connected | ✅ covered | `SocketVolatileTest` |
| should discard a volatile packet when the pipe is not ready | ✅ covered | `SocketVolatileTest`, `SocketEngineWritableTest` |
| should send a volatile packet when the socket is connected and the pipe is ready | ✅ covered | `SocketVolatileTest` |
| should call listener | ✅ covered | `SocketAnyListenersTest` / `SocketAnyOutgoingListenersTest` |
| should prepend listener | ✅ covered | `SocketAnyListenersTest` / `SocketAnyOutgoingListenersTest` |
| should remove listener | ✅ covered | `SocketAnyListenersTest` / `SocketAnyOutgoingListenersTest` |
| should call listener | ✅ covered | `SocketAnyListenersTest` / `SocketAnyOutgoingListenersTest` |
| should call listener with binary data | ✅ covered | `SocketAnyOutgoingListenersTest` |
| should prepend listener | ✅ covered | `SocketAnyListenersTest` / `SocketAnyOutgoingListenersTest` |
| should remove listener | ✅ covered | `SocketAnyListenersTest` / `SocketAnyOutgoingListenersTest` |
| should timeout after the given delay when socket is not connected | ✅ covered | `SocketTimedEmitterTest` |
| should timeout when the server does not acknowledge the event | ✅ covered | `SocketTimedEmitterE2ETest` (`never_ack`) |
| should timeout when the server does not acknowledge the event in time | ✅ covered | `SocketTimedEmitterTest` |
| should not timeout when the server does acknowledge the event | ✅ covered | `SocketTimedEmitterE2ETest` |
| should timeout when the server does not acknowledge the event (promise) | ✅ covered | `SocketTimedEmitterAsyncTest` |
| should not timeout when the server does acknowledge the event (promise) | ✅ covered | `SocketTimedEmitterAsyncTest` |
| should use the default timeout value | 🔧 fixed | **gap closed** — `.ackTimeout` + `emit(_:_:ack:)`; `testDefaultAckTimeoutApplies`, `SocketAckTimeoutTest` |
| should not ack upon disconnection (callback) | ✅ covered | legacy `emitWithAck.timingOut` is documented as not cleared on disconnect |
| should ack with an error upon disconnection (callback & timeout) | ✅ covered | `SocketTimedEmitterTest`, `.disconnected` |
| should ack with an error upon disconnection (callback & ackTimeout) | 🔧 fixed | **gap closed** — `testAckTimeoutFailsWithErrorOnDisconnect` |
| should ack with an error upon disconnection (promise) | ✅ covered | `SocketTimedEmitterAsyncTest` |
| should ack with an error upon disconnection (promise & timeout) | ✅ covered | `SocketTimedEmitterAsyncTest` |
| should not discard an unsent ack (callback) | ✅ ported | `testAnUnsentAckIsNotDiscarded` |
| should buffer the event and send it upon reconnection | ✅ covered | `SocketSendBufferTest` (whole file) |

### `url.ts`

| Scenario | Status | Where |
|---|---|---|
| works with undefined | ➖ n/a | resolves against the browser's `location`; Swift takes a full `URL` |
| works with relative paths | ➖ n/a | resolves against the browser's `location` |
| works with no protocol | ➖ n/a | resolves against the browser's `location` |
| works with no schema | ➖ n/a | resolves against the browser's `location` |
| forces ports for unique url ids | ➖ n/a | JS `io()` caches Managers by url id; Swift constructs `SocketManager` explicitly |
| identifies the namespace | ✅ covered | `SocketNamespacePacketTest` |
| works with ipv6 | ✅ ported | `SocketEngineTest.testIpv6HostSurvivesEngineUrlConstruction` |
| works with ipv6 location | ➖ n/a | browser `location` |
| works with a custom path | ✅ covered | `SocketIOClientConfigurationTest` (`path`) |

### `retry.ts`

| Scenario | Status | Where |
|---|---|---|
| should preserve the order of the packets | ❌ gap | no `retries` option in Swift |
| should fail when the server does not acknowledge the packet | ❌ gap | no `retries` option in Swift |
| should not drain the queue while the socket is disconnected | ❌ gap | no `retries` option in Swift |
| should not emit a packet twice in the 'connect' handler | ❌ gap | no `retries` option in Swift |

### `connection-state-recovery.ts`

| Scenario | Status | Where |
|---|---|---|
| should have an accessible socket id equal to the server-side socket id (default namespace) | ✅ covered | `StateRecoveryE2ETest` (12 cases) |

### `node.ts`

| Scenario | Status | Where |
|---|---|---|
| should stop once the timer is triggered | ➖ n/a | `autoUnref` is a Node event-loop concern |
| should stop once the timer is triggered (even when trying to reconnect) | ➖ n/a | `autoUnref` |
| should stop once the timer is triggered (polling) | ➖ n/a | `autoUnref` |
| should stop once the timer is triggered (websocket) | ➖ n/a | `autoUnref` |
| should not stop with autoUnref set to false | ➖ n/a | `autoUnref` |
