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

    /// Connects and waits for it. The handler stays registered, so reconnects
    /// later in a test do not trip the over-fulfil check.
    @discardableResult
    private func connect(_ socket: SocketIOClient) -> SocketIOClient {
        let connected = expectation(description: "connect \(socket.nsp)")
        connected.assertForOverFulfill = false
        socket.on(clientEvent: .connect) { _, _ in connected.fulfill() }
        socket.connect()
        wait(for: [connected], timeout: 5)

        return socket
    }

    /// Waits a fixed interval, for assertions that nothing *further* happens.
    private func settle(_ seconds: TimeInterval) {
        let done = expectation(description: "settled")
        DispatchQueue.main.socketAsyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }

    /// Raw socket.io CONNECT frames the server has seen, counted at the
    /// engine.io layer so duplicates cannot be deduplicated away.
    private func connectFrameCount() throws -> Int {
        let (status, body) = try server.admin("/admin/connect-frame-count", method: "GET")
        XCTAssertEqual(status, 200)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]

        return json?["count"] as? Int ?? -1
    }

    /// Reads the receiving namespace's own server-side ID, not an echoed client ID.
    private func serverSocketId(for socket: SocketIOClient) throws -> String {
        let replied = expectation(description: "server ID for \(socket.nsp)")
        var serverID: String?
        socket.emitWithAck("server-socket-id").timingOut(after: 5) { data in
            serverID = data.first as? String
            XCTAssertNotEqual(serverID, SocketAckStatus.noAck.rawValue)
            replied.fulfill()
        }
        wait(for: [replied], timeout: 6)
        return try XCTUnwrap(serverID)
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

    /// CONNECT_ERROR arrives as the `connect_error` client event, JS-aligned.
    /// What has to match is that the server's message reaches the application
    /// at all.
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
        socket.on(clientEvent: .connectError) { data, _ in
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
        socket.on(clientEvent: .connectError) { data, _ in
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
        let rootReconnected = expectation(description: "root reconnected")
        var rootConnects = 0
        root.on(clientEvent: .connect) { _, _ in
            rootConnects += 1
            if rootConnects == 1 { rootConnected.fulfill() }
            if rootConnects == 2 { rootReconnected.fulfill() }
        }
        root.connect()
        wait(for: [rootConnected], timeout: 5)

        let refused = manager.socket(forNamespace: "/no")
        var errorCount = 0
        let firstError = expectation(description: "first connect error")
        firstError.assertForOverFulfill = false
        refused.on(clientEvent: .connectError) { _, _ in
            errorCount += 1
            firstError.fulfill()
        }
        refused.connect()
        wait(for: [firstError], timeout: 5)

        let sid = try XCTUnwrap(root.sid)
        try killTransport(ofSocketWithId: sid)

        wait(for: [rootReconnected], timeout: 10)
        // A server round trip after reconnect is a processing barrier, not a
        // guessed sleep: a mistakenly re-sent /no CONNECT precedes this event.
        XCTAssertEqual(try serverSocketId(for: root), root.sid)
        XCTAssertEqual(rootConnects, 2, "The engine has to actually reconnect, or this proves nothing")
        XCTAssertEqual(errorCount, 1, "The namespace must not be rejoined after the server refused it")
        XCTAssertEqual(try connectFrameCount(), 3, "Only initial root, refused namespace and reconnected root CONNECTs are allowed")
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

    // MARK: socket.ts — "should not ack upon disconnection (callback)"

    /// The mirror image of the test above: an ack registered with no timeout on
    /// a socket that is then disconnected is dropped silently. It must never
    /// fire — not with data, not with an error — and it must not stay in the
    /// registry (JS `_clearAcks` empties `socket.acks`).
    func testANoTimeoutAckIsNotCalledAfterDisconnecting() {
        let socket = makeManager().socket(forNamespace: "/")
        connect(socket)

        let neverAcked = expectation(description: "the ack must not fire after disconnecting")
        neverAcked.isInverted = true
        socket.emit("echo", "a", ack: { _, _ in neverAcked.fulfill() })
        // JS registers the ack synchronously inside `emit()` and disconnects on
        // the very next line. Here registration is dispatched to the manager's
        // handleQueue, so the disconnect goes through that same serial queue: it
        // lands after the registration and before any ack the server sends back,
        // which a wall-clock wait could not guarantee. (`handleQueue.sync` is not
        // an option — this manager's handleQueue is the queue we are on.)
        manager.handleQueue.socketAsync { socket.disconnect() }
        settle(0.2)
        // Read on handleQueue: it is the main queue, which is this thread.
        XCTAssertTrue(socket.ackHandlers.pendingTimedAckIDs.isEmpty)

        // The server may well answer the echo; none of it may reach the callback.
        settle(1)
        wait(for: [neverAcked], timeout: 0.1)
    }

    // MARK: socket.ts — "clears socket.id upon disconnection"

    /// Root IDs match the server's ID and are cleared by explicit disconnection.
    func testSocketIdIsClearedOnDisconnect() throws {
        let socket = makeManager().socket(forNamespace: "/")

        let connected = expectation(description: "connect")
        socket.on(clientEvent: .connect) { _, _ in connected.fulfill() }
        socket.connect()
        wait(for: [connected], timeout: 5)
        XCTAssertEqual(try serverSocketId(for: socket), try XCTUnwrap(socket.sid))

        let disconnected = expectation(description: "disconnect")
        disconnected.assertForOverFulfill = false
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
        DispatchQueue.main.socketAsyncAfter(deadline: .now() + 1) { settled.fulfill() }
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

    // MARK: connection.ts — "should work with false"

    func testFalseSurvivesTheRoundTrip() {
        let socket = connect(makeManager().socket(forNamespace: "/"))

        let received = expectation(description: "false comes back")
        socket.on("false") { data, _ in
            XCTAssertEqual(data.first as? Bool, false, "A falsy value must not be lost or turned into nil")
            received.fulfill()
        }
        socket.emit("false")

        wait(for: [received], timeout: 5)
    }

    // MARK: connection.ts — "should connect to a namespace after connection established"

    func testJoinANamespaceAfterTheConnectionIsEstablished() {
        let manager = makeManager()
        connect(manager.socket(forNamespace: "/"))

        let foo = connect(manager.socket(forNamespace: "/foo"))

        XCTAssertEqual(foo.status, .connected)
    }

    // MARK: connection.ts — "should open a new namespace after connection gets closed"

    func testJoinANewNamespaceAfterTheConnectionWasClosed() {
        let manager = makeManager()
        let root = connect(manager.socket(forNamespace: "/"))

        let disconnected = expectation(description: "disconnect")
        disconnected.assertForOverFulfill = false
        root.on(clientEvent: .disconnect) { _, _ in disconnected.fulfill() }
        root.disconnect()
        wait(for: [disconnected], timeout: 5)

        let foo = connect(manager.socket(forNamespace: "/foo"))

        XCTAssertEqual(foo.status, .connected)
    }

    // MARK: connection.ts — "should not reopen a cached but active socket"

    /// Looking up a connected, active socket must not send another CONNECT.
    /// A post-lookup server round trip precedes the raw-frame count assertion.
    func testFetchingTheSameNamespaceTwiceSendsOneConnectFrame() throws {
        let manager = makeManager(.autoConnect(true))
        let socket = manager.defaultSocket
        // autoConnect starts I/O asynchronously; install the handler before
        // yielding the main handle queue instead of calling connect twice.
        let connected = expectation(description: "auto-connected cached socket")
        socket.once(clientEvent: .connect) { _, _ in connected.fulfill() }
        wait(for: [connected], timeout: 5)
        XCTAssertEqual(socket.status, .connected)
        XCTAssertTrue(socket.active)
        let again = manager.socket(forNamespace: "/")
        XCTAssertTrue(socket === again, "The manager has to hand back the cached socket")
        XCTAssertEqual(try serverSocketId(for: again), socket.sid)
        XCTAssertEqual(try connectFrameCount(), 1)
    }

    // MARK: connection.ts — "should not reopen an already active socket"

    func testTwoNamespacesSendOneConnectFrameEach() throws {
        let manager = makeManager()

        connect(manager.socket(forNamespace: "/"))
        connect(manager.socket(forNamespace: "/foo"))
        settle(1)

        XCTAssertEqual(try connectFrameCount(), 2)
    }

    // MARK: socket.ts — "should have an accessible socket id equal to the server-side socket id (custom namespace)"

    /// Both namespace IDs must equal IDs independently supplied by their servers.
    func testSocketIdOnACustomNamespace() throws {
        let manager = makeManager()
        let root = connect(manager.socket(forNamespace: "/"))
        let foo = connect(manager.socket(forNamespace: "/foo"))

        XCTAssertEqual(try serverSocketId(for: root), try XCTUnwrap(root.sid))
        XCTAssertEqual(try serverSocketId(for: foo), try XCTUnwrap(foo.sid))
        XCTAssertNotEqual(foo.sid, root.sid, "Each namespace gets its own server-side id")
    }

    // MARK: socket.ts — "doesn't fire an error event if we force disconnect in opening state"

    func testNoErrorWhenDisconnectingWhileStillOpening() {
        let manager = makeManager()
        let socket = manager.socket(forNamespace: "/")

        var errors = [[Any]]()
        socket.on(clientEvent: .error) { data, _ in errors.append(data) }
        socket.on(clientEvent: .connectError) { data, _ in errors.append(data) }

        socket.connect()
        socket.disconnect()

        settle(1.5)

        XCTAssertTrue(errors.isEmpty, "Tearing down an in-flight connect is not an error: \(errors)")
    }

    // MARK: socket.ts — "doesn't fire a connect_error event when the connection is already established"

    /// The JS assertion concerns connect_error, not Swift's runtime .error
    /// diagnostic. URLSession may report a native receive failure when the
    /// server drops the transport; that detail must not be suppressed just to
    /// satisfy this test. The drop must still disconnect and reconnect once.
    func testNoErrorEventWhenAnEstablishedConnectionDrops() throws {
        let manager = makeManager(.reconnectWait(1))
        let socket = connect(manager.socket(forNamespace: "/"))
        defer { socket.removeAllHandlers() }

        var connectErrors = [[Any]]()
        var lifecycle = [String]()
        var disconnectCount = 0
        var connectCount = 0
        let disconnected = expectation(description: "transport disconnected")
        let reconnected = expectation(description: "namespace reconnected")
        socket.on(clientEvent: .connectError) { data, _ in connectErrors.append(data) }
        socket.on(clientEvent: .disconnect) { data, _ in
            lifecycle.append("disconnect")
            disconnectCount += 1
            XCTAssertTrue(["transport close", "transport error"].contains(data.first as? String ?? ""))
            if disconnectCount == 1 { disconnected.fulfill() }
        }
        socket.on(clientEvent: .reconnect) { _, _ in lifecycle.append("reconnect") }
        socket.on(clientEvent: .connect) { _, _ in
            lifecycle.append("connect")
            connectCount += 1
            if connectCount == 1 { reconnected.fulfill() }
        }

        try killTransport(ofSocketWithId: XCTUnwrap(socket.sid))
        wait(for: [disconnected, reconnected], timeout: 15, enforceOrder: true)
        // A real round trip proves that the replacement connection is usable
        // and provides a processing barrier instead of the old fixed sleep.
        XCTAssertEqual(try serverSocketId(for: socket), socket.sid)

        XCTAssertTrue(connectErrors.isEmpty, "An established transport drop is not a connect_error: \(connectErrors)")
        XCTAssertEqual(lifecycle, ["disconnect", "reconnect", "connect"])
        XCTAssertEqual(disconnectCount, 1)
        XCTAssertEqual(connectCount, 1)
        XCTAssertEqual(socket.status, .connected)
        XCTAssertTrue(socket.active)
    }

    // MARK: connection.ts — "should reconnect manually"

    func testReconnectManually() {
        let manager = makeManager()
        let socket = manager.socket(forNamespace: "/")
        connect(socket)

        let disconnected = expectation(description: "manual disconnect")
        disconnected.assertForOverFulfill = false
        socket.on(clientEvent: .disconnect) { _, _ in disconnected.fulfill() }
        socket.disconnect()
        wait(for: [disconnected], timeout: 5)

        connect(socket)

        XCTAssertEqual(socket.status, .connected)
    }

    // MARK: connection.ts — "should reconnect automatically after reconnecting manually"

    func testReconnectAutomaticallyAfterReconnectingManually() throws {
        let manager = makeManager(.reconnectWait(1))
        let socket = manager.socket(forNamespace: "/")
        connect(socket)

        let disconnected = expectation(description: "manual disconnect")
        disconnected.assertForOverFulfill = false
        socket.on(clientEvent: .disconnect) { _, _ in disconnected.fulfill() }
        socket.disconnect()
        wait(for: [disconnected], timeout: 5)

        connect(socket)

        // JS-aligned since 17.0.0: the drop reports `.disconnect(reason)`, the
        // successful retry reports `.reconnect(attempt)` and the re-joined
        // namespace then reports `.connect`.
        var connects = 0
        var transportKilled = false
        let cameBack = expectation(description: "reconnected after transport drop")
        cameBack.assertForOverFulfill = false
        socket.on(clientEvent: .connect) { _, _ in
            connects += 1
            if transportKilled {
                cameBack.fulfill()
            }
        }
        let connectsBeforeKill = connects
        try killTransport(ofSocketWithId: XCTUnwrap(socket.sid))
        transportKilled = true
        wait(for: [cameBack], timeout: 15)

        XCTAssertEqual(socket.status, .connected)
        XCTAssertGreaterThan(connects, connectsBeforeKill)
    }

    // MARK: socket.ts — "should properly disconnect then reconnect"

    func testDisconnectThenReconnect() {
        let manager = makeManager(.forceWebsockets(true))
        let socket = manager.socket(forNamespace: "/")

        var connects = 0
        var disconnects = 0
        var bounced = false
        let reconnected = expectation(description: "connected again after bounce")
        reconnected.assertForOverFulfill = false
        socket.on(clientEvent: .connect) { _, _ in
            connects += 1
            if !bounced {
                bounced = true
                socket.disconnect()
                socket.connect()
            } else {
                reconnected.fulfill()
            }
        }
        socket.on(clientEvent: .disconnect) { _, _ in disconnects += 1 }
        socket.connect()
        wait(for: [reconnected], timeout: 10)

        settle(1)

        XCTAssertEqual(connects, 2, "The bounce must be followed by exactly one reconnect")
        XCTAssertEqual(disconnects, 1, "The bounce must surface exactly one disconnect")
        XCTAssertEqual(socket.status, .connected)
    }

    // MARK: connection.ts — "should connect while disconnecting another socket"

    func testConnectWhileDisconnectingAnotherSocket() {
        let manager = makeManager()
        let foo = connect(manager.socket(forNamespace: "/foo"))

        let asd = manager.socket(forNamespace: "/asd")
        let asdConnected = expectation(description: "/asd connected")
        asdConnected.assertForOverFulfill = false
        asd.on(clientEvent: .connect) { _, _ in asdConnected.fulfill() }
        asd.connect()
        foo.disconnect()
        wait(for: [asdConnected], timeout: 5)

        XCTAssertEqual(asd.status, .connected)
    }

    // MARK: connection.ts — "should stop reconnecting on a socket and keep to reconnect on another"

    func testStopReconnectingOnOneSocketButNotTheOther() throws {
        let manager = makeManager(.reconnectWait(1))
        let socket1 = manager.socket(forNamespace: "/")
        let socket2 = manager.socket(forNamespace: "/asd")

        var connects1 = 0
        var connects2 = 0
        let bothConnected = expectation(description: "both namespaces connected")
        bothConnected.expectedFulfillmentCount = 2
        bothConnected.assertForOverFulfill = false
        socket1.on(clientEvent: .connect) { _, _ in
            connects1 += 1
            bothConnected.fulfill()
        }
        socket2.on(clientEvent: .connect) { _, _ in
            connects2 += 1
            bothConnected.fulfill()
        }
        socket1.connect()
        socket2.connect()
        wait(for: [bothConnected], timeout: 5)

        // Registered after the initial connects, so this only fires on the
        // reconnect. The `connects2` count below proves the engine came back.
        let socket2Back = expectation(description: "second socket reconnected")
        socket2Back.assertForOverFulfill = false
        socket2.on(clientEvent: .connect) { _, _ in socket2Back.fulfill() }

        var stoppedFirst = false
        socket1.on(clientEvent: .reconnectAttempt) { _, _ in
            if !stoppedFirst {
                stoppedFirst = true
                socket1.disconnect()
            }
        }

        try killTransport(ofSocketWithId: XCTUnwrap(socket1.sid))
        wait(for: [socket2Back], timeout: 15)

        settle(2)

        XCTAssertGreaterThan(connects2, 1, "The engine has to actually reconnect, or this proves nothing")
        XCTAssertEqual(connects1, 1, "The stopped socket must not connect again")
    }

    // MARK: connection.ts — "should not try to reconnect and should form a connection when connecting to correct port with default timeout"

    func testNoReconnectAttemptWhenConnectingToCorrectPort() {
        let manager = makeManager(.reconnects(true), .reconnectWait(1))
        let socket = manager.socket(forNamespace: "/valid")

        var attempts = 0
        socket.on(clientEvent: .reconnectAttempt) { _, _ in attempts += 1 }

        connect(socket)
        settle(2)

        XCTAssertEqual(attempts, 0, "A healthy connection must not attempt to reconnect")
        XCTAssertEqual(socket.status, .connected)
    }

    // MARK: socket.ts — "should properly encode the parameters"

    func testQueryParametersAreProperlyEncoded() {
        let manager = makeManager(.connectParams(["&a": "&=?a"]))
        let socket = manager.socket(forNamespace: "/abc")

        let gotHandshake = expectation(description: "handshake")
        var queryValue: String?
        socket.on("handshake") { data, _ in
            let handshake = data.first as? [String: Any]
            let query = handshake?["query"] as? [String: Any]
            queryValue = query?["&a"] as? String
            gotHandshake.fulfill()
        }
        socket.connect()
        wait(for: [gotHandshake], timeout: 5)

        XCTAssertEqual(queryValue, "&=?a")
    }

    // MARK: connection.ts — "should send events with ArrayBuffers in the correct order"

    func testBinaryEventsArriveInOrder() {
        let socket = connect(makeManager().socket(forNamespace: "/"))

        let acked = expectation(description: "abuff2-ack")
        socket.on("abuff2-ack") { _, _ in acked.fulfill() }
        socket.emit("abuff1", Data("abuff1".utf8))
        socket.emit("abuff2", "please arrive second")
        wait(for: [acked], timeout: 5)
    }

    // MARK: connection.ts — "should stop trying to reconnect"

    func testStopTryingToReconnect() {
        manager = SocketManager(socketURL: URL(string: "http://127.0.0.1:9823")!,
                                config: [.log(false), .reconnectWait(1)])
        let socket = manager.socket(forNamespace: "/")

        var attempts = 0
        var stopped = false
        socket.on(clientEvent: .reconnectAttempt) { _, _ in
            attempts += 1
            if !stopped {
                stopped = true
                self.manager.reconnects = false
            }
        }
        socket.connect()

        settle(4)

        XCTAssertEqual(attempts, 1, "Disabling reconnection must stop the loop after the first attempt")
        XCTAssertNotEqual(socket.status, .connected)
    }

    // MARK: connection.ts — "should not try to reconnect with incorrect port when reconnection disabled"

    func testNoReconnectWhenDisabledWithIncorrectPort() {
        manager = SocketManager(socketURL: URL(string: "http://127.0.0.1:9823")!,
                                config: [.log(false), .reconnects(false), .reconnectWait(1)])
        let socket = manager.socket(forNamespace: "/")

        var attempts = 0
        socket.on(clientEvent: .reconnectAttempt) { _, _ in attempts += 1 }

        let terminal = expectation(description: "terminal error or disconnect")
        terminal.assertForOverFulfill = false
        var terminalReason: String?
        socket.on(clientEvent: .error) { data, _ in
            terminalReason = self.errorMessage(from: data)
            terminal.fulfill()
        }
        socket.on(clientEvent: .connectError) { data, _ in
            terminalReason = self.errorMessage(from: data)
            terminal.fulfill()
        }
        socket.on(clientEvent: .disconnect) { data, _ in
            terminalReason = self.errorMessage(from: data)
            terminal.fulfill()
        }
        socket.connect()
        wait(for: [terminal], timeout: 5)

        settle(3)

        XCTAssertEqual(attempts, 0, "Reconnect attempts must not fire when reconnection is disabled")
        XCTAssertNotNil(terminalReason, "A terminal event must have arrived, or this proves nothing")
    }

    // MARK: connection.ts — "should try to reconnect twice and fail when requested two attempts with incorrect address and reconnect enabled"

    func testReconnectTwiceThenFailWithIncorrectAddress() {
        manager = SocketManager(socketURL: URL(string: "http://127.0.0.1:9823")!,
                                config: [.log(false), .reconnects(true), .reconnectAttempts(2), .reconnectWait(1)])
        let socket = manager.socket(forNamespace: "/")

        var attempts = 0
        socket.on(clientEvent: .reconnectAttempt) { _, _ in attempts += 1 }

        let failed = expectation(description: "reconnect failed")
        failed.assertForOverFulfill = false
        // JS `reconnect_failed`; the Swift-only `.disconnect("Reconnect Failed")`
        // was removed in 17.0.0.
        socket.on(clientEvent: .reconnectFailed) { _, _ in failed.fulfill() }
        socket.connect()
        wait(for: [failed], timeout: 15)

        XCTAssertEqual(attempts, 2)
    }

    // MARK: connection.ts — "should close the engine upon decoding exception"

    /// Proves the engine is closed and re-opened on a decoding exception: after
    /// injecting bad data the socket reports `.disconnect("parse error")` — the
    /// reason JS emits on this path — and connects again with a different sid.
    func testParseErrorClosesEngineAndReconnectsWithFreshSession() {
        makeManager(.reconnectWait(1))
        let socket = manager.socket(forNamespace: "/")
        connect(socket)
        let oldSid = socket.sid
        XCTAssertNotNil(oldSid)

        var sawReconnectSignal = false
        let signal = expectation(description: "reconnect signal")
        signal.assertForOverFulfill = false
        socket.on(clientEvent: .reconnect) { _, _ in
            sawReconnectSignal = true
            signal.fulfill()
        }
        socket.on(clientEvent: .reconnectAttempt) { _, _ in
            sawReconnectSignal = true
            signal.fulfill()
        }

        // JS `Manager.ondata` → `onclose("parse error")` → `Socket.onclose`.
        let parseErrorReported = expectation(description: "disconnect with parse error")
        parseErrorReported.assertForOverFulfill = false
        socket.on(clientEvent: .disconnect) { data, _ in
            if data.first as? String == "parse error" { parseErrorReported.fulfill() }
        }

        let reconnected = expectation(description: "reconnect")
        reconnected.assertForOverFulfill = false
        var newSid: String?
        var sawSignalBeforeReconnect = false
        socket.on(clientEvent: .connect) { _, _ in
            sawSignalBeforeReconnect = sawReconnectSignal
            newSid = socket.sid
            reconnected.fulfill()
        }

        // The entry point the engine calls with incoming data, i.e. the same
        // injection point as the JS test's `engine.emit("data", "bad")`.
        manager.parseEngineMessage("bad")

        wait(for: [parseErrorReported, signal, reconnected], timeout: 15)
        XCTAssertTrue(sawSignalBeforeReconnect, "A .reconnect or .reconnectAttempt must be observed before the second .connect")
        XCTAssertNotNil(newSid)
        // A fresh engine.io session: this client reuses the engine object, so
        // the new sid (not object identity) is what proves the old engine was
        // closed and a new one connected.
        XCTAssertNotEqual(newSid, oldSid)
    }

    // MARK: socket.ts — "fire a connect_error event on open timeout (polling)"

    /// `.connectTimeout(0)` fails the attempt before the handshake can
    /// complete — the JS `timeout: 0` trick — so the namespace never matters.
    func testConnectErrorOnOpenTimeoutPolling() {
        let socket = makeManager(.connectTimeout(0), .forcePolling(true), .reconnects(false))
            .socket(forNamespace: "/")

        let failed = expectation(description: "connect error")
        failed.assertForOverFulfill = false
        var message: String?
        socket.on(clientEvent: .connectError) { data, _ in
            message = data.first as? String
            failed.fulfill()
        }
        socket.connect()
        wait(for: [failed], timeout: 5)

        XCTAssertEqual(message, "timeout")
    }

    // MARK: socket.ts — "fire a connect_error event on open timeout (websocket)"

    func testConnectErrorOnOpenTimeoutWebsocket() {
        let socket = makeManager(.connectTimeout(0), .forceWebsockets(true), .reconnects(false))
            .socket(forNamespace: "/")

        let failed = expectation(description: "connect error")
        failed.assertForOverFulfill = false
        var message: String?
        socket.on(clientEvent: .connectError) { data, _ in
            message = data.first as? String
            failed.fulfill()
        }
        socket.connect()
        wait(for: [failed], timeout: 5)

        XCTAssertEqual(message, "timeout")
    }

    // MARK: connection.ts — "should try to reconnect twice and fail when requested two attempts with immediate timeout and reconnect enabled"

    func testReconnectTwiceThenFailWithImmediateTimeout() {
        let manager = makeManager(.connectTimeout(0), .reconnectAttempts(2), .reconnectWait(1))
        let socket = manager.socket(forNamespace: "/")

        var attempts = 0
        socket.on(clientEvent: .reconnectAttempt) { _, _ in attempts += 1 }

        let failed = expectation(description: "reconnect failed")
        failed.assertForOverFulfill = false
        // JS `reconnect_failed`; the Swift-only `.disconnect("Reconnect Failed")`
        // was removed in 17.0.0.
        socket.on(clientEvent: .reconnectFailed) { _, _ in failed.fulfill() }
        socket.connect()
        wait(for: [failed], timeout: 15)

        XCTAssertEqual(attempts, 2)
    }

    // MARK: connection.ts — "should attempt reconnects after a failed reconnect"

    /// Written exactly to the JS contract: after the first `reconnect_failed`
    /// a new `connect()` must get another full budget of 2 attempts. JS resets
    /// its attempt counter on `reconnect_failed`; if this client does not,
    /// this test fails — that is a FINDING, do not weaken the test.
    func testAttemptReconnectsAfterAFailedReconnect() {
        let manager = makeManager(.connectTimeout(0), .reconnectAttempts(2), .reconnectWait(1))
        let socket = manager.socket(forNamespace: "/")

        var attempts = 0
        socket.on(clientEvent: .reconnectAttempt) { _, _ in attempts += 1 }

        var failures = 0
        let firstFailed = expectation(description: "first reconnect failed")
        firstFailed.assertForOverFulfill = false
        let secondFailed = expectation(description: "second reconnect failed")
        secondFailed.assertForOverFulfill = false
        socket.on(clientEvent: .reconnectFailed) { _, _ in
            failures += 1
            if failures == 1 {
                firstFailed.fulfill()
            } else if failures == 2 {
                secondFailed.fulfill()
            }
        }
        socket.connect()
        wait(for: [firstFailed], timeout: 15)
        XCTAssertEqual(attempts, 2, "The first round must spend exactly its budget of 2 attempts")

        socket.connect()
        wait(for: [secondFailed], timeout: 15)
        XCTAssertEqual(attempts, 4, "The second round must get a fresh budget of 2 attempts")
    }

    // MARK: connection.ts — "should not reconnect when force closed"

    func testNoReconnectWhenForceClosedDuringTimeout() {
        let manager = makeManager(.connectTimeout(0), .reconnectWait(1))
        let socket = manager.socket(forNamespace: "/")

        var errors = 0
        var attempts = 0
        var closed = false
        socket.on(clientEvent: .connectError) { _, _ in
            errors += 1
            if !closed {
                closed = true
                socket.disconnect()
            }
        }
        socket.on(clientEvent: .reconnectAttempt) { _, _ in attempts += 1 }
        socket.connect()

        settle(2)

        XCTAssertGreaterThanOrEqual(errors, 1, "The timeout error must have fired, or this proves nothing")
        XCTAssertEqual(attempts, 0, "No reconnect attempt may fire after the socket was closed")
    }

    // MARK: connection.ts — "should stop reconnecting when force closed"

    func testStopReconnectingWhenForceClosed() {
        let manager = makeManager(.connectTimeout(0), .reconnectWait(1))
        let socket = manager.socket(forNamespace: "/")

        var attempts = 0
        var stopped = false
        socket.on(clientEvent: .reconnectAttempt) { _, _ in
            attempts += 1
            if !stopped {
                stopped = true
                socket.disconnect()
            }
        }
        socket.connect()

        settle(2.5)

        XCTAssertEqual(attempts, 1, "Closing the socket must stop the loop after the first attempt")
    }

    // MARK: connection.ts — "should reconnect after stopping reconnection"

    func testReconnectAfterStoppingReconnection() {
        let manager = makeManager(.connectTimeout(0), .reconnectAttempts(3), .reconnectWait(1))
        let socket = manager.socket(forNamespace: "/")

        var attempts = 0
        let attemptedAgain = expectation(description: "further reconnect attempt")
        attemptedAgain.assertForOverFulfill = false
        var restarted = false
        socket.on(clientEvent: .reconnectAttempt) { _, _ in
            attempts += 1
            if !restarted {
                restarted = true
                socket.disconnect()
                socket.connect()
            } else {
                attemptedAgain.fulfill()
            }
        }
        socket.connect()
        wait(for: [attemptedAgain], timeout: 10)

        XCTAssertGreaterThanOrEqual(attempts, 2, "Reconnecting after the stop must schedule further attempts")
    }

    // MARK: connection.ts — "should still try to reconnect twice after opening another socket asynchronously"

    func testReconnectTwiceAfterOpeningAnotherSocketAsynchronously() {
        manager = SocketManager(socketURL: URL(string: "http://127.0.0.1:9823")!,
                                config: [.log(false), .reconnects(true), .reconnectAttempts(2), .reconnectWait(1)])
        let socket = manager.socket(forNamespace: "/")

        var attempts = 0
        var openedSecond = false
        socket.on(clientEvent: .reconnectAttempt) { _, _ in
            attempts += 1
            if !openedSecond {
                openedSecond = true
                DispatchQueue.main.socketAsyncAfter(deadline: .now() + 0.5) {
                    let other = self.manager.socket(forNamespace: "/asd")
                    other.connect()
                }
            }
        }

        let failed = expectation(description: "reconnect failed")
        failed.assertForOverFulfill = false
        // JS `reconnect_failed`; the Swift-only `.disconnect("Reconnect Failed")`
        // was removed in 17.0.0.
        socket.on(clientEvent: .reconnectFailed) { _, _ in failed.fulfill() }
        socket.connect()
        wait(for: [failed], timeout: 15)

        XCTAssertEqual(attempts, 2, "Opening a second socket must not change the first socket's attempt budget")
    }

    // MARK: connection.ts — "should reopen a cached socket"

    /// With `autoConnect` on, asking for a namespace whose cached socket was
    /// disconnected re-connects it and hands back the same instance.
    func testReopenACachedSocket() {
        let manager = makeManager(.autoConnect(true))
        let socket = manager.socket(forNamespace: "/")

        let connected = expectation(description: "connect")
        connected.assertForOverFulfill = false
        socket.on(clientEvent: .connect) { _, _ in connected.fulfill() }
        wait(for: [connected], timeout: 5)

        let disconnected = expectation(description: "disconnect")
        disconnected.assertForOverFulfill = false
        socket.on(clientEvent: .disconnect) { _, _ in disconnected.fulfill() }
        socket.disconnect()
        wait(for: [disconnected], timeout: 5)

        let reconnected = expectation(description: "reconnect")
        reconnected.assertForOverFulfill = false
        socket.on(clientEvent: .connect) { _, _ in reconnected.fulfill() }

        let again = manager.socket(forNamespace: "/")
        XCTAssertTrue(again === socket, "The manager has to hand back the cached socket")
        XCTAssertTrue(again.active, "Fetching an inactive socket with autoConnect must reactivate it")

        wait(for: [reconnected], timeout: 5)
    }

    // MARK: engine.io-client — Polling.uri() cache buster

    /// Every polling request has to carry a unique `t=` parameter so that
    /// intermediaries never serve a cached long-poll response, JS-aligned
    /// with `Polling.uri()` in engine.io-client. The fixture taps the HTTP
    /// layer because poll URLs never reach the packet layer.
    func testPollingRequestsCarryCacheBustingTimestamp() throws {
        connect(makeManager(.forcePolling(true)).socket(forNamespace: "/"))
        settle(0.5)

        let (status, body) = try server.admin("/admin/last-polling-query", method: "GET")
        XCTAssertEqual(status, 200)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let query = json?["query"] as? String
        XCTAssertNotNil(query, "The server must have seen at least one polling request")

        let items = URLComponents(string: "http://localhost/?\(query ?? "")")?.queryItems ?? []
        let t = items.first(where: { $0.name == "t" })?.value
        XCTAssertNotNil(t, "Polling requests must carry the t= cache buster (saw query: \(query ?? "nil"))")
        XCTAssertFalse(t?.isEmpty ?? true)
    }

    // MARK: socket.ts — "should use the default timeout value"

    func testDefaultAckTimeoutApplies() {
        let socket = connect(makeManager(.ackTimeout(0.05)).socket(forNamespace: "/"))

        let timedOut = expectation(description: "default timeout fires")
        socket.emit("never_ack", ack: { err, _ in
            XCTAssertEqual(err as? SocketAckError, .timeout)
            timedOut.fulfill()
        })
        wait(for: [timedOut], timeout: 5)
    }

    // MARK: socket.ts — "should ack with an error upon disconnection (callback & ackTimeout)"

    func testAckTimeoutFailsWithErrorOnDisconnect() {
        let socket = connect(makeManager(.ackTimeout(10)).socket(forNamespace: "/"))

        let disconnected = expectation(description: "ack fails on disconnect")
        socket.emit("never_ack", ack: { err, _ in
            XCTAssertEqual(err as? SocketAckError, .disconnected)
            disconnected.fulfill()
        })
        socket.disconnect()
        wait(for: [disconnected], timeout: 5)
    }

    // MARK: socket.ts — "should use the default timeout value" (positive round trip)

    /// The default must not break the happy path: a server ack still arrives
    /// as `(nil, data)`.
    func testEmitWithDefaultAckTimeoutRoundTrip() {
        let socket = connect(makeManager(.ackTimeout(5)).socket(forNamespace: "/"))

        let acked = expectation(description: "server ack")
        socket.emit("echo", "a", ack: { err, data in
            XCTAssertNil(err)
            XCTAssertEqual(data.first as? String, "a")
            acked.fulfill()
        })
        wait(for: [acked], timeout: 5)
    }

    // MARK: socket.ts > query option — "should accept an object (default namespace)"

    func testQueryOptionAcceptsAnObjectOnTheDefaultNamespace() throws {
        let socket = makeManager(.connectParams(["e": "f"])).socket(forNamespace: "/")
        connect(socket)

        XCTAssertEqual(try handshakeQuery(for: socket)["e"] as? String, "f")
    }

    // MARK: socket.ts > query option — "should accept a query string (default namespace)"

    /// JS reads the parameters out of the server URL
    /// (`opts.query = parsed.queryKey` in `lib/index.ts`).
    func testQueryOptionAcceptsAQueryStringOnTheDefaultNamespace() throws {
        manager = SocketManager(socketURL: URL(string: "http://127.0.0.1:\(server.port)/?c=d")!,
                                config: [.log(false)])
        let socket = manager.socket(forNamespace: "/")
        connect(socket)

        XCTAssertEqual(try handshakeQuery(for: socket)["c"] as? String, "d")
    }

    // MARK: socket.ts > query option — "should accept an object"

    /// The JS test puts the namespace in the URL (`io(BASE_URL + "/abc")`);
    /// here the namespace comes from `socket(forNamespace:)`, which is the only
    /// way this client selects one.
    func testQueryOptionAcceptsAnObjectOnACustomNamespace() {
        let socket = makeManager(.connectParams(["a": "b"])).socket(forNamespace: "/abc")

        XCTAssertEqual(handshakeEventQuery(for: socket)["a"] as? String, "b")
    }

    // MARK: socket.ts > query option — "should accept a query string"

    func testQueryOptionAcceptsAQueryStringOnACustomNamespace() {
        manager = SocketManager(socketURL: URL(string: "http://127.0.0.1:\(server.port)/?b=c&d=e")!,
                                config: [.log(false)])
        let socket = manager.socket(forNamespace: "/abc")

        let query = handshakeEventQuery(for: socket)
        XCTAssertEqual(query["b"] as? String, "c")
        XCTAssertEqual(query["d"] as? String, "e")
    }

    /// The default namespace answers `getHandshake` with its own handshake.
    private func handshakeQuery(for socket: SocketIOClient) throws -> [String: Any] {
        let replied = expectation(description: "handshake for \(socket.nsp)")
        var handshake: [String: Any]?
        socket.emitWithAck("getHandshake").timingOut(after: 5) { data in
            handshake = data.first as? [String: Any]
            replied.fulfill()
        }
        wait(for: [replied], timeout: 5)

        return try XCTUnwrap(handshake?["query"] as? [String: Any])
    }

    /// `/abc` pushes its handshake on connect, like `server.of("/abc")` in the
    /// JS support server.
    private func handshakeEventQuery(for socket: SocketIOClient) -> [String: Any] {
        let got = expectation(description: "handshake event for \(socket.nsp)")
        got.assertForOverFulfill = false
        var handshake: [String: Any]?
        socket.on("handshake") { data, _ in
            handshake = data.first as? [String: Any]
            got.fulfill()
        }
        socket.connect()
        wait(for: [got], timeout: 5)

        return (handshake?["query"] as? [String: Any]) ?? [:]
    }

    // MARK: connection.ts — "should emit date as string"

    func testEmitDateAsString() {
        let socket = makeManager().socket(forNamespace: "/")
        connect(socket)

        let took = expectation(description: "takeDate")
        took.assertForOverFulfill = false
        var received: Any?
        socket.on("takeDate") { data, _ in
            received = data.first
            took.fulfill()
        }
        socket.emit("getDate")
        wait(for: [took], timeout: 5)

        XCTAssertTrue(received is String, "A Date crosses the wire as a string, got \(String(describing: received))")
    }

    // MARK: connection.ts — "should emit date in object"

    func testEmitDateInObject() {
        let socket = makeManager().socket(forNamespace: "/")
        connect(socket)

        let took = expectation(description: "takeDateObj")
        took.assertForOverFulfill = false
        var received: [String: Any]?
        socket.on("takeDateObj") { data, _ in
            received = data.first as? [String: Any]
            took.fulfill()
        }
        socket.emit("getDateObj")
        wait(for: [took], timeout: 5)

        XCTAssertNotNil(received)
        XCTAssertTrue(received?["date"] is String)
    }

    // MARK: connection.ts — "should receive date with ack"

    func testReceiveDateWithAck() {
        let socket = makeManager().socket(forNamespace: "/")
        connect(socket)

        let acked = expectation(description: "getAckDate")
        var received: Any?
        socket.emitWithAck("getAckDate", ["test": true]).timingOut(after: 5) { data in
            received = data.first
            acked.fulfill()
        }
        wait(for: [acked], timeout: 5)

        XCTAssertTrue(received is String)
    }

    /// The outgoing direction of the same rule: a `Date` this client emits
    /// arrives as the ISO-8601 string `JSON.stringify` produces.
    func testEmittedDateArrivesAsAnISO8601String() {
        let socket = makeManager().socket(forNamespace: "/")
        connect(socket)

        let date = Date(timeIntervalSince1970: 1_704_164_645.678)
        let acked = expectation(description: "echo")
        var received: Any?
        socket.emitWithAck("echo", date).timingOut(after: 5) { data in
            received = data.first
            acked.fulfill()
        }
        wait(for: [acked], timeout: 5)

        XCTAssertEqual(received as? String, "2024-01-02T03:04:05.678Z")
    }

    // MARK: socket.ts — "should emit an event and wait for the acknowledgement"

    func testEmitWithAckAwaitsTheAcknowledgement() async throws {
        let socket = makeManager().socket(forNamespace: "/")
        connect(socket)

        let value = try await socket.emitWithAck("echo", 123)

        XCTAssertEqual(value.first as? Int, 123)
    }

    // MARK: socket.ts > timeout — "should not timeout when the server does acknowledge the event (promise)"

    func testTimedEmitWithAckDoesNotTimeOutWhenTheServerAcknowledges() async throws {
        let socket = makeManager().socket(forNamespace: "/")
        connect(socket)

        let value = try await socket.timeout(after: 5).emitWithAck("echo", 42)

        XCTAssertEqual(value.first as? Int, 42)
    }

    // MARK: socket.ts > acknowledgement upon disconnection — on a retried drop

    /// The JS scenarios "should ack with an error upon disconnection
    /// (callback & timeout / ackTimeout)" disconnect manually, but JS
    /// `Socket.onclose` runs `_clearAcks()` on *every* close, so a transport
    /// drop that the manager retries settles the pending acknowledgement the
    /// same way. `never_ack` guarantees the server never answers, so the only
    /// thing that can settle it is the close. The timeout is far longer than
    /// the test budget, so a `.timeout` here would be a different bug.
    func testPendingAckFailsWhenTheTransportIsKilledAndTheSocketReconnects() throws {
        let socket = connect(makeManager(.ackTimeout(60), .reconnectWait(1)).socket(forNamespace: "/"))
        let sid = try XCTUnwrap(socket.sid)

        let settled = expectation(description: "pending ack settles on the retried drop")
        socket.emit("never_ack", ack: { err, _ in
            XCTAssertEqual(err as? SocketAckError, .disconnected)
            settled.fulfill()
        })
        // A round trip on the same session proves the emit reached the server
        // before the transport is killed.
        XCTAssertEqual(try serverSocketId(for: socket), sid)

        let reconnected = expectation(description: "namespace re-joined")
        reconnected.assertForOverFulfill = false
        socket.on(clientEvent: .connect) { _, _ in reconnected.fulfill() }

        try killTransport(ofSocketWithId: sid)
        wait(for: [settled, reconnected], timeout: 20)

        XCTAssertEqual(socket.status, .connected)
        XCTAssertTrue(socket.active)
    }
}
