import Foundation
import XCTest
@testable import SocketIO

/// Raw Engine.IO callbacks are marshalled to main before touching XCTest state.
private final class RemainingEngineClient: NSObject, SocketEngineClient {
    var opened: () -> Void = {}
    var message: (EngineWebSocketMessage) -> Void = { _ in }
    var failed: (String, SocketTransportError?) -> Void = { _, _ in }
    var closed: (String, SocketTransportError?) -> Void = { _, _ in }
    func engineDidOpen(reason: String) { DispatchQueue.main.async { self.opened() } }
    func parseEngineMessage(_ msg: String) { DispatchQueue.main.async { self.message(.text(msg)) } }
    func parseEngineBinaryData(_ data: Data) { DispatchQueue.main.async { self.message(.binary(data)) } }
    func engineDidError(reason: String) { DispatchQueue.main.async { self.failed(reason, nil) } }
    func engineDidError(reason: String, error: SocketTransportError) {
        DispatchQueue.main.async { self.failed(reason, error) }
    }
    func engineDidClose(reason: String) { DispatchQueue.main.async { self.closed(reason, nil) } }
    func engineDidClose(reason: String, error: SocketTransportError) {
        DispatchQueue.main.async { self.closed(reason, error) }
    }
    func engineDidReceivePing() {}
    func engineDidReceivePong() {}
    func engineDidSendPing() {}
    func engineDidSendPong() {}
    func engineDidWebsocketUpgrade(headers: [String: String]) {}
}

final class EngineRemainingParityE2ETest: XCTestCase {
    private var server: TestServerProcess!
    private var client: RemainingEngineClient!
    private var engine: SocketEngine!

    override func tearDown() {
        if let engine = engine {
            engine.disconnect(reason: "test teardown")
            engine.engineQueue.sync {}
        }
        server?.stop()
        engine = nil; client = nil; server = nil
        super.tearDown()
    }

    private func make(_ options: [SocketIOClientOption], maximum: Int? = nil,
                      environment: [String: String] = [:]) throws {
        server = try TestServerProcess.start(serverScript: "engine-parity-server.mjs",
                                            maxHttpBufferSize: maximum, extraEnvironment: environment)
        client = RemainingEngineClient()
        client.failed = { reason, _ in XCTFail("Unexpected transport failure: \(reason)") }
        var config: SocketIOClientConfiguration = [.log(false)]
        options.forEach { config.insert($0) }
        engine = SocketEngine(client: client, url: URL(string: "http://127.0.0.1:\(server.port)")!, config: config)
    }

    private func snapshot() throws -> [String: Any] {
        let (status, body) = try server.admin("/admin/snapshot", method: "GET")
        XCTAssertEqual(status, 200)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    /// The native engine's binary send consists of a text header followed by
    /// attachments. Assert the extra empty header too; do not pretend to expose
    /// the standalone JS Socket.send(ArrayBuffer) API.
    private func roundTrip(_ packets: [EngineWebSocketMessage]) {
        var expected: [EngineWebSocketMessage] = []
        for packet in packets {
            if case .binary = packet { expected.append(.text("")) }
            expected.append(packet)
        }
        let received = expectation(description: "all raw Engine.IO packets echoed")
        received.expectedFulfillmentCount = expected.count
        received.assertForOverFulfill = true
        var actual: [EngineWebSocketMessage] = []
        client.message = { packet in actual.append(packet); received.fulfill() }
        client.opened = { [self] in
            for packet in packets {
                switch packet {
                case .text(let value): engine.send(value, withData: [])
                case .binary(let data): engine.send("", withData: [data])
                }
            }
        }
        engine.connect()
        wait(for: [received], timeout: 10)
        XCTAssertEqual(actual, expected)
    }

    func testConnectLocalhostPolling() throws {
        try make([.forcePolling(true)])
        roundTrip([.text("connected")])
        engine.engineQueue.sync { XCTAssertTrue(engine.connected); XCTAssertFalse(engine.sid.isEmpty) }
    }
    func testConnectLocalhostWebSocket() throws {
        try make([.forceWebsockets(true)])
        roundTrip([.text("connected")])
        engine.engineQueue.sync { XCTAssertTrue(engine.connected); XCTAssertTrue(engine.wsConnected) }
    }
    func testMultibyteUTF8Polling() throws {
        try make([.forcePolling(true)])
        roundTrip([.text("cash money €€€")])
    }
    func testUnicodeScalarBoundaries() throws {
        try make([.forcePolling(true)])
        // Exact scalar sequence of upstream connection.js, not only a common emoji.
        roundTrip([.text("\u{10000}-\u{EFFFF}\u{F0000}-\u{10FFFF}\u{E000}-\u{F8FF}")])
    }
    func testBinaryDataPolling() throws {
        try make([.forcePolling(true)])
        roundTrip([.binary(Data([0, 1, 2, 3, 4])), .binary(Data())])
    }
    func testBinaryDataWebSocket() throws {
        try make([.forceWebsockets(true)])
        roundTrip([.binary(Data([0, 1, 2, 3, 4])), .binary(Data())])
        let frames = try XCTUnwrap(snapshot()["frames"] as? [[String: Any]])
        XCTAssertTrue(frames.contains { ($0["binary"] as? Bool) == true })
    }
    func testForcedBase64Polling() throws {
        try make([.forcePolling(true), .forceBase64(true)])
        roundTrip([.binary(Data([0, 1, 2, 3, 4]))])
        let requests = try XCTUnwrap(snapshot()["requests"] as? [[String: Any]])
        XCTAssertTrue(requests.contains { ($0["body"] as? String)?.contains("bAAECAwQ=") == true })
    }
    func testForcedBase64WebSocket() throws {
        try make([.forceWebsockets(true), .forceBase64(true)])
        roundTrip([.binary(Data([0, 1, 2, 3, 4])), .binary(Data())])
        let snapshot = try self.snapshot()
        let frames = try XCTUnwrap(snapshot["frames"] as? [[String: Any]])
        XCTAssertFalse(frames.contains { ($0["binary"] as? Bool) == true })
        XCTAssertTrue(frames.contains { ($0["payload"] as? String) == "bAAECAwQ=" })
        XCTAssertTrue(frames.contains { ($0["payload"] as? String) == "b" })
        let requests = try XCTUnwrap(snapshot["requests"] as? [[String: Any]])
        XCTAssertTrue(requests.contains { ($0["url"] as? String)?.contains("b64=1") == true })
    }
    func testBinaryMaxPayloadBatching() throws {
        try make([.forcePolling(true)], maximum: 100)
        roundTrip([.binary(Data(repeating: 1, count: 72)), .binary(Data(repeating: 2, count: 20)),
                   .text(String(repeating: "a", count: 20)), .binary(Data(repeating: 3, count: 20)),
                   .binary(Data(repeating: 4, count: 72))])
        let requests = try XCTUnwrap(snapshot()["requests"] as? [[String: Any]])
        let posts = requests.filter { ($0["method"] as? String) == "POST" }
        XCTAssertGreaterThan(posts.count, 1)
        for request in posts { XCTAssertLessThanOrEqual(try XCTUnwrap(request["bytes"] as? Int), 100) }
    }

    private func assertCookiePolicy(_ enabled: Bool) throws {
        try make([.forcePolling(true), .withCredentials(enabled)])
        roundTrip([.text("cookie check")])
        let requests = try XCTUnwrap(snapshot()["requests"] as? [[String: Any]])
        let post = try XCTUnwrap(requests.first { ($0["method"] as? String) == "POST" })
        let headers = try XCTUnwrap(post["headers"] as? [String: Any])
        if enabled {
            let cookie = try XCTUnwrap(headers["cookie"] as? String)
            XCTAssertEqual(Set(cookie.components(separatedBy: "; ")), ["one=1", "two=2"])
        } else {
            XCTAssertNil(headers["cookie"])
        }
    }
    func testServerCookiesSentWhenEnabled() throws { try assertCookiePolicy(true) }
    func testServerCookiesNotSentWhenDisabled() throws { try assertCookiePolicy(false) }
    func testExtraHeadersReachPollingGETAndPOST() throws {
        try make([.forcePolling(true), .extraHeaders(["X-Parity": "native-value"])])
        roundTrip([.text("header check")])
        let requests = try XCTUnwrap(snapshot()["requests"] as? [[String: Any]])
        for method in ["GET", "POST"] {
            let request = try XCTUnwrap(requests.first { ($0["method"] as? String) == method })
            XCTAssertEqual((request["headers"] as? [String: Any])?["x-parity"] as? String, "native-value")
        }
    }
    func testNoTrailingSlashOnWire() throws {
        try make([.forcePolling(true), .addTrailingSlash(false)], environment: ["NO_TRAILING_SLASH": "1"])
        roundTrip([.text("no slash")])
        let requests = try XCTUnwrap(snapshot()["requests"] as? [[String: Any]])
        XCTAssertTrue(requests.allSatisfy { ($0["url"] as? String)?.hasPrefix("/engine.io?") == true })
    }

    private func expectFailure(status: Int?, code: Int?, operation: String,
                               start: () -> Void) {
        let closed = expectation(description: "one detailed close")
        closed.assertForOverFulfill = true
        var failures: [SocketTransportError] = []
        client.failed = { _, detail in if let detail = detail { failures.append(detail) } }
        client.closed = { reason, detail in
            XCTAssertEqual(reason, code == nil ? "transport error" : "transport close")
            XCTAssertNotNil(detail)
            XCTAssertEqual(detail?.httpStatusCode, status)
            XCTAssertEqual(detail?.closeCode, code)
            XCTAssertEqual(detail?.operation, operation)
            if code == nil { XCTAssertEqual(failures.count, 1) }
            if status == 400 {
                XCTAssertEqual(detail?.responseText, "{\"code\":1,\"message\":\"Session ID unknown\"}")
            }
            closed.fulfill()
        }
        start()
        wait(for: [closed], timeout: 10)
    }
    func testOversizePollingReports413AndCloseDetail() throws {
        try make([.forcePolling(true)], maximum: 100)
        client.opened = { [self] in engine.send(String(repeating: "a", count: 101), withData: []) }
        expectFailure(status: 413, code: nil, operation: "write") { engine.connect() }
    }
    func testOversizeWebSocketReports1009AndCloseDetail() throws {
        try make([.forceWebsockets(true)], maximum: 100)
        client.opened = { [self] in engine.send(String(repeating: "a", count: 101), withData: []) }
        expectFailure(status: nil, code: 1009, operation: "close") { engine.connect() }
    }
    func testUnknownSIDPollingReports400BodyAndCloseDetail() throws {
        try make([.forcePolling(true)])
        // Inject a stale transport request, not a user query (sid is engine-owned).
        let url = URL(string: "http://127.0.0.1:\(server.port)/engine.io/?EIO=4&transport=polling&sid=missing")!
        expectFailure(status: 400, code: nil, operation: "read") {
            engine.engineQueue.sync {
                engine.setConnected(true)
                engine.setTestSession(URLSession(configuration: .ephemeral))
                engine.doLongPoll(for: URLRequest(url: url))
            }
        }
    }
    func testUnknownSIDWebSocketReportsErrorAndCloseDetail() throws {
        try make([.forceWebsockets(true)])
        let url = URL(string: "ws://127.0.0.1:\(server.port)/engine.io/?EIO=4&transport=websocket&sid=missing")!
        engine.webSocketTransportFactory = { [weak engine] _ in
            URLSessionWebSocketTransport(request: URLRequest(url: url), queue: engine!.engineQueue,
                                         configuration: .ephemeral)
        }
        expectFailure(status: nil, code: nil, operation: "close") { engine.connect() }
    }
}
