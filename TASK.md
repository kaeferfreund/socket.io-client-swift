# Task: JS-aligned disconnect reasons (socket.io-client v4.8.3 parity)

You are implementing one open parity gap in this Swift port of socket.io-client.
Everything you do must follow the JS client's observable behavior exactly.

## Hard constraints

- Do NOT push. Do NOT open PRs. Commit on the current branch (`feat/js-disconnect-reasons`) with the repo's commit-message style (`fix(scope): ...` style, see `git log --oneline`).
- You CANNOT build or run tests on this Linux machine (the project only builds on macOS in CI). Use `swiftc -parse <file>` for syntax checks on every file you touch. Do not claim tests pass — CI will decide.
- Do NOT touch reconnection logic, the ack system, or the send buffer. This task is ONLY about the reason strings surfaced to the application.
- Do NOT add third-party dependencies.
- Code style: mimic the surrounding code; comments are used heavily in this repo to record JS-alignment rationale — write them in the same style (English).
- Docs are part of the deliverable: update `PARITY.md` and `CHANGELOG.md` (top, `## Unreleased`).

## Background

The client fires a `.disconnect` client event whose first payload item is a
String reason. JS `socket.on("disconnect", reason => ...)` reasons
(socket.io-client v4.8.3, `lib/socket.ts` + engine.io-client) are exactly:

- `"io server disconnect"` — the server sent a DISCONNECT packet
- `"io client disconnect"` — the app called `socket.disconnect()` (or manager teardown of this socket)
- `"transport close"` — the engine connection closed without an error (network drop, server closed the socket)
- `"transport error"` — the engine errored
- `"ping timeout"` — server closed the connection due to a missed pong (engine.io close reason)
- `"parse error"` — an undecodable packet closed the engine

## Current Swift state (audit with grep before editing)

Reason strings currently surfaced via `didDisconnect(reason:)` / `engineDidClose(reason:)`:

- `"Got Disconnect"` — `Source/SocketIO/Client/SocketIOClient.swift` (~line 925), server-initiated DISCONNECT packet → must become `"io server disconnect"`.
- `"Disconnect"` — `Source/SocketIO/Manager/SocketManager.swift` (`disconnect()`, engine close reason) and `"Namespace leave"` (`disconnectSocket` / leave paths) → both are app-initiated disconnects → must become `"io client disconnect"`.
- `"Manager Deinit"` and `"Adding new engine"` — `SocketManager.swift` teardown paths → app-initiated from the app's perspective → must become `"io client disconnect"`.
- `"manual reconnect"` / `"reconnect"` — engine close reasons used when tearing down an engine to reconnect → these are NOT app disconnects and JS never surfaces a disconnect reason for them (reconnection is transparent: the socket only sees the transport close). Map them to `"transport close"`.
- `"timeout"` — connect-timeout close → KEEP AS-IS (documented Swift divergence: JS has no disconnect after a failed open; the Swift manager closes the engine and reconnect loops rely on this; several tests depend on it).
- `"Reconnect Failed"` — terminal reconnection state → KEEP AS-IS (Swift-specific; JS exposes `reconnect_failed` as a manager event instead — separate gap, do not touch).
- `"parse error"` — already JS-aligned, keep.
- The native engine (`Source/SocketIO/Engine/SocketEngine.swift`, URLSession transport) reports close reasons for network drops and errors. Currently error-based closes surface the error description as the close reason. Split them:
  - a clean remote/local close (URLSession reports the task/session ended without an error, server closed) → `"transport close"`
  - an error-based close (`didError` path, URLSession error, TLS rejection) → `"transport error"` for the disconnect reason (the engine may keep its detailed error text for logging and for the `.error`/`.connectError` payload — do not lose the detail there; align ONLY the disconnect reason).
  - if the server sends an engine.io CLOSE packet whose reason is `"ping timeout"` (or a close code mapping to it), surface `"ping timeout"`. Look at how the native engine parses the engine.io CLOSE packet (`Source/SocketIO/Engine/`) and pass the server's reason through when it is one of the JS reasons; otherwise fall back to `"transport close"`.

IMPORTANT: keep the strings used INTERNALLY (e.g. what the manager keys on) consistent — first grep the whole `Source/` and `Tests/` tree for each string to find every comparison (`==`, `contains`, switch cases) before renaming anything. If internal logic compares against a reason string, introduce the mapping at the boundary where the reason is surfaced to the socket (a single place, e.g. a small `static func jsReason(for:)`-style helper or explicit constants), rather than string-matching at many call sites.

## Tests

`grep -rn` the old strings under `Tests/` and update assertions that pin the old
client-facing strings (e.g. `"Got Disconnect"`, `"Disconnect"`, `"Namespace leave"`).
Be careful:

- Tests asserting `"Reconnect Failed"` or `"timeout"` must remain untouched.
- Do not weaken assertions: if a test asserted the exact reason, keep asserting the exact (new) reason.
- If a behavior-coupling becomes visible (e.g. a test relied on an internal string that never reached the app), adjust minimally and explain in the commit message.

## Docs

- `PARITY.md`: the "Open gaps" section lists disconnect reasons as a gap — remove/rewrite that bullet to reflect closure, and note the two kept divergences (`"timeout"`, `"Reconnect Failed"`) explicitly.
- `CHANGELOG.md`: add an entry under `## Unreleased` → `## Fixes` describing the JS-aligned reasons.

## Definition of done

1. All source changes + test updates in `Source/` and `Tests/`.
2. `swiftc -parse` clean on every touched file.
3. `PARITY.md` + `CHANGELOG.md` updated.
4. One or more commits on `feat/js-disconnect-reasons` (no push).
5. Finish with a short report: what you changed, the exact mapping table you implemented, which tests you updated, and anything you deliberately left alone.
