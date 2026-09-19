from pathlib import Path

def change(name, before, after):
    p = Path(name)
    text = p.read_text()
    assert before in text, (name, before[:100])
    p.write_text(text.replace(before, after))

change('Tests/TestSocketIO/SocketPollingCloseTest.swift',
       '    private static var fixtures = [String: PollingCloseFixture]()',
       '    // Every access is protected by registryLock, including URLProtocol callbacks.\n    nonisolated(unsafe) private static var fixtures = [String: PollingCloseFixture]()')
change('Tests/TestSocketIO/SocketParserTest.swift',
       '        let message = "4/swift,"\n        validateParseResult(message)',
       '        XCTAssertThrowsError(try testManager.parseString("4/swift,"))')
change('Source/SocketIO/Engine/SocketEngine.swift',
       '''        if !urlWebSocket.percentEncodedQuery!.contains("EIO") {
            urlWebSocket.percentEncodedQuery = urlWebSocket.percentEncodedQuery! + engineIOParam
        }

        if !urlPolling.percentEncodedQuery!.contains("EIO") {
            urlPolling.percentEncodedQuery = urlPolling.percentEncodedQuery! + engineIOParam
        }''',
       '''        // EIO is reserved. Ignore user overrides without decoding/re-encoding
        // unrelated query values (notably '+', '/', ':' and credentials).
        do {
            var query = (urlWebSocket.percentEncodedQueryItems ?? []).filter {
                $0.name.removingPercentEncoding != "EIO"
            }
            query.append(URLQueryItem(name: "EIO", value: "4"))
            urlWebSocket.percentEncodedQueryItems = query
        }
        do {
            var query = (urlPolling.percentEncodedQueryItems ?? []).filter {
                $0.name.removingPercentEncoding != "EIO"
            }
            query.append(URLQueryItem(name: "EIO", value: "4"))
            urlPolling.percentEncodedQueryItems = query
        }''')
change('Source/SocketIO/Engine/SocketEngine.swift',
       '''        transport.onEvent = { [weak self, weak transport] event in
            self?.engineQueue.socketAsync { [weak self, weak transport] in''',
       '''        let queue = engineQueue
        transport.onEvent = { [weak self, weak transport] event in
            queue.socketAsync { [weak self, weak transport] in''')
change('Source/SocketIO/Engine/SocketEngine.swift',
       '    /// where servers do not advertise a limit.', '    /// does not advertise a limit.')
change('Source/SocketIO/Engine/SocketEngineSpec.swift',
       '''        var query = (com.queryItems ?? []).filter { $0.name != "EIO" }
        query.append(URLQueryItem(name: "EIO", value: "4"))
        com.queryItems = query''',
       '''        var query = (com.percentEncodedQueryItems ?? []).filter { $0.name.removingPercentEncoding != "EIO" }
        query.append(URLQueryItem(name: "EIO", value: "4"))
        com.percentEncodedQueryItems = query''')
change('Source/SocketIO/Client/SocketIOClient.swift',
       '''    /// Internal flag for `SocketManager._engineDidOpen` to detect that the v2
    /// root-namespace short-circuit should still surface the v2-bypass `.error`.
    /// Without this, the v2 root-nsp path never reaches `resolveConnectPayload`
    /// (where the bypass guard normally fires).
    internal var hasAuthProvider: Bool { authProvider != nil }

''', '')
change('Source/SocketIO/Engine/SocketEngineClient.swift',
       '''    /// Called when the engine sends a ping to the server. Only called in socket.io 2.
    func engineDidSendPing()

''', '')
change('Source/SocketIO/Engine/SocketEngineClient.swift',
       'Called when the engine receives a ping message. Only called in socket.io >3.',
       'Called when the engine receives a server heartbeat ping.')
change('Source/SocketIO/Engine/SocketEngineClient.swift',
       'Called when the engine receives a pong message. Only called in socket.io 2.',
       'Called when the engine receives a pong, including a WebSocket upgrade probe.')
change('Source/SocketIO/Engine/SocketEngineClient.swift',
       'Called when the engine sends a pong to the server. Only called in socket.io >3.',
       'Called when the engine answers a server heartbeat ping with a pong.')
change('Source/SocketIO/Manager/SocketManager.swift',
       '''    /// Called when the sends a ping to the server.
    open func engineDidSendPing() {
        handleQueue.socketAsync {
            self._engineDidSendPing()
        }
    }

    private func _engineDidSendPing() {
        emitAll(clientEvent: .ping, data: [])
    }

''', '')
for p in Path('Tests').rglob('*.swift'):
    p.write_text(p.read_text().replace('    func engineDidSendPing() {}\n', ''))
change('Source/SocketIO/Ack/SocketTimedEmitter.swift', 'guard depth < 512 else', 'guard depth < 1025 else')
change('.github/workflows/swift.yml', 'runs-on: macos-latest', 'runs-on: xcode-27')
change('.github/workflows/swift.yml',
       '      - name: Build without third-party Swift dependencies',
       '''      - name: Verify Swift 6.4 toolchain
        run: swift --version | grep -E 'Swift version 6\\.4'
      - name: Build without third-party Swift dependencies''')
change('Socket.IO-Client-Swift.podspec', 'For socket.io 3.0+ and Swift.', 'For Socket.IO 4.x and Swift 6.4 (Swift 6 language mode).')
change('Socket.IO-Client-Swift.podspec', ":branch => 'feat/native-urlsession-transport'", ":branch => 'master'")
change('README.md', '| Swift tools | 5.5, using the package\'s Swift 5 language mode |', '| Swift tools / compiler | 6.4, using Swift 6 language mode (Xcode 27) |')
change('README.md', '''The public API is intended for Swift. Strict Swift 6 concurrency compatibility
and an Objective-C integration are not claimed.

| Socket.IO server | Client configuration | Engine.IO protocol |
| --- | --- | --- |
| 3.x / 4.x | `.version(.three)`, the default | 4 |
| 2.x | `.version(.two)` | 3 |

`.three` also selects the mode for Socket.IO 4.x servers; there is no `.four`
option.''', '''The package and framework targets use **Swift 6 language mode** with complete
concurrency checking. The public API remains queue-based, not actor-based:
`SocketManager` and `SocketIOClient` are deliberately **not Sendable**. Configure
and use a manager and its sockets on its serial `handleQueue` (main by default).
Do not concurrently mutate callback payloads or change the queue after connecting.
The public API is intended for Swift; Objective-C integration is not supported.

| Supported Socket.IO server | Client configuration | Engine.IO protocol |
| --- | --- | --- |
| 4.x | No version option | 4 |

Socket.IO below 4 is no longer supported. Remove `.version(.two)`,
`.version(.three)` and dictionary `"version"` options; no replacement is needed.
There is deliberately no `.four` selector. Socket.IO 3 shares the modern wire
protocol, so the handshake cannot distinguish its major version, but it is
outside this fork's supported/tested server range.
See [the migration guide](Documentation/SocketIO4Swift6Migration.md).''')
change('README.md', 'For Socket.IO 3.x/4.x servers that accept an authentication payload:', 'For Socket.IO 4.x servers that accept an authentication payload:')
change('README.md', 'With a `.version(.three)` manager and a Socket.IO server configured for', 'With a Socket.IO 4.6+ server configured for')
change('README.md', '`.version(.two)` does not use recovery.\n', '')
Path('Documentation/SocketIO4Swift6Migration.md').write_text('''# Socket.IO 4 and Swift 6 migration

This is a breaking API/toolchain change, not a new runtime switch.

## Toolchain and deployment

Use Swift 6.4 or newer (Xcode 27 for the Apple SDKs). `Package.swift` requires
`swift-tools-version:6.4` and explicitly selects `swiftLanguageModes: [.v6]`.
Xcode and CocoaPods use `SWIFT_VERSION = 6.0`: compiler versions and language
modes are different settings; `SWIFT_VERSION = 6.4` is not a valid language mode.
Deployment targets remain iOS/tvOS 15, macOS 12 and watchOS 8. The new SDK warns
that watchOS 8 is deprecated; the manifest has not silently raised that floor.

## Server and configuration

Only Socket.IO 4.x is supported. Remove every `.version(...)` option and every
`"version"` dictionary entry. `SocketIOVersion`, the manager/engine `version`
properties and the obsolete `engineDidSendPing` delegate method are removed.
A dictionary version entry is an explicit configuration error, not silently
ignored. No `.four` option or replacement selector is necessary.

Engine.IO 4 is always used, including when a URL or connect parameter tries to
supply `EIO=3`. Polling uses record separators and `b`-prefixed base64 packets;
WebSocket binary frames are transmitted unchanged. Heartbeats are driven by
server PINGs and answered with PONGs. Upgrade probes still use `2probe`/`3probe`.
The Engine.IO 3 length-prefixed polling parser, binary prefix and client-driven
heartbeat timer have been removed, along with Socket.IO 2 namespace shortcuts.

The Socket.IO 3 and 4 wire protocols are shared. This change does not pretend to
identify a 3.x server from its handshake; 3.x simply is not a supported target.
Missing CONNECT `sid` and malformed legacy CONNECT_ERROR packets are rejected.
Connection State Recovery requires a configured Socket.IO 4.6+ server.

## Concurrency and asynchronous callbacks

The serial `handleQueue` ownership contract remains. The public manager, client
and engine are not declared `@unchecked Sendable`. Keep application-side access
on the configured serial queue. Internal executor handoffs have narrow audited
wrappers, and URLSession callbacks hop to the owning queue before reading state.
Do not mutate a Foundation payload concurrently with sending or callback use.
The logger facade serializes its own accesses; a custom logger's owner remains
responsible for any external concurrent access to that custom instance.

The async auth-provider overload is now `@Sendable` and returns a `sending`
payload. Capture immutable Sendable values, or obtain a fresh payload from an
actor. Do not return a dictionary containing mutable objects also retained by
another task. The callback-form provider still resolves back on `handleQueue`.

Async acknowledgement methods return `sending [Any]`. Received JSON/binary
values are snapshotted on the callback queue and materialized as fresh containers
for the awaiting task. Errors and cancellation still complete once and remove
the pending acknowledgement on its owning queue. This does not turn arbitrary
`[Any]` values into Sendable values for application-created `Task` results.

## Validation

The normal CI selects `xcode-27`, checks the Swift 6.4 toolchain, runs the complete
unit/real-server suite, builds all four Apple framework targets and compares the
parser with the pinned official JavaScript decoder. Historical review evidence
under `Documentation/ReviewEvidence` describes its recorded commit, not this
migration. Socket.IO 2 fixtures and tests are removed, not counted as passing.
''')
Path('scripts/test-native-transport.sh').write_text('''#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift test --filter URLSessionWebSocketTransportTest
''')
p = Path('Tests/TestSocketIO/SocketProtocolSafetyTest.swift')
p.write_text(p.read_text() + '''

extension SocketProtocolSafetyTest {
    func testModernConnectErrorPayloadsRemainSupported() throws {
        let manager = parser()
        XCTAssertEqual(try manager.parseString("4\\\"denied\\\"").data.first as? String, "denied")
        let packet = try manager.parseString("4/admin,{\\\"message\\\":\\\"denied\\\",\\\"data\\\":{\\\"code\\\":401}}")
        XCTAssertEqual(packet.nsp, "/admin")
        XCTAssertEqual((packet.data.first as? [String: Any])?["message"] as? String, "denied")
        for text in ["4", "41", "4true", "4null", "4[]", "4/admin,"] {
            XCTAssertThrowsError(try manager.parseString(text), text)
        }
    }
}
''')
p = Path('Tests/TestSocketIO/SocketIOClientConfigurationTest.swift')
p.write_text(p.read_text() + '''

extension TestSocketIOClientConfiguration {
    func testRemovedVersionDictionaryOptionsFailClosed() {
        for value: Any in [2, 3, 4, "4", true] {
            let config = ["version": value].toSocketConfiguration()
            guard let option = config.first, case .invalidConfiguration(let reason) = option else {
                XCTFail("version must not be silently accepted: \\(value)"); continue
            }
            XCTAssertTrue(reason.contains("Socket.IO 4"))
        }
    }
}
''')
p = Path('Tests/TestSocketIO/SocketEngineTest.swift')
p.write_text(p.read_text() + '''

extension SocketEngineTest {
    func testEngineIO4CannotBeOverriddenAndEscapedQueriesStayIntact() {
        for query in ["EIO=3", "containsEIO=x", "EIO=3&EIO=2", "%45IO=3&value=a%2Bb%2Fc%3Ad"] {
            let url = URL(string: "http://localhost/?" + query)!
            let engine = SocketEngine(client: manager, url: url, config: [.timestampRequests(false)])
            for candidate in [engine.urlPolling, engine.urlWebSocket, engine.urlPollingHandshake,
                              engine.urlPollingWithSid, engine.urlWebSocketWithSid] {
                let components = URLComponents(url: candidate, resolvingAgainstBaseURL: false)!
                XCTAssertEqual(components.queryItems?.filter { $0.name == "EIO" }.map { $0.value }, ["4"])
                if query.contains("value=") {
                    XCTAssertTrue(components.percentEncodedQuery!.contains("value=a%2Bb%2Fc%3Ad"))
                }
            }
        }
        let engine = SocketEngine(client: manager, url: URL(string: "http://localhost")!,
                                  config: [.connectParams(["EIO": "3"]), .timestampRequests(false)])
        XCTAssertEqual(URLComponents(url: engine.urlPolling, resolvingAgainstBaseURL: false)!
            .queryItems?.filter { $0.name == "EIO" }.map { $0.value }, ["4"])
    }
}
''')
p = Path('Tests/TestSocketIO/SocketTimedEmitterTest.swift')
p.write_text(p.read_text() + '''

final class SocketValueSnapshotTest: XCTestCase {
    func testMutableFoundationContainersAreDetachedFromAsyncAckResults() throws {
        let array = NSMutableArray(array: ["before"])
        let bytes = NSMutableData(data: Data([4, 0, 255]))
        let dictionary = NSMutableDictionary(dictionary: ["nested": array, "binary": bytes])
        let snapshot = try SocketValueSnapshot(dictionary)
        array[0] = "after"
        bytes.setData(Data([99]))
        dictionary["added"] = true
        let value = try XCTUnwrap(snapshot.value as? [String: Any])
        XCTAssertEqual(value["nested"] as? [String], ["before"])
        XCTAssertEqual(value["binary"] as? Data, Data([4, 0, 255]))
        XCTAssertNil(value["added"])
    }

    func testUnsupportedObjectsCannotCrossTheAsyncAckBoundary() {
        XCTAssertThrowsError(try SocketValueSnapshot(NSObject()))
    }

    func testWireScalarAndEmptyContainerTypesRoundTrip() throws {
        XCTAssertEqual(try SocketValueSnapshot(true).value as? Bool, true)
        XCTAssertEqual(try SocketValueSnapshot(42).value as? Int, 42)
        XCTAssertTrue(try SocketValueSnapshot(NSNull()).value is NSNull)
        XCTAssertEqual(try SocketValueSnapshot([String]()).value as? [String], [])
        XCTAssertNotNil(try SocketValueSnapshot([String: Any]()).value as? [String: Any])
    }
}
''')
p = Path('Tests/TestSocketIO/SocketPollingCloseTest.swift')
p.write_text(p.read_text() + '''

extension SocketPollingCloseTest {
    func testCloseRequestUsesEngineIO4WireEncoding() {
        engine.engineQueue.sync {
            let request = engine.createRequestForPost(with: ["1"])
            XCTAssertEqual(request.httpBody, Data("1".utf8))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Length"), "1")
        }
    }
}
''')
