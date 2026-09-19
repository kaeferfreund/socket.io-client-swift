# JavaScript parity: evidence and explicit boundaries

Reference: official `socketio/socket.io` commit
`aaf2af36ec8ad05910f357a788e0e358bad32738`, audited 2026-09-18.
The checked-out client package declares 4.8.3; the commit, not a moving version
label, identifies the reviewed implementation.

**Full behavioral equivalence and complete upstream-test porting are not established.**
The previous 116-row matrix covered only socket.io-client, omitted Engine.IO and
both parsers, and contained stale/generic test pointers and inconsistent totals.
It must not be used as a coverage percentage.

| Upstream scope | Static runtime test declarations |
| --- | ---: |
| socket.io-client | 116 |
| engine.io-client | 109 |
| socket.io-parser | 34 |
| engine.io-parser | 38 |
| Total | 297 |

An additional 14 TypeScript compile-time test declarations are separate.
Parameterized declarations may expand to multiple executions. Server-side
socket.io/engine.io suites are outside this client-port inventory.

See [the full inventory](Documentation/JavaScriptTestInventory.csv),
[the review and release gates](Documentation/ProtocolParityReview.md), and
[the recorded decoder comparison](Documentation/ReviewEvidence/DecoderDifferential.json).
Inventory labels distinguish focused regressions, candidate old pointers,
unmapped rows, API differences and unsupported features. A candidate is not a
proof that all assertions of an upstream test have been ported. The round-2 pass
(2026-09-18) closed every `mapping-gap` row. The 2026-09-19 cycle-safety follow-up
adds the remaining circular-object regression: 67 rows are focused regressions,
with zero `mapping-gap` and zero `known-divergence` rows. These inventory labels
do not remove the deliberate encoding bounds or close release gate R2.

The local decoder comparison exercised 5,000 generated valid text/binary vectors
against the actual pinned JavaScript decoder and current Swift decoder, with zero
normalized-output differences. Eight of 29 malformed/noncanonical probes differ.
Three are representation only: payload-less EVENT/ACK packets (`2`, `3`, `2123`)
decode in both, JS with `data === undefined` and Swift with empty data. Five are
deliberate: Swift rejects a CONNECT or CONNECT_ERROR without payload (which JS
decodes and then fails on in `onpacket`, closing with the same `parse error`), a
binary header without payload, and a non-decimal attachment count.

The comparison also runs in the encode direction: 1,000 seeded packets — every
type, Unicode namespaces, binary at any depth — are encoded by this client and
read back by that same pinned JavaScript decoder, with zero differences. This is
parser evidence only, not complete Socket.IO lifecycle, transport or application
equivalence.

Native transport uses URLSessionWebSocketTask with separate polling URLSession.
The native queue, TLS policy, graceful polling teardown and parser limits have
focused tests. Compression, WebTransport and several JavaScript-specific APIs are
not implemented. Reconnect-event semantics now match the JavaScript manager
(`reconnect` means success and carries the attempt number; `reconnect_error` and
`reconnect_failed` exist) — a breaking change in 17.0.0, see the README. The
outgoing encoder throws instead of substituting an empty payload and rejects
cyclic Foundation graphs before bridging. Its finite node/byte/depth budgets
are deliberate deviations; full encoder parity remains an open release gate. Legacy and async acknowledgement contracts
still differ; see the review rather than treating these as browser-only
exceptions. Runtime tests, SDK builds, API compatibility and device validation
are different acceptance gates.
