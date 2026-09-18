# Parity with the JavaScript client

This fork exists to behave like [socket.io-client](https://github.com/socketio/socket.io)
does, and the only honest way to say how close it is, is to measure it against
that client's own tests rather than against our reading of its source.

This file tracks every scenario in `socket.io/packages/socket.io-client/test`
at **v4.8.3** — 116 of them — and what this client does about it.

| Status | Meaning | Count |
|---|---|---|
| ✅ covered | an existing Swift test asserts the same behaviour | 41 |
| ✅ ported | the JS scenario itself is now a Swift test, in `JSParityE2ETest` | 10 |
| 🔧 fixed | the port found a divergence and it was fixed | 1 |
| ❌ gap | a known divergence, not yet addressed | 8 |
| ➖ n/a | not applicable to Swift or to a non-browser platform | 14 |
| ❓ unassessed | not yet checked — **the honest state, not a claim of parity** | 42 |

**42 of 116 are unassessed.** They are not assumed to pass. Porting them is the
remaining work, and each port either confirms the behaviour or finds something,
as the middleware-failure scenario did.

## What porting found so far

- **`should not try to reconnect after a middleware failure`** — after the
  server refused a namespace, this client re-sent CONNECT on *every* subsequent
  engine open. A server rejecting an expired token would be asked again on each
  reconnect, forever. `SocketManager._engineDidOpen` now skips sockets whose
  `active` is false, which is what the flag was introduced for; nothing had been
  reading it.

## Open gaps

- **No `connect_error` client event.** A refused connection surfaces as `.error`.
  The message and `data` do reach the application (pinned by two ported tests),
  but the event name differs and `.error` carries other things too.
- **No `retries` option** and no packet queue behind it (4 scenarios).
- **No manager-level `ackTimeout`** (2 scenarios).
- **A decoding exception does not close the engine.** JS treats an
  undecodable packet as fatal for the transport; this client logs and continues.
- Plus the engine-level items in the repository history: no `t=` cache buster on
  polling requests, and disconnect reasons that are not the JS strings
  (`io server disconnect`, `ping timeout`, …).

## How to add to this

The fixture server under `Tests/TestSocketIO/E2E/Fixtures/server.js` mirrors
`test/support/server.ts` where the ported scenarios need it — same namespace
names (`/no`, `/with-data`, `/foo`, `/asd`), same error strings, same `echo`
handler. Port a scenario into `JSParityE2ETest`, keep the JS title in a `MARK`
comment, and let CI decide whether it passes.

## The matrix

### `connection.ts`

| Scenario | Status | Where |
|---|---|---|
| should connect to localhost | ✅ covered | `HarnessSanityTest`, every E2E `connect` expectation |
| should not connect when autoConnect option set to false | ✅ covered | `AutoConnectE2ETest` |
| should start two connections with same path | ❓ unassessed |  |
| should start two connections with same path and different querystrings | ❓ unassessed |  |
| should start two connections with different paths | ❓ unassessed |  |
| should start a single connection with different namespaces | ✅ ported | `testDisconnectingOneNamespaceKeepsTheOtherConnected` covers the shared engine |
| should work with acks | ✅ ported | `testEmitWithAckRoundTrip` |
| should receive date with ack | ➖ n/a | JS `Date` has no Swift equivalent on the wire; `SocketData` is the Swift contract |
| should work with false | ❓ unassessed |  |
| should receive utf8 multibyte characters | ✅ ported | `testUtf8MultibyteCharactersSurviveTheRoundTrip` |
| should connect to a namespace after connection established | ❓ unassessed |  |
| should open a new namespace after connection gets closed | ❓ unassessed |  |
| should reconnect by default | ✅ covered | `SocketMangerTest` |
| should reconnect manually | ❓ unassessed |  |
| should reconnect automatically after reconnecting manually | ❓ unassessed |  |
| should attempt reconnects after a failed reconnect | ❓ unassessed |  |
| reconnect delay should increase every time | ✅ covered | exponential backoff, `SocketMangerTest` |
| should not reconnect when force closed | ❓ unassessed |  |
| should stop reconnecting when force closed | ❓ unassessed |  |
| should reconnect after stopping reconnection | ❓ unassessed |  |
| should stop reconnecting on a socket and keep to reconnect on another | ❓ unassessed |  |
| should try to reconnect twice and fail when requested two attempts with immediate timeout and reconnect enabled | ❓ unassessed |  |
| should fire reconnect_* events on manager | ❓ unassessed | Swift fires `.reconnect` / `.reconnectAttempt` on the socket, not the manager |
| should fire reconnecting (on manager) with attempts number when reconnecting twice | ❓ unassessed |  |
| should not try to reconnect and should form a connection when connecting to correct port with default timeout | ❓ unassessed |  |
| should connect while disconnecting another socket | ❓ unassessed |  |
| should emit a connect_error event when reaching a Socket.IO server in v2.x | ❓ unassessed |  |
| should not close the connection when disconnecting a single socket | ✅ ported | `testDisconnectingOneNamespaceKeepsTheOtherConnected` |
| should stop trying to reconnect | ❓ unassessed |  |
| should try to reconnect twice and fail when requested two attempts with incorrect address and reconnect enabled | ❓ unassessed |  |
| should not try to reconnect with incorrect port when reconnection disabled | ❓ unassessed |  |
| should still try to reconnect twice after opening another socket asynchronously | ❓ unassessed |  |
| should use overridden setTimeout by default | ➖ n/a | JS timer-injection idiom |
| should use native setTimeout with useNativeSetTimers | ➖ n/a | JS timer-injection idiom |
| should emit date as string | ➖ n/a | JS `Date` serialisation |
| should emit date in object | ➖ n/a | JS `Date` serialisation |
| should get base64 data as a last resort | ✅ covered | `SocketBasicPacketTest`, `SocketParserTest` |
| should get binary data (as an ArrayBuffer) | ✅ covered | `Data` in `SocketBasicPacketTest` |
| should send binary data (as an ArrayBuffer) | ✅ covered | `Data` in `SocketBasicPacketTest` |
| should send binary data (as an ArrayBuffer) mixed with json | ✅ covered | `SocketBasicPacketTest` |
| should send events with ArrayBuffers in the correct order | ❓ unassessed |  |
| should send binary data (as a Blob) | ➖ n/a | browser-only type |
| should send binary data (as a Blob) mixed with json | ➖ n/a | browser-only type |
| should send events with Blobs in the correct order | ➖ n/a | browser-only type |
| should reopen a cached socket | ❓ unassessed |  |
| should not reopen a cached but active socket | ❓ unassessed |  |
| should not reopen an already active socket | ❓ unassessed |  |
| should close the engine upon decoding exception | ❌ gap | Swift logs a parse failure and keeps the engine open |

### `socket.ts`

| Scenario | Status | Where |
|---|---|---|
| should have an accessible socket id equal to the server-side socket id (default namespace) | ✅ ported | `testSocketIdIsClearedOnDisconnect` asserts the id exists while connected |
| should have an accessible socket id equal to the server-side socket id (custom namespace) | ❓ unassessed |  |
| clears socket.id upon disconnection | ✅ ported | `testSocketIdIsClearedOnDisconnect` |
| doesn | ❓ unassessed |  |
| fire a connect_error event when the connection cannot be established | ❌ gap | Swift has no `connect_error` client event; it maps onto `.error` |
| fire a connect_error event on open timeout (polling) | ❓ unassessed |  |
| fire a connect_error event on open timeout (websocket) | ❓ unassessed |  |
| doesn | ❓ unassessed |  |
| should change socket.id upon reconnection | ✅ ported | `testSocketIdChangesOnReconnection` |
| should enable compression by default | ❓ unassessed |  |
| should disable compression | ❓ unassessed |  |
| should accept an object (default namespace) | ✅ covered | `SocketIOClientConfigurationTest` (`connectParams`) |
| should accept a query string (default namespace) | ✅ covered | `SocketIOClientConfigurationTest` |
| should accept an object | ✅ covered | `SocketAuthProviderTest` / `SocketAuthProviderE2ETest` |
| should accept a query string | ✅ covered | `SocketIOClientConfigurationTest` |
| should properly encode the parameters | ❓ unassessed |  |
| should accept an object | ✅ covered | `SocketAuthProviderTest` / `SocketAuthProviderE2ETest` |
| should accept an function | ✅ covered | `setAuth(_:)`, `SocketAuthProviderE2ETest` |
| should fire an error event on middleware failure from custom namespace | ✅ ported | `testMiddlewareFailureOnCustomNamespaceIsReported` |
| should fire a connect_error event with error data on middleware failure | ✅ ported | `testMiddlewareFailureCarriesItsErrorData` |
| should not try to reconnect after a middleware failure | 🔧 fixed | **found by this port** — `testNoRejoinAfterAMiddlewareFailure` |
| should properly disconnect then reconnect | ❓ unassessed |  |
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
| should use the default timeout value | ❌ gap | no manager-level `ackTimeout` option in Swift |
| should not ack upon disconnection (callback) | ✅ covered | legacy `emitWithAck.timingOut` is documented as not cleared on disconnect |
| should ack with an error upon disconnection (callback & timeout) | ✅ covered | `SocketTimedEmitterTest`, `.disconnected` |
| should ack with an error upon disconnection (callback & ackTimeout) | ❌ gap | depends on the missing `ackTimeout` option |
| should ack with an error upon disconnection (promise) | ✅ covered | `SocketTimedEmitterAsyncTest` |
| should ack with an error upon disconnection (promise & timeout) | ✅ covered | `SocketTimedEmitterAsyncTest` |
| should not discard an unsent ack (callback) | ✅ ported | `testAnUnsentAckIsNotDiscarded` |
| should buffer the event and send it upon reconnection | ✅ covered | `SocketSendBufferTest` (whole file) |

### `url.ts`

| Scenario | Status | Where |
|---|---|---|
| works with undefined | ❓ unassessed |  |
| works with relative paths | ❓ unassessed |  |
| works with no protocol | ❓ unassessed |  |
| works with no schema | ❓ unassessed |  |
| forces ports for unique url ids | ❓ unassessed |  |
| identifies the namespace | ✅ covered | `SocketNamespacePacketTest` |
| works with ipv6 | ❓ unassessed |  |
| works with ipv6 location | ➖ n/a | browser `location` |
| works with a custom path | ✅ covered | `SocketIOClientConfigurationTest` (`path`) |

### `retry.ts`

| Scenario | Status | Where |
|---|---|---|
| should preserve the order of the packets | ❌ gap | no `retries` option in Swift |
| should fail when the server does not acknowledge the packet | ❌ gap | no `retries` option in Swift |
| should not drain the queue while the socket is disconnected | ❌ gap | no `retries` option in Swift |
| should not emit a packet twice in the  | ❌ gap | no `retries` option in Swift |

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

