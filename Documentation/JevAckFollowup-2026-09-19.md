# Jev follow-up: acknowledgement assertion audit

The user authorized delegating bounded comparisons to the installed read-only
OpenCode Jev agent. The first delegated batch covered exactly JS-094, JS-095,
JS-096, JS-097, JS-098, JS-100, JS-101 and JS-105 against upstream
`aaf2af36ec8ad05910f357a788e0e358bad32738`. Reconnect work proceeded independently
and passed all seven CI jobs at `7be2fa5` (run 35436799492).

[Exact evaluator inputs and outputs](ReviewEvidence/JevAckEvaluation-2026-09-19.json)
are advisory source-review evidence, not executed test proof. Two Jev calls used
8,530 input and 1,015 output tokens (9,545 total), with 972 ms evaluation time.
The coordinator separately reported USD 0.42655; this is not a combined billing
statement for both providers. No additional agents or recursive reviews ran.

## Source review and resulting changes

| ID | Source-verified conclusion and action |
| --- | --- |
| JS-094 | Existing timeout and send-buffer tests already covered most behavior. Strengthen the existing send-buffer test to assert zero retained packets *inside* the timeout callback, using the available native test snapshot. No duplicate suite needed. |
| JS-095 | The existing live-server test waited for connection first. Add the original pre-connect `unknown` emit with a 50 ms timeout. |
| JS-096 | Add original zero-timeout `echo(42)` and exactly-one-callback assertion after 200 ms. Also exercise the established-connection case with a following server ACK as a wire-order barrier. Count **all** callbacks: the coordinator's suggested conditional increment would miss an erroneous second successful callback. The original pre-connect test itself does not guarantee a late wire ACK because its packet can expire in the send buffer. |
| JS-097 | Do not accept `ping`/`pong` or default-timeout `echo("a")` as a complete substitute. Add explicit timed callback `echo(42)`, nil error and integer 42, issued while connecting. Scale the positive timeout for CI, documenting the adaptation. |
| JS-098 | Add real-server async `emitWithAck("unknown")` rejection with 50 ms timeout; retain existing unit coverage. |
| JS-100 | Exercise the original pre-connect `unknown` emit with inherited default ackTimeout and no explicit timeout wrapper. |
| JS-101 | Existing real-server modern untimed ACK test covers silent removal and no callback after disconnect. Record that exact method; do not rely on the legacy sentinel API. |
| JS-105 | Add public disconnect immediately behind a real outgoing async timed `echo("a")`; require `.disconnected` before its ten-second timer and an empty ACK registry. |

Static mappings and actual passing executions remain separate. The normal
contract checker validates the mappings and CI verifies the mapped methods
passed. The strict full-parity gate still rejects the remaining unsupported-by-
evidence scenarios; no exclusions or checker acceptance rules were broadened.
