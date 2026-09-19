# Original-scenario audit continuation

Reference: `aaf2af36ec8ad05910f357a788e0e358bad32738`.
This batch adds 38 complete mappings to the previous 74-item backlog. There are
36 supported runtime declarations still without complete assertion certification.
No feature exclusions or checker acceptance rules were broadened.

## Behavior changes found through the original tests

- Manager callbacks and namespace CONNECT packets follow subscription order,
  including when socket creation order differs. An unordered Swift dictionary
  previously determined the order.
- Opting into autoConnect also connects newly created namespaces, including
  after the engine is already open. The old native test and documentation
  incorrectly asserted that JS only auto-connects the root. The default remains
  false; a separate test preserves explicit-connect behavior when disabled.
- An empty Engine.IO polling payload is a parser error, not a silent no-op.
  Malformed packets expose the native error callback with `parser error`.
- Engine.IO packet types require ASCII digits. Decode removes exactly the ASCII
  type byte rather than a Swift grapheme, preserving a combining scalar at the
  start of message data. Arabic/fullwidth/superscript digits are rejected.

## Assertions strengthened

Real polling and WebSocket fixtures check original binary reception, binary send,
JSON fields surrounding binary attachments, namespace cache behavior, CONNECT/
DISCONNECT order, retry ACK IDs and packet order, query values while connecting,
connection errors, reconnection IDs and negative error assertions.

The packet recorder wraps the real engine, not a simulated transport. It
canonicalizes only the equivalent explicit root namespace spelling (`0/,` to
`0`, `1/,` to `1`). Payloads, acknowledgement IDs and all other frames are exact.

Parser tests cover every original malformed input and native error category.
Swift's String/Data-typed decoder entry points statically reject a JS-style
integer argument. Packet validity is checked through its wire representation at
the native decoder boundary. Data replaces JS binary container types; the
legacy base64 fallback retains its exact bytes and actual base64 negotiation.

Engine tests send the original six maxPayload messages, including 33 euros at a
100-byte limit; verify oversize input followed by another queued packet; require
error details before close (HTTP status, body and object identity); verify
WebSocket close code/reason; and test explicit rememberUpgrade false after a
real polling-to-WebSocket upgrade.

## Delegated evidence, checked independently

Two read-only Jev batches inspected eight codec and eight transport scenarios:
[codec inputs/results](ReviewEvidence/JevCodecEvaluation-2026-09-19.json),
[transport inputs/results](ReviewEvidence/JevEngineEvaluation-2026-09-19.json).

Corrections to the recommendations matter:

- A hand-constructed `"4test"` string was not accepted as an encoder test. The
  revised test calls the real packet encoder.
- Separate text and binary result arrays did not prove mixed delivery order.
  A combined delivery sequence now does.
- Empty payload was an additional implementation edge case, not one of the
  original JS-286 test's three inputs.
- JS-285 remains open: the standalone JS parser returns all packet objects,
  whereas native decoding and transport dispatch share a path that stops at
  CLOSE. Tests of only the prefix must not certify the complete parser scenario.
- Jev's priority/confidence numbers are not coverage percentages or evidence of
  executed tests. All mappings remain subject to actual CI PASS verification.

## Validated execution and coverage

[CI on b6f419b](https://github.com/kaeferfreund/socket.io-client-swift/actions/runs/35439479917)
passed all seven jobs, including 783 Swift tests with zero failures, Thread
Sanitizer, strict concurrency, four Apple SDK builds, pinned upstream suites,
parser differential and wire proofs. The contract checker passed against the
exact XCTest log. All eight offline checker regressions passed.

Library-only coverage: 6,203/6,608 lines (93.87%), 955/1,067 functions (89.50%),
2,329/2,665 regions (87.39%). Branch coverage is not available.

Of 297 runtime declarations, 159 have complete native assertion contracts and
current passed tests, 102 are documented API/platform/feature boundaries, and
36 supported declarations remain uncertified. The inventory has eight candidate
mappings and 187 focused regressions (including still-limited native adaptations).
The strict completeness gate therefore continues to fail. No release was made.
