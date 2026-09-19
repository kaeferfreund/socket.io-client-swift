from pathlib import Path
R=Path('.')
def edit(path, old, new):
    p=R/path; s=p.read_text(); assert old in s, (path, old[:120]); p.write_text(s.replace(old,new,1))
p='Tests/TestSocketIO/E2E/Fixtures/engine-parity-server.mjs'
edit(p,"  req.on('data', (chunk) => {\n    record.bytes += chunk.length;\n    // Keep the diagnostic fixture bounded even on deliberately oversized input.\n    if (record.bytes <= 8192) record.body += chunk.toString();\n  });", """  // A data listener resumes even an empty GET and emits its normal request-close
  // before the pending poll responds. Observe without changing stream flow.
  const push = req.push;
  req.push = function(chunk, encoding) {
    if (chunk !== null) {
      const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, encoding);
      record.bytes += bytes.length;
      if (record.bytes <= 8192) record.body += bytes.toString();
    }
    return push.call(this, chunk, encoding);
  };""")
edit(p,"  socket.on('upgrade', observeFrames);", """  socket.on('upgrade', (transport) => {
    observeFrames(transport);
    if (process.env.EMIT_UPGRADE_MARKER === '1') socket.send('__parity_upgraded__');
  });
  if (process.env.SEND_GREETING === '1') socket.send('hi');""")
p='Tests/TestSocketIO/E2E/EngineRemainingParityE2ETest.swift'
edit(p,'var config: SocketIOClientConfiguration = [.log(false)]','var config: SocketIOClientConfiguration = [.log(false), .path("/engine.io/")]')
edit(p,'private func roundTrip(_ packets: [EngineWebSocketMessage]) {','private func roundTrip(_ packets: [EngineWebSocketMessage], afterUpgrade: Bool = false) {')
edit(p,'        client.message = { packet in actual.append(packet); received.fulfill() }\n        client.opened = { [self] in', '        let send: () -> Void = { [self] in')
edit(p,'        engine.connect()\n        wait(for: [received], timeout: 10)', '''        client.message = { [self] packet in
            if afterUpgrade && packet == .text("__parity_upgraded__") {
                engine.engineQueue.sync { XCTAssertFalse(engine.polling); XCTAssertTrue(engine.wsConnected) }
                send()
            } else {
                actual.append(packet); received.fulfill()
            }
        }
        if !afterUpgrade { client.opened = send }
        engine.connect()
        wait(for: [received], timeout: 10)''')
edit(p,'''    func testConnectLocalhostPolling() throws {
        try make([.forcePolling(true)])
        roundTrip([.text("connected")])
        engine.engineQueue.sync { XCTAssertTrue(engine.connected); XCTAssertFalse(engine.sid.isEmpty) }
    }
    func testConnectLocalhostWebSocket() throws {
        try make([.forceWebsockets(true)])
        roundTrip([.text("connected")])
        engine.engineQueue.sync { XCTAssertTrue(engine.connected); XCTAssertTrue(engine.wsConnected) }
    }''','''    private func assertServerGreeting(_ options: [SocketIOClientOption]) throws {
        try make(options, environment: ["SEND_GREETING": "1"])
        let greeting = expectation(description: "open precedes unsolicited server greeting")
        var opened = false
        client.opened = { opened = true }
        client.message = { packet in
            XCTAssertTrue(opened)
            XCTAssertEqual(packet, .text("hi"))
            greeting.fulfill()
        }
        engine.connect()
        wait(for: [greeting], timeout: 10)
        engine.engineQueue.sync { XCTAssertTrue(engine.connected); XCTAssertFalse(engine.sid.isEmpty) }
    }
    func testConnectLocalhostPolling() throws { try assertServerGreeting([.forcePolling(true)]) }
    func testConnectLocalhostWebSocket() throws { try assertServerGreeting([.forceWebsockets(true)]) }''')
edit(p,'    func testBinaryMaxPayloadBatching() throws {', '''    func testForcedBase64AfterActualTransportUpgrade() throws {
        try make([.forceBase64(true)], environment: ["EMIT_UPGRADE_MARKER": "1"])
        roundTrip([.binary(Data([0, 1, 2, 3, 4])), .binary(Data())], afterUpgrade: true)
        let frames = try XCTUnwrap(snapshot()["frames"] as? [[String: Any]])
        XCTAssertFalse(frames.contains { ($0["binary"] as? Bool) == true })
        XCTAssertTrue(frames.contains { ($0["payload"] as? String) == "bAAECAwQ=" })
        XCTAssertTrue(frames.contains { ($0["payload"] as? String) == "b" })
    }
    private func assertCookiesAcrossUpgrade(_ enabled: Bool) throws {
        try make([.withCredentials(enabled)], environment: ["EMIT_UPGRADE_MARKER": "1"])
        roundTrip([.text("upgraded")], afterUpgrade: true)
        let requests = try XCTUnwrap(snapshot()["requests"] as? [[String: Any]])
        let upgrade = try XCTUnwrap(requests.first { ($0["method"] as? String) == "UPGRADE" })
        let headers = try XCTUnwrap(upgrade["headers"] as? [String: Any])
        if enabled {
            let cookie = try XCTUnwrap(headers["cookie"] as? String)
            XCTAssertEqual(Set(cookie.components(separatedBy: "; ")), ["one=1", "two=2"])
        } else { XCTAssertNil(headers["cookie"]) }
    }
    func testCookiesSurvivePollingToWebSocketUpgrade() throws { try assertCookiesAcrossUpgrade(true) }
    func testDisabledCookiesStayDisabledDuringUpgrade() throws { try assertCookiesAcrossUpgrade(false) }

    func testBinaryMaxPayloadBatching() throws {''')
p='Tests/TestSocketIO/SocketRemainingParityTest.swift'
edit(p,'XCTAssertEqual(engine([.path("/custom")]).urlPolling.path, "/custom/")', 'XCTAssertEqual(URLComponents(url: engine([.path("/custom")]).urlPolling, resolvingAgainstBaseURL: false)?.percentEncodedPath, "/custom/")')
edit(p,'    func testManagerPassesSameErrorToDisconnectAndDoesNotLeakIt() {','''    func testInvalidUTF8ResponseRemainsBoundedAfterLossyDecoding() {
        let detail = SocketTransportError(transport: "polling", operation: "read", body: Data(repeating: 255, count: 4096))
        XCTAssertLessThanOrEqual(detail.responseText?.utf8.count ?? Int.max, 4096)
        XCTAssertTrue(detail.responseTruncated)
    }
    func testManagerPassesSameErrorToDisconnectAndDoesNotLeakIt() {''')
p='Source/SocketIO/Engine/SocketEngineClient.swift'
edit(p,'''        self.closeReason = closeReason
        self.responseText = body.map { String(decoding: $0.prefix(4096), as: UTF8.self) }
        self.responseTruncated = (body?.count ?? 0) > 4096''','''        self.closeReason = closeReason ?? (closeCode == nil ? nil : "")
        if let body = body {
            let decoded = String(decoding: body.prefix(4096), as: UTF8.self)
            var text = ""
            var bytes = 0
            // A replacement character can expand invalid input. Bound the
            // retained UTF-8 result, not just the bytes passed to the decoder.
            for scalar in decoded.unicodeScalars {
                let size = String(scalar).utf8.count
                guard bytes + size <= 4096 else { break }
                text.unicodeScalars.append(scalar)
                bytes += size
            }
            self.responseText = text
            self.responseTruncated = body.count > 4096 || bytes < decoded.utf8.count
        } else {
            self.responseText = nil
            self.responseTruncated = false
        }''')
p='Tests/TestSocketIO/SocketClearAcksOnCloseTest.swift'
s=(R/p).read_text();start=s.index('    func testAsyncEmitWithAckThrowsDisconnectedOnATransportDropThatReconnects() async {');end=s.index('\n    }\n}',start)+6
s=s[:start]+'''    func testAsyncEmitWithAckThrowsDisconnectedOnATransportDropThatReconnects() async {
        let initial = expectation(description: "initial connect")
        let registered = expectation(description: "emit reached the fake transport")
        let rejoined = expectation(description: "namespace re-joined")
        let thrown = expectation(description: "await throws the disconnect error")
        // Never block the MainActor with synchronous XCTest waits. The fake
        // transport and manager need that executor to deliver CONNECT and ACK.
        await MainActor.run {
            self.manager = SocketManager(socketURL: URL(string: "http://localhost/")!,
                config: [.log(false), .reconnects(true), .reconnectWait(0), .ackTimeout(10)])
            self.engine = ClearAcksTestEngine(client: self.manager, url: self.manager.socketURL, options: nil)
            self.manager.engine = self.engine
            self.socket = self.manager.defaultSocket
            self.socket.once(clientEvent: .connect) { _, _ in initial.fulfill() }
            self.engine.onEventWrite = { registered.fulfill() }
            self.socket.connect()
        }
        await fulfillment(of: [initial], timeout: 5)
        let emit = Task {
            do {
                _ = try await self.socket.emitWithAck("echo", "a")
                XCTFail("the acknowledgement must not resolve")
            } catch {
                XCTAssertEqual(error as? SocketAckError, .disconnected)
            }
            thrown.fulfill()
        }
        defer { emit.cancel() }
        await fulfillment(of: [registered], timeout: 5)
        await MainActor.run {
            self.socket.once(clientEvent: .connect) { _, _ in rejoined.fulfill() }
            self.engine.dropTransport(reason: "transport close")
        }
        await fulfillment(of: [thrown, rejoined], timeout: 5)
        await MainActor.run {
            XCTAssertTrue(self.socket.ackHandlers.pendingTimedAckIDs.isEmpty)
            XCTAssertEqual(self.socket.status, .connected)
        }
    }''' + s[end:]
assert '    private var sessions = 0' in s
s=s.replace('    private var sessions = 0','    var onEventWrite: (() -> Void)?\n    private var sessions = 0',1)
s=s.replace('            sent.append(msg)\n            return','            sent.append(msg)\n            onEventWrite?()\n            return',1)
(R/p).write_text(s)
p='Tests/TestSocketIO/SocketRemainingBinaryParserTest.swift'
edit(p,'private func assertRoundTrip(_ items: [Any], ack: Bool = false) throws {','private func assertRoundTrip(_ items: [Any], ack: Bool = false, id: Int = 0, namespace: String = "/binary") throws {')
edit(p,'packetFromEmit(safe, id: 0, nsp: "/binary", ack: ack)','packetFromEmit(safe, id: id, nsp: namespace, ack: ack)')
edit(p,'XCTAssertEqual(decoded.id, 0); XCTAssertEqual(decoded.nsp, "/binary")','XCTAssertEqual(decoded.id, id); XCTAssertEqual(decoded.nsp, namespace)')
edit(p,'        try assertRoundTrip(["hello", bytes])','        try assertRoundTrip(["hello", bytes])\n        try assertRoundTrip(["a", Data(repeating: 0, count: 2)], namespace: "/")')
edit(p,'        try assertRoundTrip(["slice", slice])','        try assertRoundTrip(["slice", slice])\n        try assertRoundTrip(["a", Data([0, 1, 2, 3, 4])], namespace: "/")')
edit(p,'        for data in [Data(), Data([0, 1, 127, 128, 255])] { try assertRoundTrip(["blob", data]) }','''        for data in [Data(), Data([0, 1, 127, 128, 255])] { try assertRoundTrip(["blob", data]) }
        try assertRoundTrip(["a", Data(repeating: 0, count: 2)], namespace: "/")''')
edit(p,'        try assertRoundTrip(["deep", ["a": [NSNull(), ["b": Data([1, 2, 3])]]]])','''        try assertRoundTrip(["deep", ["a": [NSNull(), ["b": Data([1, 2, 3])]]]])
        try assertRoundTrip(["a", ["a": "hi", "b": ["why": Data(repeating: 0, count: 2)], "c": "bye"] as [String: Any]],
                           id: 999, namespace: "/deep")''')
edit(p,'    func testBinaryAckBlobEquivalent() throws { try assertRoundTrip([Data([0, 1, 2, 3, 4])], ack: true) }','''    func testBinaryAckBlobEquivalent() throws {
        try assertRoundTrip([Data([0, 1, 2, 3, 4])], ack: true)
        try assertRoundTrip([["a": "hi ack", "b": ["why": Data(repeating: 0, count: 2)], "c": "bye ack"] as [String: Any]],
                           ack: true, id: 999, namespace: "/deep")
    }''')
