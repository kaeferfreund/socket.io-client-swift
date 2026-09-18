from pathlib import Path

def edit(path, old, new):
    p = Path(path)
    s = p.read_text()
    assert s.count(old) == 1, (path, old[:80], s.count(old))
    p.write_text(s.replace(old, new))

engine = 'Source/SocketIO/Engine/SocketEngine.swift'
edit(engine, 'private func websocketDidDisconnect(error: Error?, reason: String? = nil)',
     'private func websocketDidDisconnect(error: Error?, reason: String? = nil, reportSendError: Bool = false)')
edit(engine, 'self.websocketDidDisconnect(error: error) }',
     'self.websocketDidDisconnect(error: error, reportSendError: true) }')
edit(engine, '        if error != nil { client?.engineDidError(reason: message) }', '''        // JS parity: a receive failure on an established connection is a
        // disconnect, not CONNECT_ERROR (which the manager broadcasts to every
        // namespace, including previously refused ones). Opening failures and
        // explicit local send failures still surface the error as well.
        if error != nil && (!connected || reportSendError) {
            client?.engineDidError(reason: message)
        }''')
edit(engine, '        let wasWebSocketOpen = wsConnected\n', '        let wasWebSocketOpen = wsConnected\n        let wasPolling = polling\n')
edit(engine, '''        oldSession?.invalidateAndCancel()
        oldTransport?.onEvent = nil
        if graceful, wasWebSocketOpen, let transport = oldTransport {''', '''        if graceful && wasPolling {
            // Allow the already-enqueued final polling POST to leave before
            // invalidating the old session, but bound a stuck outstanding GET.
            oldSession?.finishTasksAndInvalidate()
            engineQueue.asyncAfter(deadline: .now() + 1) { oldSession?.invalidateAndCancel() }
        } else {
            oldSession?.invalidateAndCancel()
        }
        oldTransport?.onEvent = nil
        if graceful, !wasPolling, wasWebSocketOpen, let transport = oldTransport {''')
edit(engine, '''        doRequest(for: createRequestForPostWithPostWait()) {_, _, _ in }
        closeOutEngine(reason: reason)''', '''        doRequest(for: createRequestForPostWithPostWait()) {_, _, _ in }
        closeOutEngine(reason: reason, graceful: true)''')
edit(engine, '''        client?.parseEngineBinaryData(version.rawValue >= 3 ? data : data.subdata(in: 1..<data.endIndex))''', '''        guard version.rawValue >= 3 || data.first == 0x04 else {
            didError(reason: "Invalid Engine.IO 3 binary packet")
            return
        }
        client?.parseEngineBinaryData(version.rawValue >= 3 ? data : Data(data.dropFirst()))''')
tests = 'Tests/TestSocketIO/SocketNativeEngineTest.swift'
edit(tests, 'XCTAssertEqual(captured?.url?.path, "/custom/")',
     'XCTAssertEqual(URLComponents(url: captured!.url!, resolvingAgainstBaseURL: false)?.path, "/custom/")')
edit(tests, '    func testDuplicateTerminalEventsCloseEngineOnlyOnce() {', '''    func testEstablishedReceiveFailureIsDisconnectNotConnectError() {
        let (engine, client, transport) = make(); open(engine, transport)
        transport.onEvent?(.closed(code: nil, reason: nil, error: EngineWebSocketError.closed))
        drain(engine)
        XCTAssertTrue(engine.closed)
        XCTAssertEqual(client.closes.count, 1)
        XCTAssertTrue(client.errors.isEmpty)
    }

    func testOpeningFailureStillSurfacesConnectionError() {
        let (engine, client, transport) = make()
        transport.onEvent?(.closed(code: nil, reason: nil, error: EngineWebSocketError.notOpen))
        drain(engine)
        XCTAssertTrue(engine.closed)
        XCTAssertEqual(client.closes.count, 1)
        XCTAssertEqual(client.errors.count, 1)
        XCTAssertEqual(client.opens, 0)
    }

    func testEngineIO3IncomingBinaryStripsExactlyItsPrefix() {
        let (engine, client, transport) = make([.forceWebsockets(true), .version(.two)])
        open(engine, transport)
        defer { engine.disconnect(reason: "test"); drain(engine) }
        transport.onEvent?(.message(.binary(Data([4, 9]))))
        transport.onEvent?(.message(.binary(Data([4]))))
        drain(engine)
        XCTAssertEqual(client.binary, [Data([9]), Data()])
    }

    func testMalformedEngineIO3BinaryClosesInsteadOfCrashing() {
        for data in [Data(), Data([1, 9])] {
            let (engine, client, transport) = make([.forceWebsockets(true), .version(.two)])
            open(engine, transport)
            transport.onEvent?(.message(.binary(data))); drain(engine)
            XCTAssertTrue(engine.closed)
            XCTAssertEqual(client.errors.count, 1)
            XCTAssertTrue(client.binary.isEmpty)
        }
    }

    func testDuplicateTerminalEventsCloseEngineOnlyOnce() {''')
helper = 'Tests/TestSocketIO/E2E/TestServerProcess.swift'
edit(helper, '        maxHttpBufferSize: Int? = nil\n', '        maxHttpBufferSize: Int? = nil,\n        extraEnvironment: [String: String] = [:]\n')
edit(helper, '        p.environment = env\n', '        env.merge(extraEnvironment) { _, value in value }\n        p.environment = env\n')
tls = 'Tests/TestSocketIO/SocketNativeTLSConfigurationTest.swift'
edit(tls, '''    static func certificate(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("E2E/Fixtures/native-tls/\\(name).der")
        return try Data(contentsOf: url)
    }''', '''    private static let generated: Result<URL, Error> = Result {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("socketio-native-tls-" + UUID().uuidString)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", TestServerProcess.fixturesDir()
            .appendingPathComponent("generate-native-tls.mjs").path, directory.path]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "NativeTLSFixtures", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        return directory
    }
    static func directory() throws -> URL { try generated.get() }
    static func certificate(_ name: String) throws -> Data {
        try Data(contentsOf: directory().appendingPathComponent("\\(name).der"))
    }''')
e2e = 'Tests/TestSocketIO/E2E/SocketNativeTLSE2ETest.swift'
edit(e2e, 'TestServerProcess.start(serverScript: "native-tls-server.mjs")',
     'TestServerProcess.start(serverScript: "native-tls-server.mjs",\n            extraEnvironment: ["NATIVE_TLS_DIR": try NativeTLSFixtures.directory().path])')
edit(e2e, 'TestServerProcess.start(serverScript: expired ? "native-tls-expired.mjs" : "native-tls-server.mjs")',
     'TestServerProcess.start(serverScript: expired ? "native-tls-expired.mjs" : "native-tls-server.mjs",\n            extraEnvironment: ["NATIVE_TLS_DIR": try NativeTLSFixtures.directory().path])')
server = 'Tests/TestSocketIO/E2E/Fixtures/native-tls-server.mjs'
edit(server, "import https from 'node:https';", "import https from 'node:https';\nimport { join } from 'node:path';")
edit(server, "// Public localhost-only fixtures, not production credentials.", "// Ephemeral localhost-only fixtures; no key or trust-store installation.\nconst directory = process.env.NATIVE_TLS_DIR;\nif (!directory) throw new Error('NATIVE_TLS_DIR is required');")
edit(server, "readFileSync(new URL('./native-tls/leaf.key', import.meta.url))", "readFileSync(join(directory, 'leaf.key'))")
edit(server, 'readFileSync(new URL(`./native-tls/${certificate}.pem`, import.meta.url))', 'readFileSync(join(directory, `${certificate}.pem`))')
for file in Path('Tests/TestSocketIO/E2E/Fixtures/native-tls').iterdir():
    if file.name != 'README.md': file.unlink()
Path('Tests/TestSocketIO/E2E/Fixtures/native-tls/README.md').write_text('''# Ephemeral TLS fixtures

`generate-native-tls.mjs` uses Node and OpenSSL to generate a private test CA,
a seven-day localhost leaf and an explicitly expired leaf in a temporary
per-test-process directory. The valid leaf never exceeds platform lifetime
limits. Tests do not override their verification clock or install roots.
No generated private key or certificate is committed. Unit and HTTPS/WSS
integration tests use the same temporary certificate set and trust policy.
''')
p = Path('.native-migration/xcode.rb')
if p.exists():
    edit(str(p), "  s['SWIFT_VERSION'] = '5.0'", "  s['SWIFT_VERSION'] = '5.0'\n  s.delete('VALID_ARCHS')")
script = 'scripts/test-native-distributions.sh'
edit(script, "for DESTINATION in 'platform=macOS' 'generic/platform=iOS Simulator' 'generic/platform=tvOS Simulator' 'generic/platform=watchOS Simulator'; do", "for SPEC in 'macosx|platform=macOS' 'iphonesimulator|generic/platform=iOS Simulator' 'appletvsimulator|generic/platform=tvOS Simulator' 'watchsimulator|generic/platform=watchOS Simulator'; do\n  SDK=\"${SPEC%%|*}\"\n  DESTINATION=\"${SPEC#*|}\"\n  echo \"Building native framework for $SDK\"")
edit(script, '    -destination "$DESTINATION" -derivedDataPath', '    -sdk "$SDK" -destination "$DESTINATION" -derivedDataPath')
