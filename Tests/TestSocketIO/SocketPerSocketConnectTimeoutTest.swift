import XCTest
@testable import SocketIO

final class SocketPerSocketConnectTimeoutTest: XCTestCase {
    private var manager: SocketManager!
    private var socket: SocketIOClient!

    override func setUp() {
        super.setUp()
        manager = SocketManager(socketURL: URL(string: "http://localhost")!,
                                config: [.autoConnect(false), .reconnects(false)])
        manager.engine = MockEngine()
        socket = manager.defaultSocket
    }

    override func tearDown() {
        manager.disconnect()
        socket = nil
        manager = nil
        super.tearDown()
    }

    private func letTimerDeadlinePass() {
        let settled = expectation(description: "past original connect deadline")
        DispatchQueue.main.socketAsyncAfter(deadline: .now() + 0.1) { settled.fulfill() }
        wait(for: [settled], timeout: 1)
    }

    func testSuccessfulConnectCannotTimeOutLaterReconnect() {
        socket.connect(timeoutAfter: 0.02) { XCTFail("successful attempt timed out") }
        socket.didConnect(toNamespace: "/", payload: ["sid": "first"])
        socket.setReconnecting(reason: "transport close")
        letTimerDeadlinePass()
        XCTAssertEqual(socket.status, .connecting)
        XCTAssertTrue(socket.active)
    }

    func testSynchronousSuccessDuringStatusChangeCancelsDeadline() {
        var first = true
        socket.on(clientEvent: .statusChange) { [self] _, _ in
            guard first, socket.status == .connecting else { return }
            first = false
            socket.didConnect(toNamespace: "/", payload: ["sid": "sync"])
        }
        socket.connect(timeoutAfter: 0.02) { XCTFail("synchronous success timed out") }
        socket.setReconnecting(reason: "transport close")
        letTimerDeadlinePass()
        XCTAssertEqual(socket.status, .connecting)
    }

    func testNewUntimedAttemptCancelsOldDeadline() {
        socket.connect(timeoutAfter: 0.02) { XCTFail("superseded attempt timed out") }
        socket.connect()
        letTimerDeadlinePass()
        XCTAssertEqual(socket.status, .connecting)
    }

    func testDisconnectAndReconnectCancelOldDeadline() {
        socket.connect(timeoutAfter: 0.02) { XCTFail("disconnected attempt timed out") }
        socket.disconnect()
        socket.connect()
        letTimerDeadlinePass()
        XCTAssertEqual(socket.status, .connecting)
    }

    func testUnsuccessfulAttemptStillCallsHandlerExactlyOnce() {
        var calls = 0
        socket.connect(timeoutAfter: 0.02) { calls += 1 }
        letTimerDeadlinePass()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(socket.status, .disconnected)
    }

    func testResetBeforeSuccessStillReportsTimeout() {
        var calls = 0
        socket.connect(timeoutAfter: 0.02) { calls += 1 }
        socket.abortPendingConnect()
        letTimerDeadlinePass()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(socket.status, .notConnected)
    }
}
