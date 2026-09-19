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

## Assertion audit and coverage follow-up (2026-09-19)

31 formerly uncertified declarations now have reviewed native assertion contracts:
20 encoder/binary round trips, seven malformed/reset parser scenarios, and four
server-acknowledgement/UTF8/auth scenarios. Round trips check decoded type,
namespace, acknowledgement ID, complete data and attachment completion rather
than only an encoded string. Error/reset cases use the original malformed input
sequences, with explicit native error/lifecycle adaptations. The manifest names
exact test methods; CI still requires passed executions.

Coverage-driven tests also found and fixed a real raw-ack defect: `createOnAck`
ignored its `binary` argument and allocated acknowledgement IDs before validating
raw payloads. Invalid/reserved payloads now fail before allocation; raw binary
payloads cannot silently become binary emits. Legacy success, exhaustion, duplicate
acks and conversion errors have explicit regressions.

The next audit added complete mappings for 55 more declarations: namespace and
callback ordering, volatile acknowledgements, catch-all listeners, reconnects
and timed/async acknowledgements. Volatile error-first acknowledgements now have
a real implementation with timeout and retry-bypass regressions. The bounded
[Jev audit](JevAckFollowup-2026-09-19.md) helped identify missing assertions;
its recommendations were independently checked and corrected before mapping.

A further [38-scenario continuation](ParityContinuation-2026-09-19.md)
checks packet creation and original Engine.IO payload/error cases. It fixes
namespace subscription order, autoConnect for newly created namespaces, and
Engine.IO ASCII framing/empty-payload handling. Jev assisted with bounded
comparisons; every recommendation was independently checked.

The [final 36-scenario audit](FinalParityAssertions-2026-09-19.md) completes the
supported assertion mappings, verified against the successful 801-test native run. No execution
coverage percentage implies semantic equivalence.

## Evidence and CI contracts

`JavaScriptParityContracts.json` gives exact XCTest symbols and assertions for selected reviewed contracts. CI requires these symbols to exist **and to appear as passed executions** in the current Swift log. It also compares every CSV declaration identity with a newly generated AST inventory of the pinned JS checkout. Checker self-tests reject fake symbols, absent execution evidence and unreviewed backlog changes.

The original Node client suites are executed in a separate Node 24 job (matching the pinned upstream CI), including the Engine.IO default, Fetch and built-in WebSocket modes. Server packages are compiled only to provide their fixtures. The browser matrix and separate Engine.IO WebTransport suite are not executed by this job; these are not silently described as a complete upstream platform run.

`swift test --enable-code-coverage` exports LLVM coverage. The summary counts only `Source/SocketIO`, not tests. Execution coverage and scenario parity remain separate metrics.

The inventory now contains 297 runtime declarations plus 14 type declarations:
195 fully mapped focused regressions, 38 platform-specific, 28 API differences
and 36 unsupported-feature entries, with zero candidate or unmapped declarations.
Seven transport scenarios moved from unsupported to implemented, and now have
complete original-scenario assertions.
For a deliberately strict completeness check:

```sh
python3 scripts/check-parity-contracts.py --strict
```

This fails while supported runtime rows remain uncertified; reviewed unsupported-feature exclusions are explicit and validated. CI now runs this strict check together with current passed-XCTest evidence.

## Still outside this change

There is no claim of complete JavaScript parity or a production-release approval. WebTransport, compression configuration, browser/Node-specific APIs, JS manager caching and custom JSON hooks remain explicit boundaries. Callback, async and legacy acknowledgements now share ordered retry delivery, with async cancellation cleanup and socket-specific overrides. General pre-connect reception is buffered. Transport lists, fallback and remembered upgrades are implemented. Strict concurrency and TSan have passed in macOS CI. Paired lifecycle traces, deterministic scheduling of every timer, and physical-device/background/network-transition validation remain open. Existing parser/encoder safety limits are not weakened to imitate unlimited JS acceptance.

The older `ProtocolParityReview.md` is historical except where explicitly updated by this follow-up. In particular, JS promise acknowledgements without a timeout **do reject on disconnect** (`emitWithAck` marks its callback `withError`); they are not intentionally left pending forever.
