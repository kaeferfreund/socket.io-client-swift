import XCTest
@testable import SocketIO

/// Scenarios ported one-to-one from the JavaScript client's own test suite
/// (`socket.io/packages/socket.io-client/test`, v4.8.3), run against the same
/// kind of server it is tested against.
///
/// The point is not to add more Swift tests but to let the reference client's
/// expectations decide what "parity" means, instead of our reading of the
/// source. Each test names the JS file and title it comes from; the fixture
/// namespaces (`/no`, `/with-data`, `/foo`, `/asd`) and the `echo` handler
/// mirror `test/support/server.ts`.
///
/// See `PARITY.md` for the full matrix, including the scenarios that are not
/// portable and why.
final class JSParityE2ETest: XCTestCase {
    var server: TestServerProcess!
    var manager: SocketManager!
    var serverURL: URL { URL(string: "http://127.0.0.1:\(server.port)")! }

    override func setUp() {
        super.setUp()
        server = try! TestServerProcess.start()
    }

    override func tearDown() {
        manager?.disconnect()
        manager = nil
        server.stop()
        super.tearDown()
    }

    private func makeManager(_ extra: SocketIOClientOption...) -> SocketManager {
        var config: SocketIOClientConfiguration = [.log(false)]
        for option in extra { config.insert(option) }

        manager = SocketManager(socketURL: serverURL, config: config)

        return manager
    }

    /// Drops the engine from the server side, the way `StateRecoveryE2ETest`
    /// does. The JS tests call `socket.io.engine.close()`, but a client-initiated
    /// close is a *clean* shutdown here and does not reliably trigger a
    /// reconnect — killing the transport server-side reproduces the unexpected
    /// drop those tests mean to simulate.
    private func killTransport(ofSocketWithId sid: String) throws {
        let (status, _) = try server.admin("/admin/kill-transport?sid=\(sid)")
        XCTAssertEqual(status, 200)
    }

    /// CONNECT_ERROR arrives as the `error` client event here; JS calls it
    /// `connect_error`. What has to match is that the server's message reaches
    /// the application at all.
    private func errorMessage(from data: [Any]) -> String? {
        if let payload = data.first as? [String: Any] {
            return payload["message"] as? String
        }

        return data.first as? String
    }

    // MARK: socket.ts — "should fire an error event on middleware failure from custom namespace"

    func testMiddlewareFailureOnCustomNamespaceIsReported() {
        let socket = makeManager().socket(forNamespace: "/no")

        let failed = expectation(description: "connect error")
        // A refused namespace may be retried; only the first report is under test.
        failed.assertForOverFulfill = false
        var message: String?
        socket.on(clientEvent: .error) { data, _ in
            message = self.errorMessage(from: data)
            failed.fulfill()
        }
        socket.connect()

        wait(for: [failed], timeout: 5)
        XCTAssertEqual(message, "Auth failed (custom namespace)")
    }

    // MARK: socket.ts — "should fire a connect_error event with error data on middleware failure"

    func testMiddlewareFailureCarriesItsErrorData() {
        let socket = makeManager().socket(forNamespace: "/with-data")

        let failed = expectation(description: "connect error")
        failed.assertForOverFulfill = false
        var payload: [String: Any]?
        socket.on(clientEvent: .error) { data, _ in
            payload = data.first as? [String: Any]
            failed.fulfill()
        }
        socket.connect()

        wait(for: [failed], timeout: 5)

        XCTAssertEqual(payload?["message"] as? String, "Auth failed (with data)")

        let errorData = payload?["data"] as? [String: Any]
        XCTAssertEqual(errorData?["code"] as? Int, 401,
                       "JS exposes err.data; without it the app cannot tell 401 from any other refusal")
        XCTAssertEqual(errorData?["details"] as? String, "Invalid token")
    }

    // MARK: socket.ts — "should not try to reconnect after a middleware failure"

    /// The server refused this namespace. Rejoining it on the next engine open
    /// would hammer a server that already said no, so JS does not: it destroys
    /// the socket's subscriptions on CONNECT_ERROR and waits for an explicit
    /// `connect()`.
    func testNoRejoinAfterAMiddlewareFailure() throws {
        let manager = makeManager(.reconnectWait(1))

        // A socket on a namespace the server accepts, so the engine has a
        // transport to kill and something to prove it came back.
        let root = manager.socket(forNamespace: "/")
        let rootConnected = expectation(description: "root connected")
        rootConnected.assertForOverFulfill = false
        var rootConnects = 0
        root.on(clientEvent: .connect) { _, _ in
            rootConnects += 1
            rootConnected.fulfill()
        }
        root.connect()
        wait(for: [rootConnected], timeout: 5)

        let refused = manager.socket(forNamespace: "/no")
        var errorCount = 0
        let firstError = expectation(description: "first connect error")
        firstError.assertForOverFulfill = false
        refused.on(clientEvent: .error) { _, _ in
            errorCount += 1
            firstError.fulfill()
        }
        refused.connect()
        wait(for: [firstError], timeout: 5)

        let sid = try XCTUnwrap(root.sid)
        try killTransport(ofSocketWithId: sid)

        let reconnected = expectation(description: "engine came back")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { reconnected.fulfill() }
        wait(for: [reconnected], timeout: 10)

        XCTAssertGreaterThan(rootConnects, 1, "The engine has to actually reconnect, or this proves nothing")
        XCTAssertEqual(errorCount, 1, "The namespace must not be rejoined after the server refused it")
    }

    // MARK: socket.ts — "should not discard an unsent ack (callback)"

    /// Disconnect, emit, reconnect: the packet is buffered and its ack is still
    /// owed. This is the JS scenario that the send buffer exists for.
    func testAnUnsentAckIsNotDiscarded() {
        let socket = makeManager().socket(forNamespace: "/")

        let connected = expectation(description: "connect")
        // The handler stays registered across the reconnect below.
        connected.assertForOverFulfill = false
        socket.on(clientEvent: .connect) { _, _ in connected.fulfill() }
        socket.connect()
        wait(for: [connected], timeout: 5)

        socket.disconnect()

        let acked = expectation(description: "the buffered emit is acked after reconnecting")
        socket.emitWithAck("echo", "a").timingOut(after: 10) { data in
            XCTAssertEqual(data.first as? String, "a")
            acked.fulfill()
        }

        socket.connect()
        wait(for: [acked], timeout: 10)
    }

    // MARK: socket.ts — "clears socket.id upon disconnection"

    func testSocketIdIsClearedOnDisconnect() {
        let socket = makeManager().socket(forNamespace: "/")

        let connected = expectation(description: "connect")
        socket.on(clientEvent: .connect) { _, _ in connected.fulfill() }
        socket.connect()
        wait(for: [connected], timeout: 5)
        XCTAssertNotNil(socket.sid)

        let disconnected = expectation(description: "disconnect")
        socket.on(clientEvent: .disconnect) { _, _ in disconnected.fulfill() }
        socket.disconnect()
        wait(for: [disconnected], timeout: 5)

        XCTAssertTrue(socket.sid?.isEmpty ?? true, "A cleared id is what tells the app the session is gone")
    }

    // MARK: socket.ts — "should change socket.id upon reconnection"

    func testSocketIdChangesOnReconnection() throws {
        let manager = makeManager(.reconnectWait(1))
        let socket = manager.socket(forNamespace: "/")

        let connected = expectation(description: "connect")
        // The handler stays registered and fires again on the reconnect below.
        connected.assertForOverFulfill = false
        var connects = 0
        socket.on(clientEvent: .connect) { _, _ in
            connects += 1
            connected.fulfill()
        }
        socket.connect()
        wait(for: [connected], timeout: 5)

        let firstId = try XCTUnwrap(socket.sid)

        try killTransport(ofSocketWithId: firstId)

        let reconnected = expectation(description: "reconnect")
        reconnected.assertForOverFulfill = false
        socket.on(clientEvent: .connect) { _, _ in reconnected.fulfill() }
        wait(for: [reconnected], timeout: 15)

        XCTAssertGreaterThan(connects, 1)
        XCTAssertNotEqual(socket.sid, firstId, "A new session must not reuse the old id")
    }

    // MARK: connection.ts — "should not close the connection when disconnecting a single socket"

    /// Two namespaces share one engine. Leaving one must not take the other
    /// down with it.
    func testDisconnectingOneNamespaceKeepsTheOtherConnected() {
        let manager = makeManager()
        let foo = manager.socket(forNamespace: "/foo")
        let asd = manager.socket(forNamespace: "/asd")

        let bothConnected = expectation(description: "both namespaces connected")
        bothConnected.expectedFulfillmentCount = 2
        bothConnected.assertForOverFulfill = false
        foo.on(clientEvent: .connect) { _, _ in bothConnected.fulfill() }
        asd.on(clientEvent: .connect) { _, _ in bothConnected.fulfill() }
        foo.connect()
        asd.connect()
        wait(for: [bothConnected], timeout: 5)

        var asdDisconnected = false
        asd.on(clientEvent: .disconnect) { _, _ in asdDisconnected = true }

        foo.disconnect()

        let settled = expectation(description: "give the disconnect time to propagate")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        XCTAssertFalse(asdDisconnected, "Leaving one namespace must not close the shared engine")
        XCTAssertEqual(asd.status, .connected)
    }

    // MARK: connection.ts — "should work with acks"

    func testEmitWithAckRoundTrip() {
        let socket = makeManager().socket(forNamespace: "/")

        let connected = expectation(description: "connect")
        socket.on(clientEvent: .connect) { _, _ in connected.fulfill() }
        socket.connect()
        wait(for: [connected], timeout: 5)

        let acked = expectation(description: "ack")
        socket.emitWithAck("echo", "hello").timingOut(after: 5) { data in
            XCTAssertEqual(data.first as? String, "hello")
            acked.fulfill()
        }
        wait(for: [acked], timeout: 5)
    }

    // MARK: connection.ts — "should receive utf8 multibyte characters"

    func testUtf8MultibyteCharactersSurviveTheRoundTrip() {
        let socket = makeManager().socket(forNamespace: "/")

        let connected = expectation(description: "connect")
        socket.on(clientEvent: .connect) { _, _ in connected.fulfill() }
        socket.connect()
        wait(for: [connected], timeout: 5)

        // The same three strings the JS test uses.
        let strings = [
            "てすと",
            "Я Б Г Д Ж Й",
            "Ä ä Ü ü ß"
        ]

        for string in strings {
            let acked = expectation(description: "ack for \(string)")
            socket.emitWithAck("echo", string).timingOut(after: 5) { data in
                XCTAssertEqual(data.first as? String, string)
                acked.fulfill()
            }
            wait(for: [acked], timeout: 5)
        }
    }
}
