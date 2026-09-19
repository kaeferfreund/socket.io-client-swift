# 17.0.0 release preparation

Status: **unreleased; publication blocked**. The requested stable release is
authorized once validation passes. No `v17.0.0` tag or public release has been
created. The podspec and framework now declare 17.0.0; the podspec uses the
immutable `v17.0.0` tag that will be created on the validated release commit.
Until then, development consumers must pin a commit explicitly.

## Additional parity corrections

When explicitly enabled, `autoConnect(true)` now also connects newly created
namespaces, matching the JavaScript client. The default remains false. Namespace
CONNECT packets and lifecycle callbacks follow subscription order. Engine.IO
framing requires ASCII packet type digits, preserves combining Unicode scalars
in text data, and reports an empty polling payload as a parser error.
Raw Engine.IO binary sends now produce one packet without an attachment header.
The shared codec decodes packet framing independently of transport CLOSE handling.
A parser failure replaces the native engine on reconnect; low-level delegates can
observe completed/failed Engine.IO upgrades separately from the HTTP handshake.

## Draft release notes

Socket.IO-Client-Swift 17 targets Socket.IO 4 servers using Engine.IO 4 over
HTTP long-polling and WebSocket. It requires Swift 6.4 / Xcode 27, with Swift 6
language mode, iOS/tvOS 15, macOS 12 or watchOS 9.

- Apple's URLSession replaces Starscream; there are no third-party Swift
  dependencies. TLS uses system validation, with explicit pinning/private-anchor
  configuration where required.
- Ordered retries now include callback, async and legacy acknowledgement entry
  points. Async cancellation removes queued/in-flight work. Individual namespaces
  can override acknowledgement timeouts and retry counts.
- Events received before namespace connection are buffered and delivered before
  outgoing buffered events and the connect notification, including binary events.
- Transport lists, `tryAllTransports` and `rememberUpgrade` support polling and
  WebSocket. Opening failures can try the next configured transport.
- Reconnection uses JavaScript-style backoff and event semantics. Pending
  acknowledgements are cleaned up on transport loss, and the last active
  namespace disconnect closes the manager.
- Parser/encoder validation and optional buffer limits protect malformed input
  and retained data. Encoding failures no longer substitute a different packet.

### Migration

Remove `SocketIOVersion` and `.version(...)`; the engine always uses Engine.IO 4.
Remove obsolete `compress`, `selfSigned`, `enableSOCKSProxy` and `useCustomEngine`
options. Obsolete dictionary keys fail configuration validation instead of being
silently ignored. See [the native migration guide](NativeWebSocketTransport.md)
and [Swift 6 / Socket.IO 4 migration](SocketIO4Swift6Migration.md).

Reconnection event payloads and timing changed; consult the
[breaking-change table](../README.md#breaking-changes-in-1700).
Automatic server-cookie replay requires `withCredentials(true)` and uses an
isolated engine-owned cookie jar. `autoConnect` remains false by default.
Use the manager and sockets on their serial `handleQueue`; they are not Sendable.

### Scope and limitations

WebTransport **and its stream codec are explicitly unsupported**. This release
targets polling and WebSocket. Custom per-transport constructors and JavaScript's
compression switches/Deflate thresholds are also unsupported. URLSession deflate
interoperability does not imply that those controls exist. Parser safety limits
and documented Swift/platform API differences remain intentional.

All 195 applicable original runtime declarations now have complete native
assertions and passed execution evidence in the 801-test suite. The other 102
runtime declarations retain explicit API/platform/unsupported-feature reasons.
This scoped assertion audit is complete; it is not proof of all possible client
behavior or a device/release certificate. See [PARITY.md](../PARITY.md).

## Publication gates

- [x] Complete the supported original-test assertion audit and validate all 195
  mappings against the successful 801-test native log; see [final audit](FinalParityAssertions-2026-09-19.md).
- [ ] Finish the paired lifecycle traces and rerun
  `python3 scripts/check-parity-contracts.py --strict --swift-log <current-log>`
  against the complete successful Swift log for the release commit. Do not
  weaken this gate or convert missing supported behavior to exclusions.
- [ ] All seven CI jobs pass on the release commit: native suite, TSan, strict
  concurrency, four Apple SDK framework builds, pinned upstream suites,
  parser differential and wire proofs.
- [x] Encoder gate R2 closed with documented deviations (2026-09-19); R3 and
  the scheduling half of R4 deferred to after 17.0.0 as architecture work
  without a demonstrated defect; see [ProtocolParityReview.md](ProtocolParityReview.md).
- [ ] Record the outstanding TimeMonkey/Bun upgrade and Apple-device runtime
  checks from [REMAINING-WORK.md](../REMAINING-WORK.md).
- [ ] Validate independent Swift Package, framework and CocoaPods consumers
  against the final immutable release tag before publishing the GitHub release.

Once the pre-tag gates pass, merge the reviewed follow-up, rerun CI on the exact
release commit, and create `v17.0.0` on that commit. Validate tagged consumers and
publish these notes after updating this status with the actual results. Do not
move an existing published tag. CocoaPods registry publication is a separate
distribution operation; the Git-backed podspec alone does not publish a pod.

## Evidence so far

- [e06d5be CI](https://github.com/kaeferfreund/socket.io-client-swift/actions/runs/35433419941):
  all jobs passed, including 715 Swift tests and zero strict-concurrency warnings.
- [e63dc0e CI](https://github.com/kaeferfreund/socket.io-client-swift/actions/runs/35433653301):
  all jobs passed after transport ordering/fallback/remembered-upgrade changes.
- [43bbe47 final audit CI](https://github.com/kaeferfreund/socket.io-client-swift/actions/runs/35440824938):
  all seven jobs pass, including 801 Swift tests and the strict checker against
  the actual log. All 195 applicable runtime declarations are covered by complete
  native assertion mappings; library line coverage is 93.97%.
- [69adced coverage follow-up CI](https://github.com/kaeferfreund/socket.io-client-swift/actions/runs/35443462303):
  all seven jobs passed, including 844 Swift tests with zero failures. Latest
  validated library-only line coverage is **98.57% (6,605/6,701 lines)**; see
  [coverage evidence](ReviewEvidence/PollingFailureValidation-2026-09-19.json).


These earlier runs do not certify later release-preparation commits.
