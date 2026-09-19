# Native client parity follow-up

Baseline: merged `master` at `37e8b039f3db1d30beee320b4d97610711f3718f` (PR #18).
Reference: official `socketio/socket.io` at `aaf2af36ec8ad05910f357a788e0e358bad32738`.

## Implemented

* Incoming/outgoing multi-listener mutations run immediately on the owning queue, preserving off-queue asynchronous compatibility. Snapshot dispatch still protects the current iteration. Modern incoming catch-all listeners do not receive internal lifecycle events; legacy `onAny` keeps its historical behavior.
* Both terminal disconnect and automatic reconnect close the modern acknowledgement lifetime. The disconnect event precedes error callbacks. A pre-notification ID snapshot prevents reentrant successor registrations from being swept; unsent buffered acks survive. The retry head drains synchronously on the owner queue, and retries retain fresh attempt IDs and ordering.
* Explicit empty `connectParams` replaces a URL query, as an empty JS object does. Engine-owned EIO/transport/SID/base64 fields cannot be overridden, including percent-encoded names. A token containing `EIO` cannot suppress the protocol version. Absolute HTTP(S)/WS(S), IPv6, ports and paths have concrete native URI tests.
* `JS-082` now checks server-acknowledged ordering across a connect-handler emit, separately for polling, WebSocket and upgrade-enabled configuration. The binary outgoing-listener port does not insert an artificial queue drain. Additional real-transport tests cover binary/UTF-8 round trips and remote disconnect/ack behavior.
* Fixture startup drains stdout and stderr asynchronously and keeps bounded diagnostic tails. Silent/early-exiting/noisy/invalid-readiness/SIGTERM-resistant children have regression tests. Dependency installation and process shutdown are bounded. Fixture versions and transitive dependencies are locked; CI uses `npm ci` without lifecycle scripts.
* The parser harness invokes the actual pinned JS Encoder as well as Decoder: Swift encoding → JS decoding, JS encoding → Swift decoding, and the existing generated decode corpus. Comparison normalizes representation differences; it is not byte-for-byte JSON object-order equivalence.

## Evidence and CI contracts

`JavaScriptParityContracts.json` gives exact XCTest symbols and assertions for selected reviewed contracts. CI requires these symbols to exist **and to appear as passed executions** in the current Swift log. It also compares every CSV declaration identity with a newly generated AST inventory of the pinned JS checkout. Checker self-tests reject fake symbols, absent execution evidence and unreviewed backlog changes.

The original Node client suites are executed in a separate job. Server packages are compiled only to provide their fixtures. The browser matrix and separate Engine.IO WebTransport suite are not executed by this job; these are not silently described as a complete upstream platform run.

`swift test --enable-code-coverage` exports LLVM coverage. The summary counts only `Source/SocketIO`, not tests. Execution coverage and scenario parity remain separate metrics.

After the added native mappings, the static inventory contains 297 runtime declarations plus 14 type declarations, with **44 still unmapped**, **70 candidate-existing**, **89 focused regressions**, **36 platform-specific**, **15 API differences** and **43 unsupported-feature** entries (type entries are separate). Mapping a transferable invariant is not certification of a whole JS API.

For a deliberately strict completeness check:

```sh
python3 scripts/check-parity-contracts.py --strict
```

This fails while applicable or unsupported runtime rows remain uncertified. The ordinary CI check is a reviewed-contract/backlog regression gate, not an assertion of 100% coverage.

## Still outside this change

There is no claim of complete JavaScript parity or a production-release approval. WebTransport, compression configuration, browser/Node-specific APIs, JS manager caching and custom JSON hooks remain explicit boundaries. Legacy acknowledgement behavior remains separate; async cancellation-aware emits still bypass the ordered retry queue. A coherent end-to-end retained-memory/backpressure policy, strict concurrency/TSan, deterministic scheduling of every timer, and physical-device/background/network-transition validation are not completed here. Existing parser/encoder safety limits are not weakened to imitate unlimited JS acceptance.

The older `ProtocolParityReview.md` is historical except where explicitly updated by this follow-up. In particular, JS promise acknowledgements without a timeout **do reject on disconnect** (`emitWithAck` marks its callback `withError`); they are not intentionally left pending forever.
