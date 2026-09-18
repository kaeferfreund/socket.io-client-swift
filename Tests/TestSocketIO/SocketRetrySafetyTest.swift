import Foundation
import XCTest
@testable import SocketIO

/// Queue/ack invariants use a synchronous fake writer, not a 10ms localhost budget.
final class SocketRetrySafetyTest: XCTestCase {
    private var manager: SocketManager!
    private var socket: SocketIOClient!
    private var engine: MockEngine!

    private func make(_ config: SocketIOClientConfiguration = [.retries(1), .ackTimeout(1)]) {
        manager = SocketManager(socketURL: URL(string: "http://localhost")!, config: config)
        socket = manager.defaultSocket
        engine = MockEngine()
        manager.engine = engine
        socket.didConnect(toNamespace: "/", payload: ["sid": "first"])
    }
    private func drain() {
        let done = expectation(description: "handle queue barrier")
        manager.handleQueue.async { done.fulfill() }
        wait(for: [done], timeout: 3)
    }
    private func ackID(_ position: Int) throws -> Int {
        try manager.parseString(engine.sentPackets[position].0).id
    }
    override func tearDown() {
        if let socket = socket { socket.clearRecoveryState() }
        socket = nil; engine = nil; manager = nil
        super.tearDown()
    }

    func testExpiredHeartbeatBuffersInsteadOfSendingOnTheStaleConnection() throws {
        make([])
        engine.hasPingExpired = true
        socket.emit("after-suspension", "data")
        XCTAssertTrue(engine.sentPackets.isEmpty)
        socket.didDisconnect(reason: "ping timeout")
        engine.hasPingExpired = false
        socket.didConnect(toNamespace: "/", payload: ["sid": "fresh"])
        XCTAssertEqual(engine.sentPackets.count, 1)
        XCTAssertEqual(try manager.parseString(engine.sentPackets[0].0).event, "after-suspension")
    }

    func testIdentityResetCannotSweepTheNewIdentityAcknowledgement() {
        make([])
        socket.ackHandlers.addTimedAck(100, on: .main, callback: { _, _ in }, timeout: .infinity)
        socket.clearRecoveryState()
        socket.ackHandlers.addTimedAck(101, on: .main, callback: { _, _ in }, timeout: .infinity)
        drain()
        XCTAssertEqual(socket.ackHandlers.pendingTimedAckIDs, [101])
    }

    func testEmitImmediatelyFollowedByDisconnectFailsTheAlreadyRegisteredAck() {
        make([.ackTimeout(10)])
        let failed = expectation(description: "same-turn emit is registered before disconnect")
        socket.emit("never_ack", ack: { error, _ in
            XCTAssertEqual(error as? SocketAckError, .disconnected)
            failed.fulfill()
        })
        XCTAssertEqual(engine.sentPackets.count, 1)
        socket.didDisconnect(reason: "transport close")
        wait(for: [failed], timeout: 2)
    }

    func testTimedRetryDoesNotConsumeAnUnusedAckID() throws {
        make([.retries(1)])
        socket.timeout(after: 10).emit("x", ack: { _, _ in })
        drain()
        XCTAssertEqual(try ackID(0), 0)
    }

    func testPlainRetryInheritsAckTimeoutAndCannotBlockNextPacketForever() {
        make([.retries(1), .ackTimeout(0)])
        let done = expectation(description: "next packet exhausted its budget")
        socket.emit("never-acked")
        socket.emit("next", ack: { error, _ in
            XCTAssertEqual(error as? SocketAckError, .timeout)
            done.fulfill()
        })
        wait(for: [done], timeout: 3)
        XCTAssertEqual(engine.sentPackets.count, 4)
        XCTAssertEqual(socket.testRetryQueueCount, 0)
    }

    func testPlainLocalCompletionFiresOnceAcrossRetries() {
        make([.retries(2), .ackTimeout(0)])
        let completed = expectation(description: "one local completion")
        var calls = 0
        socket.emit("never-acked", completion: { calls += 1; completed.fulfill() })
        let done = expectation(description: "following packet drained")
        socket.emit("next", ack: { _, _ in done.fulfill() })
        wait(for: [completed, done], timeout: 3)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(engine.sentPackets.count, 6)
    }

    func testRetryCannotBypassReservedEventValidation() {
        make()
        var errors = 0
        socket.on(clientEvent: .error) { _, _ in errors += 1 }
        for event in ["connect", "connect_error", "disconnect", "disconnecting", "newListener", "removeListener"] {
            socket.emit(event)
        }
        drain()
        XCTAssertEqual(errors, 6)
        XCTAssertEqual(socket.testRetryQueueCount, 0)
        XCTAssertTrue(engine.sentPackets.isEmpty)
        XCTAssertTrue(socket.ackHandlers.pendingTimedAckIDs.isEmpty)
    }

    func testReconnectRetiresOldAckAndOldDisconnectCannotCancelNewAttempt() throws {
        make()
        var replies = 0
        socket.emit("x", ack: { error, _ in XCTAssertNil(error); replies += 1 })
        drain()
        let oldID = try ackID(0)
        socket.didDisconnect(reason: "transport close")
        // Before the old asynchronous ack sweep executes, the new namespace opens.
        socket.didConnect(toNamespace: "/", payload: ["sid": "second"])
        let newID = try ackID(1)
        drain()
        XCTAssertNotEqual(oldID, newID)
        XCTAssertEqual(engine.sentPackets.count, 2)
        XCTAssertEqual(socket.ackHandlers.pendingTimedAckIDs, [newID])
        socket.handleAck(oldID, data: ["stale"])
        XCTAssertEqual(replies, 0)
        socket.handleAck(newID, data: ["current"])
        XCTAssertEqual(replies, 1)
        XCTAssertEqual(socket.testRetryQueueCount, 0)
    }

    func testConnectEventSeesAlreadyDrainedRetryHead() throws {
        make()
        socket.setTestStatus(.disconnected)
        socket.emit("buffered")
        drain()
        socket.on(clientEvent: .connect) { [self] _, _ in
            XCTAssertEqual(engine.sentPackets.count, 1)
            socket.emit("from-connect")
        }
        socket.didConnect(toNamespace: "/", payload: ["sid": "replacement"])
        drain()
        XCTAssertEqual(engine.sentPackets.count, 1)
        socket.handleAck(try ackID(0), data: [])
        drain()
        XCTAssertEqual(engine.sentPackets.count, 2)
    }

    func testIdentityResetCancelsRetryTimerAndCompletesUnsentOperation() {
        make([.retries(3)])
        socket.setTestStatus(.disconnected)
        let completed = expectation(description: "unsent local operation cancelled")
        socket.emit("unsent", completion: { completed.fulfill() })
        socket.clearRecoveryState()
        wait(for: [completed], timeout: 3)
        drain()
        XCTAssertTrue(engine.sentPackets.isEmpty)
        XCTAssertTrue(socket.ackHandlers.pendingTimedAckIDs.isEmpty)
        XCTAssertEqual(socket.testRetryQueueCount, 0)
    }

    func testNoTimeoutModernAckIsRemovedSilentlyOnDisconnect() {
        make([])
        var callbacks = 0
        socket.emit("x", ack: { _, _ in callbacks += 1 })
        drain()
        XCTAssertEqual(socket.ackHandlers.pendingTimedAckIDs.count, 1)
        socket.didDisconnect(reason: "transport close")
        drain()
        XCTAssertTrue(socket.ackHandlers.pendingTimedAckIDs.isEmpty)
        XCTAssertEqual(callbacks, 0)
    }

    func testRetryWithoutTimeoutSurvivesSeveralDisconnects() throws {
        make([.retries(1)])
        var callbacks = 0
        socket.emit("x", ack: { error, _ in XCTAssertNil(error); callbacks += 1 })
        drain()
        for index in 0..<3 {
            socket.didDisconnect(reason: "transport close")
            drain()
            socket.didConnect(toNamespace: "/", payload: ["sid": "s\(index)"])
        }
        XCTAssertEqual(callbacks, 0)
        socket.handleAck(try ackID(3), data: [])
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(socket.testRetryQueueCount, 0)
    }

    func testSelectiveAckSweepDoesNotDeleteLaterRegistration() {
        make([])
        socket.ackHandlers.addTimedAck(10, on: .main, callback: { _, _ in }, timeout: .infinity)
        let retired = socket.ackHandlers.pendingTimedAckIDs
        socket.ackHandlers.addTimedAck(11, on: .main, callback: { _, _ in }, timeout: .infinity)
        socket.ackHandlers.clearTimedAcks(reason: .disconnected, only: retired)
        XCTAssertEqual(socket.ackHandlers.pendingTimedAckIDs, [11])
    }

    func testCancelledBeforeRegistrationCannotHangInfiniteAsyncAck() {
        make([])
        let state = SocketAsyncAckState()
        state.cancel() // Models cancellation in the check-to-enqueue race window.
        let cancelled = expectation(description: "early cancellation observed at registration")
        socket.emitTimed(event: "x", items: [], timeout: .infinity, cancellation: state) { error, _ in
            XCTAssertTrue(error is CancellationError)
            cancelled.fulfill()
        }
        wait(for: [cancelled], timeout: 3)
        XCTAssertNil(state.registeredID)
        XCTAssertTrue(engine.sentPackets.isEmpty)
        XCTAssertTrue(socket.ackHandlers.pendingTimedAckIDs.isEmpty)
    }

    func testReplacingAnAckIDCannotFireItsOldTimer() {
        make([])
        var oldCalls = 0
        var newCalls = 0
        socket.ackHandlers.addTimedAck(50, on: .main, callback: { _, _ in oldCalls += 1 }, timeout: 0)
        socket.ackHandlers.addTimedAck(50, on: .main, callback: { _, _ in newCalls += 1 }, timeout: .infinity)
        drain()
        XCTAssertEqual(oldCalls, 0)
        XCTAssertEqual(newCalls, 0)
        socket.ackHandlers.executeTimedAck(50, with: [])
        XCTAssertEqual(newCalls, 1)
    }
}
