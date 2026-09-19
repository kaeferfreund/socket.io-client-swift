# Remaining native-client parity review

Baseline: `master` at `c905f4f869bdd208ad04269a855e3ac2438abddd`.
Official reference: `socketio/socket.io` at `aaf2af36ec8ad05910f357a788e0e358bad32738`.
Scope: client, client transport and codecs only. The Node server is a fixture, not a port target.

## Meaning of the result

All **44 previously unmapped declarations** now have an explicit disposition:
**29 native regression mappings, 13 API differences and 2 platform differences**.
This is a complete classification of that backlog, **not 100% JavaScript scenario parity**.
The inventory still contains 70 candidate mappings and unsupported features.
A native `Data` adaptation does not certify the JavaScript `Blob`/prototype API.
An original Node suite passing does not prove that Swift has every corresponding assertion.

`JavaScriptParityContracts.json` records the original 44 IDs, each reason and each
native executable contract. The normal gate verifies the test symbols and their
actual passed XCTest executions. It also rejects missing or inconsistent
dispositions. `check-parity-contracts.py --strict` still intentionally rejects a
full-parity claim; unsupported and uncertified rows remain.

## Production changes and migration

| Option | Default | Native contract |
| --- | --- | --- |
| `.withCredentials(Bool)` | `false` | Opt into accepting and resending server cookies using an isolated engine-owned Foundation cookie jar. |
| `.forceBase64(Bool)` | `false` | Encode WebSocket binary payloads as Engine.IO base64 text and request base64 server responses with `b64=1`. Polling already uses base64. |
| `.addTrailingSlash(Bool)` | `true` | Append one slash after normalizing the configured transport path; `false` leaves the trailing slash off. |

**Cookie migration:** server-cookie replay is now opt-in and no longer uses the
application-wide shared cookie store. Applications relying on an automatically
accepted session cookie must set `.withCredentials(true)`. Explicit `.cookies(...)`
and explicit `Cookie` headers remain explicit, including when the flag is false;
the latter is not a browser CORS or ambient-credential sandbox.

The private jar persists across engine reconnects and polling-to-WebSocket upgrades,
not across independent engine instances. Create a new manager when changing a
cookie-authenticated identity. Foundation applies native domain/path/security and
expiration semantics; the implementation does not recreate Node's name-only jar.

`SocketTransportError` carries transport, operation, HTTP status, optional response
text, WebSocket close code/reason and underlying native error. Client event data
retains its existing reason at index 0 and appends detail at index 1 where available.
The response text is at most 4096 UTF-8 bytes, including after invalid-input
replacement. Its description excludes response text, request URL and headers.
The body and underlying native error are still untrusted diagnostics and may
contain sensitive server/native content; do not log the whole object indiscriminately.

An HTTP error during polling supplies the actual response status/body. A failed
WebSocket handshake may expose only a native error, not its HTTP rejection status.
A received close code (for example 1009) survives an outstanding receive failure:
it is captured before cancellation and remains a transport close rather than an
invented generic error. Existing reason-only custom engine delegates have a fallback;
subclasses handling manager engine callbacks should consider the new typed overloads.

## The 29 native regression mappings

| IDs | Evidence and adaptation |
| --- | --- |
| JS-133 | Forced polling base64 echo, bytes 0...4 and actual `bAAECAwQ=` POST body. |
| JS-137, JS-144 | Direct WebSocket plus completed polling-to-WebSocket upgrade; base64 text frames, `b64=1`, empty binary and byte preservation. |
| JS-139, JS-140 | Polling binary input/output using native `Data`, not browser `Blob`. |
| JS-141 | 72/20/20/20/72-byte payload boundaries, ordered echo and actual POST byte counts bounded by server `maxPayload=100`. |
| JS-142, JS-143 | WebSocket binary input/output using native `Data`; actual binary frame observation. |
| JS-145, JS-146 | Raw Engine.IO open, unsolicited server `hi` greeting, callback ordering and nonempty session ID, separately for polling/WebSocket. |
| JS-147, JS-148 | Exact upstream euro-string and Unicode scalar endpoint cases. |
| JS-165 | No trailing slash on the actual HTTP path; option order/default normalization separately tested. |
| JS-178, JS-179 | Server cookies sent/not sent on polling and upgrade; reconnect persistence, independent jars and explicit-header semantics. |
| JS-180, JS-182 | Native parsing of the original simple and embedded-equals/ampersands cookie name/value inputs. |
| JS-194, JS-195 | Actual 413 polling rejection and 1009 WebSocket closure for a payload beyond the server limit. Native detail and close reason are asserted. |
| JS-196, JS-197 | Actual stale-SID rejection in polling and WebSocket, with native error/close metadata rather than fabricated XHR/CloseEvent objects. |
| JS-220, JS-223 | Actual custom header on both polling GET and POST; browser CORS and XHR constructors are not native APIs. |
| JS-240, JS-242 | Original ArrayBuffer/TypedArray payloads as Data, exact independent header/attachment assertion and sliced-buffer boundaries. |
| JS-246, JS-247, JS-248 | Original simple, nested `/deep` id-999 and binary ACK inputs as Data, with reconstruction and payload equality. |
| JS-257 | Public native packet-type wire values 0...6. |

These entries are explicitly marked by contract kind. A reviewed transferable-wire,
native-cookie, native-error or native-data regression is not silently promoted to a
literal JavaScript API/type assertion port.

## The 15 explicit boundaries (not counted as equivalent ports)

| IDs | Decision |
| --- | --- |
| JS-138 | Platform: deleting JavaScript `ArrayBuffer` and returning its fallback wrapper has no native runtime counterpart. The base64 wire path is covered separately. |
| JS-158 | API: no standalone Engine.IO module `protocol` export. Native EIO 3/4 query values are separately tested. |
| JS-163, JS-164, JS-168, JS-169, JS-170, JS-171 | API: JS host/port/secure object constructors and location defaults are replaced by explicit Foundation URLs. The already mapped absolute-URL tests are not falsely relabelled as these overloads. |
| JS-172 | API: no identical internal eight-character `randomString` helper. No cryptographic guarantee was implied by that original test. |
| JS-181 | API/policy: the Node parser returns only name/value/expires and overwrites conflicting expiry attributes in header iteration order. Foundation preserves security scope and owns native expiration policy. Its object/expiry result is not certified identical for that conflicting header. |
| JS-183 | API: no identical public `parseuri` result or shorthand-input grammar. Native absolute transport URL tests remain separate. |
| JS-186 | API: `transports: []` is not expressible by the native fixed transport selection. Contradictory force options have a separate reject-before-network regression. |
| JS-201, JS-202 | API: no artificial public JS Transport/Polling/WebSocket constructors; native SocketEngine/internal protocols remain the supported surface. |
| JS-241 | Platform: JavaScript null-prototype objects have no Swift dictionary equivalent. Special dictionary keys and binary values receive a separate native regression, not a prototype-port claim. |

## Test-harness corrections and evidence

The raw Engine.IO fixture observes bytes without installing a `data` listener.
A data listener resumes even a bodyless GET, prematurely emitting the request's
`close` before the held polling response. A separate Node regression now proves
that observation does not consume or close the request and records the exact body.
The first native preflight caught this fixture defect; tests were not skipped or
weakened to hide it.

An existing async acknowledgement test used synchronous XCTest waits inside
`MainActor.run`, blocking the executor needed to finish the fake connection. It
now awaits initial connect, actual fake-transport write registration and reconnect
separately. It still asserts the disconnect error and empty acknowledgement registry.

The permanent CI runs committed source directly, including full native tests,
passed-contract checks, library coverage, SDK builds, wire proofs, pinned original
Node client suites and finite encoder/decoder comparisons. Temporary export and
materialization workflows are not part of the final source tree.

Physical Apple-device/background coverage, a complete browser/WebTransport matrix,
compression configuration, full concurrency validation and assertion-level
certification of all remaining candidate mappings are not supplied by this change.
Use the current PR's pinned commit and CI artifacts for measured counts; this
classification document is not a timeless green-build certificate.
