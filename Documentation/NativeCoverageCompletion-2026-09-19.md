# Native execution coverage follow-up

This work follows the 406 uncovered library lines at `43bbe47` (6,326/6,732,
93.97%). Coverage is measured over every `Source/SocketIO` file, without adding
exclusions. It is separate from the pinned JavaScript scenario inventory.

## Verified result

[CI for fdf9280](https://github.com/kaeferfreund/socket.io-client-swift/actions/runs/35442518457)
passed all seven jobs: **842 Swift tests, zero failures**, Thread Sanitizer,
strict concurrency, four Apple SDK builds, pinned JavaScript suites, parser
comparison and wire proofs. The strict contract checker passed against the
actual XCTest log; all nine checker self-tests passed.

| Metric | Baseline 43bbe47 | Validated fdf9280 |
| --- | ---: | ---: |
| Library lines | 6,326 / 6,732 (93.97%) | 6,605 / 6,701 (98.57%) |
| Functions | 980 / 1,092 (89.74%) | 1,029 / 1,084 (94.93%) |
| Regions | 2,410 / 2,754 (87.51%) | 2,585 / 2,745 (94.17%) |
| Uncovered lines | 406 | 96 |

The suite gained 41 tests; executed library lines increased by 279 and the
line denominator decreased by 31 after dead-code removal. Branch coverage is
not emitted by this toolchain. The denominator still includes every library
source file. [Machine-readable evidence](ReviewEvidence/NativeCoverageValidation-2026-09-19.json)
records the residual file counts and SHA-256 hashes of the downloaded artifacts.

## Changes and observable contracts

- Dictionary-based configuration now honors `ackTimeout` and `retries`; wrong
  value types fail configuration validation instead of silently losing the
  requested acknowledgement policy. Typed options and manager defaults are
  unchanged.
- Public emit, raw emit, volatile emit and acknowledgement entry points reject
  reserved events and failed representations before allocating acknowledgement
  IDs or writing packets. Tests also cover released clients/managers.
- Configuration collection and conversion contracts, logging evaluation,
  broadcast, namespace removal, reconnect and successful async auth are tested.
- Third-party client/manager/engine protocol conformers exercise inherited
  defaults, including actual message packets and acknowledgement delivery.
- Parser diagnostics, manual packet encoding failure, non-string Foundation
  dictionary keys, binary policy, Foundation values and binary reconstruction
  rejection have explicit assertions.
- Polling session invalidation/retirement, malformed OPEN packets, repeated
  engine connect, binary data after close and duplicate transport receive paths
  are checked. Bounded response callbacks retain the original overflow and
  complete once despite late data/completion callbacks.

## Verified dead code removed

Repository-wide caller searches found no uses of the internal `Array.toJSON`,
`String.toArray`, `SocketIOClient.emitTest`, `SocketEngine.setClosed`, private
`SocketAck` comparison operator or DispatchWorkItem `socketAsync` overload.
Their unused helpers/shims were removed. Packet type selection now expresses
its two Boolean decisions directly, eliminating an unreachable switch default.

The old `SocketEngine.URLSession(session:didBecomeInvalidWithError:)` method
was also removed. Its capitalized spelling was not a Foundation delegate
callback; the actual session proxy owns and forwards invalidation. This removes
an obsolete public spelling in the 17 major version; callers must not invoke it
as a lifecycle API. Actual current-session invalidation is tested.

## Reachability review

[Jev's bounded advisory review](ReviewEvidence/JevCoverageReachability-2026-09-19.md)
was independently checked. Reachable dictionary and late callback cases gained
tests. Defensive code was retained:

- The argument-array cast follows normalization of an actual `[Any]`, whose
  successful normalized result is another array.
- JSON serialization follows normalization and `isValidJSONObject`; the
  throwing fallback and non-UTF-8 result guard protect unexpected Foundation
  behavior. No fabricated Foundation corruption is introduced to execute them.
- The private send encoder catch follows validation of a copied payload.
  Binary placeholder depth, nodes and bytes are already reserved during that
  first validation, so attachment substitution does not create a bypass.
- Null CoreFoundation array entries and byte-count integer overflow require
  invalid object graphs or allocations outside the supported input profile.
- `@unknown default` protects future Foundation enum cases; precondition failures
  protect internal codec invariants; the reserved-event assertion deliberately
  traps in debug builds outside XCTest. These guards are not removed for the percentage.

Other residual lines must remain described as uncovered until measured or
individually justified. A high line percentage is not complete branch coverage,
full JavaScript equivalence, or satisfaction of the separate release gates.

## Remaining measurement gaps

The 96 remaining lines stay in the denominator. They include defensive
serialization/codec fallbacks, stale timer or lifecycle exits, future Foundation
cases, and diagnostic expressions that the exercised failure paths did not
need to evaluate. Pure logging-format assertions or deliberately corrupted
Foundation containers were not added just to turn those lines green. The
existing failure, cancellation and exactly-once contracts remain tested.

This is a practical stopping point, not a proof that every remaining line is
unreachable. A new supported scenario or a reported bug can justify additional
coverage. Neither the measurement nor this disposition changes the JavaScript
inventory's feature exclusions or the separate release gates.
