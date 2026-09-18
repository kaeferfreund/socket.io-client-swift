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
Inventory labels distinguish focused regressions, candidate old pointers, missing
mappings, API differences and unsupported features. A candidate is not a proof
that all assertions of an upstream test have been ported.

The local decoder comparison exercised 5,000 generated valid text/binary vectors
against the actual pinned JavaScript decoder and current Swift decoder, with zero
normalized-output differences. Eight of 29 malformed/noncanonical probes differ:
Swift deliberately rejects truncated/missing payloads and non-decimal attachment
counts accepted by that JavaScript snapshot. This is decoder evidence only, not
complete Socket.IO lifecycle, transport or application equivalence.

Native transport uses URLSessionWebSocketTask with separate polling URLSession.
The native queue, TLS policy, graceful polling teardown and parser limits have
focused tests. Compression, WebTransport and several JavaScript-specific APIs are
not implemented. Swift reconnect-event semantics and legacy/async acknowledgement
contracts still differ; see the review rather than treating these as browser-only
exceptions. Runtime tests, SDK builds, API compatibility and device validation
are different acceptance gates.
