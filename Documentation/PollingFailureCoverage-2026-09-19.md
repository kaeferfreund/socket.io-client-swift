# Follow-up: polling POST failure and stale acknowledgements

This follows the 96 uncovered lines measured at `fdf9280`. The purpose is to
close meaningful behavioral gaps, not to force every defensive branch to run.
No production Swift code or coverage exclusions changed.

## New transport contracts

`SocketPollingCloseTest` now tests both an actual URLSession network failure
(`URLError.networkConnectionLost`) and an HTTP 503 response during a polling
POST. A per-session URLProtocol controls responses; an explicit observation of
the outstanding GET makes cancellation assertions independent of scheduling.

Both tests assert:

- The first POST is in flight and the second write is queued before failure.
- The client receives exactly one error and one `transport error` close, with
  the same structured error object. Network error domain/code or HTTP status
  and response body are retained as appropriate.
- The old long poll is cancelled, session is detached, write flags and queued
  packets are cleared, and both local completions execute exactly once.
- The queued packet is not sent after failure. A new handshake yields a fresh
  SID and a subsequent write reaches that session, with no duplicate old error/close.

Tests:
`testNetworkFailureDuringPostSettlesWritesOnceAndAllowsFreshSession` and
`testHTTPFailureDuringPostPreservesResponseAndAllowsFreshSession`.

## Stale timer and retry callback disposition

The existing tests already drive the relevant scenarios without racing sleeps:

- `testReplacingAnAckIDCannotFireItsOldTimer`: enqueue a zero-delay timer,
  replace its registration before yielding the owning queue, then drain.
  Strengthened assertions check that the replacement remains registered,
  duplicate acknowledgements fire no second callback, the old callback stays
  silent, and the registry ends empty.
- `testReconnectRetiresOldAckAndOldDisconnectCannotCancelNewAttempt`: reconnect
  before the queued cleanup executes, then submit old/current acknowledgements.
  Strengthened assertions check that stale input preserves the current ID and
  packet count, and duplicate/late replies leave no pending entry or extra send.
- `testAsyncRegistrationSharesRetryQueueAndIgnoresLateAcknowledgements` already
  covers controlled attempt timeouts, late replies and exact callback/async
  send order. Cancellation while queued, in flight and reconnecting is covered
  by `testCancellationRemovesWaitingInflightAndReconnectingRetryEntries`.

The internal stale-timer guard and stale retry callback guard remain defensive.
On the documented owning queue, replacing/removing an ack cancels its timer;
late server replies find no registry entry and cannot invoke the retry callback.
The callback is synchronous once removed from that registry. No production
scheduler hook or private-state mutation was added just to bypass these earlier
checks. This is a reachability argument for the supported queue contract, not
permission to remove those guards.

## CI runtime regression encountered

A preceding CI update moved the pinned original JS suites from Node 24 to 26.
On Node 26.9.0 their unchanged Mocha/tsx/yargs dependency graph failed before any
test ran (`require is not defined in ES module scope`). Only that reference-job
runtime was restored to Node 24. The reference SHA, dependency lockfile and test
contents were not modified. Other CI jobs retain their updated runtimes/actions.

## Validation

[CI on 69adced](https://github.com/kaeferfreund/socket.io-client-swift/actions/runs/35443462303)
passed **all seven jobs**, including **844 Swift tests, zero failures**, Thread
Sanitizer, strict concurrency, four Apple SDK builds, pinned JS suites, wire
proofs and parser comparison. All nine checker self-tests passed locally and
the strict contract checker passed against the downloaded XCTest log.

Library coverage: **6,605/6,701 lines (98.57%)**, **1,030/1,084 functions
(95.02%)**, **2,586/2,745 regions (94.21%)**. Branch coverage is unavailable.
There are still 96 uncovered lines in this individual run: relative to fdf9280,
two more polling lines executed, while two engine lifecycle guard lines did
not execute. The earlier native run on 17cfda6 also passed all 844 tests but
measured 98.54%; its separate upstream job failed on the Node 26 loader issue.
No metrics are combined across runs or exclusions added to conceal variation.

[Machine-readable evidence](ReviewEvidence/PollingFailureValidation-2026-09-19.json)
records the artifact hashes and per-file line changes. The meaningful gain is
the explicit POST-failure/reconnect contract plus stronger exactly-once and
stale-ack assertions, rather than a guaranteed monotonic line percentage.
