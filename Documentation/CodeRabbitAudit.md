# CodeRabbit finding audit, 18 September 2026

## Scope and evidence

Repository: `kaeferfreund/socket.io-client-swift`. The default/main branch is named
`master`, not `main`. Audit baseline: `b613ef4c501df7b1ac32911b9a211312f496410b`.

All 17 pull requests, open and closed, were retrieved at 2026-09-18 16:02 UTC.
The snapshot includes paginated PR reviews, inline review comments, conversation
comments, and review threads (including resolved/outdated state and replies).
It is preserved in Actions run
[35366016431](https://github.com/kaeferfreund/socket.io-client-swift/actions/runs/35366016431),
artifact `coderabbit-audit-snapshot`. Findings were checked against the baseline
source, not assumed fixed because a PR was merged or a thread was resolved.
No instructions embedded in bot comments were executed.

There are **six submitted CodeRabbit reviews with 12 concrete finding occurrences**:
nine inline comments, two outside-diff comments, and one nitpick. Several repeat
or refine the same issue. All nine inline threads were unresolved at retrieval.
The manager's timeout docstring and part of the reconnect test were already fixed;
the remaining portions are addressed in this follow-up.

## Every pull request checked

| PR | State at retrieval | CodeRabbit review evidence |
| --- | --- | --- |
| #1 | Merged | In-progress/automatic summary only; no submitted review or inline finding |
| #2 | Merged | 2 inline findings, both addressed below |
| #3 | Merged | In-progress/automatic summary only; no submitted review or inline finding |
| #4 | Merged | 2 inline findings, strengthened tests below |
| #5 | Merged | 1 inline finding, reconnect expectation below |
| #6 | Merged | 2 inline findings, server IDs and active-cache test below |
| #7 | Merged | In-progress/automatic summary only; no submitted review or inline finding |
| #8 | Merged | In-progress/automatic summary only; no submitted review or inline finding |
| #9 | Merged | In-progress/automatic summary only; no submitted review or inline finding |
| #10 | Merged | Administrative bot notice; no submitted review or inline finding |
| #11 | Merged | CodeRabbit skipped the non-default target branch; Copilot reported a quota limit |
| #12 | Merged | Administrative bot notice; no submitted review or inline finding |
| #13 | Merged | Administrative bot notice; no submitted review or inline finding |
| #14 | Merged | 1 outside-diff finding, partially fixed in baseline; changelog corrected below |
| #15 | Closed, not merged | Duplicate integration PR; no submitted CodeRabbit review or inline finding |
| #16 | Merged | In-progress/automatic summary only; no submitted review or inline finding |
| #17 | Merged | 2 inline findings, 1 outside-diff finding, 1 nitpick; addressed below |

**No published review is not a clean review.** In particular, this inventory does
not claim CodeRabbit approved the native migration or retries feature. It covers
all findings actually published at the retrieval cutoff, not unpublished analysis.

## Finding-by-finding disposition

| Source finding | Baseline check | Resolution and evidence |
| --- | --- | --- |
| [#2: keep the Engine.IO close in the disconnect request](https://github.com/kaeferfreund/socket.io-client-swift/pull/2#discussion_r4043396025) | Still present after migration: `disconnectPolling` queued close behind bounded application packets and could overlap an in-flight POST or be blocked by `fastUpgrade`. | Build an independent close-only request before retiring the SID. Wait on the retiring session's actual POST completions, then send close through that same session. Unsent application packets complete locally as cancelled, never get replayed by shutdown. Retain the existing one-second teardown bound. `SocketPollingCloseTest` covers bounded batches, POST ordering, paused upgrade, deadline cancellation, stale callbacks/reconnect, and EIO3/EIO4 encoding. |
| [#2: abort a timed-out poll before another GET](https://github.com/kaeferfreund/socket.io-client-swift/pull/2#discussion_r4043396027) | Still present: `Promise.race` left the losing fetch alive and started another GET. | `observePolling` has one overall deadline, aborts and awaits the fetch/body, and ends observation after timeout or terminal HTTP status. Unexpected network errors fail the proof. Six Node regression tests run in CI before the wire proofs. |
| [#4: correct the socket-ID parity claim](https://github.com/kaeferfreund/socket.io-client-swift/pull/4#discussion_r4043544521) | The cited root test only checked existence and clearing. | The fixture returns its own `socket.id` via `server-socket-id`; the root test compares that independently supplied ID with the client SID before checking disconnect clearing. |
| [#4: prove reconnection completed](https://github.com/kaeferfreund/socket.io-client-swift/pull/4#discussion_r4043544525) | Partly fixed by #5: server-side kill and a positive root connection count prevent a vacuous pass, but the test still sleeps six seconds. | Await the second actual root `.connect`, then a server round trip and raw CONNECT count. This also addresses the refinement in #5. |
| [#5: wait for the actual reconnect](https://github.com/kaeferfreund/socket.io-client-swift/pull/5#discussion_r4043582141) | The fixed six-second wait remained. | `testNoRejoinAfterAMiddlewareFailure` now has distinct first-connect/reconnect expectations, retains the refused-namespace error count, and requires exactly three raw CONNECT frames across the scenario. |
| [#6: compare root and custom IDs with the server](https://github.com/kaeferfreund/socket.io-client-swift/pull/6#discussion_r4044071519) | `/foo` only had a nonempty SID distinct from root; neither was compared with the server. | Query both root and `/foo` through their own namespace connections and assert equality with each server-provided ID. Keep the distinct-ID assertion. Update matrix descriptions to name the actual equality check. |
| [#6: test an already active cached socket](https://github.com/kaeferfreund/socket.io-client-swift/pull/6#discussion_r4044071525) | The second lookup happened before connection. | With `autoConnect` enabled, first await connection and assert `.connected`/`active`, then perform the second lookup. Verify object identity, a subsequent server round trip and exactly one raw CONNECT frame. |
| [#14: timeout event documentation](https://github.com/kaeferfreund/socket.io-client-swift/pull/14#pullrequestreview-5247987890) | `SocketManager.connectTimeout`/`connectDidTimeOut` already documented `.connectError`; the unreleased Breaking changelog still said `.error`. | Preserve the corrected manager comments and change only the stale changelog event name. Same remaining issue as #17's outside-diff finding. |
| [#17: qualify cache-busting](https://github.com/kaeferfreund/socket.io-client-swift/pull/17#discussion_r4048145656) | `PARITY.md` incorrectly claimed every poll always has `t=`. | State the default/enabled behavior, `.timestampRequests(false)` opt-out, and configurable parameter name. Qualify the matching changelog sentence too; existing timestamp-option tests remain unchanged. |
| [#17: use an engine-close reason in the active test](https://github.com/kaeferfreund/socket.io-client-swift/pull/17#discussion_r4048145671) | The direct `didDisconnect` test still supplied `io server disconnect`. | Use `transport close` and document why active survives. The separate server-DISCONNECT-packet test still verifies deactivation. |
| [#17: correct changelog timeout event](https://github.com/kaeferfreund/socket.io-client-swift/pull/17#pullrequestreview-5249546780) | Same stale `.error` entry identified by #14. | The Breaking entry now says `.connectError`, leaving timeout/close/reconnect details intact. |
| [#17: merge duplicate Reconnect Failed entry](https://github.com/kaeferfreund/socket.io-client-swift/pull/17#pullrequestreview-5249546780) | Two consecutive bullets existed; the first stopped mid-sentence. | Keep one complete bullet including the `reconnect_failed` manager-event comparison and final `.reconnect`-semantics sentence. |

## Historical pre-merge advisories

Conversation summaries also report **docstring coverage warnings** on #2 (28%),
#4 (61.11%), #5 (75%), #14 (66.67%), and #17 (42.86%), against an 80% threshold.
These are historical diff-scoped metrics, not additional line-specific defect
reports. The touched shutdown, polling, and parity-test routines are explicitly
documented in this change. A new CodeRabbit run must calculate its own coverage;
these old percentages are not represented as rerun or green. The generated
“finishing touches” checkboxes are optional actions, not findings.

## Validation and boundaries

Local checks: all changed Swift source parses; the isolated native-transport
harness passes 22 tests; the polling-observer harness passes six Node tests.
These local checks are **not** a full Apple-platform test run. The permanent
read-only `Swift` PR workflow builds/tests the final committed source on macOS,
builds the four Apple SDK framework targets, and runs both wire proofs plus the
new Node regressions. Inspect the follow-up PR's CI for commit-specific results.

No old review thread was marked resolved before this follow-up is merged. No
change was pushed directly to `master`. The temporary read-only snapshot workflow
is removed from the final source tree. The snapshot workflow never changed source,
persisted credentials, or granted itself repository write permission.
