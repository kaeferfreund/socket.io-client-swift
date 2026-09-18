//
//  SocketEngineTest.swift
//  Socket.IO-Client-Swift
//
//  Created by Erik Little on 10/15/15.
//
//

import XCTest
@testable import SocketIO

class SocketEngineTest: XCTestCase {
    func testBasicPollingMessageV3() {
        let expect = expectation(description: "Basic polling test v3")

        socket.on("blankTest") {data, ack in
            expect.fulfill()
        }

        engine.setConfigs([.version(.two)])
        engine.parsePollingMessage("15:42[\"blankTest\"]")

        waitForExpectations(timeout: 3, handler: nil)
    }

    func testBasicPollingMessage() {
        let expect = expectation(description: "Basic polling test")
        socket.on("blankTest") {data, ack in
            expect.fulfill()
        }

        engine.parsePollingMessage("42[\"blankTest\"]")
        waitForExpectations(timeout: 3, handler: nil)
    }

    func testTwoPacketsInOnePollTest() {
        let finalExpectation = expectation(description: "Final packet in poll test")
        var gotBlank = false

        socket.on("blankTest") {data, ack in
            gotBlank = true
        }

        socket.on("stringTest") {data, ack in
            if let str = data[0] as? String, gotBlank {
                if str == "hello" {
                    finalExpectation.fulfill()
                }
            }
        }

        engine.parsePollingMessage("42[\"blankTest\"]\u{1e}42[\"stringTest\",\"hello\"]")
        waitForExpectations(timeout: 3, handler: nil)
    }

    func testEngineDoesErrorOnUnknownTransport() {
        let finalExpectation = expectation(description: "Unknown Transport")

        socket.on("error") {data, ack in
            if let error = data[0] as? String, error == "Unknown transport" {
                finalExpectation.fulfill()
            }
        }

        engine.parseEngineMessage("{\"code\": 0, \"message\": \"Unknown transport\"}")
        waitForExpectations(timeout: 3, handler: nil)
    }

    func testEngineDoesErrorOnUnknownMessage() {
        let finalExpectation = expectation(description: "Engine Errors")

        socket.on("error") {data, ack in
            finalExpectation.fulfill()
        }

        engine.parseEngineMessage("afafafda")
        waitForExpectations(timeout: 3, handler: nil)
    }

    func testEngineDecodesUTF8Properly() {
        let expect = expectation(description: "Engine Decodes utf8")

        socket.on("stringTest") {data, ack in
            XCTAssertEqual(data[0] as? String, "lïne one\nlīne \rtwo𦅙𦅛", "Failed string test")
            expect.fulfill()
        }

        let stringMessage = "42[\"stringTest\",\"lïne one\\nlīne \\rtwo𦅙𦅛\"]"

        engine.parsePollingMessage("\(stringMessage)")
        waitForExpectations(timeout: 3, handler: nil)
    }

    func testEncodeURLProperly() {
        engine.connectParams = [
            "created": "2016-05-04T18:31:15+0200"
        ]

        XCTAssertEqual(engine.urlPolling.query, "transport=polling&b64=1&created=2016-05-04T18%3A31%3A15%2B0200&EIO=4")
        XCTAssertEqual(engine.urlWebSocket.query, "transport=websocket&created=2016-05-04T18%3A31%3A15%2B0200&EIO=4")

        engine.connectParams = [
            "forbidden": "!*'();:@&=+$,/?%#[]\" {}^|"
        ]

        XCTAssertEqual(engine.urlPolling.query, "transport=polling&b64=1&forbidden=%21%2A%27%28%29%3B%3A%40%26%3D%2B%24%2C%2F%3F%25%23%5B%5D%22%20%7B%7D%5E%7C&EIO=4")
        XCTAssertEqual(engine.urlWebSocket.query, "transport=websocket&forbidden=%21%2A%27%28%29%3B%3A%40%26%3D%2B%24%2C%2F%3F%25%23%5B%5D%22%20%7B%7D%5E%7C&EIO=4")
    }

    func testBase64Data() {
        let expect = expectation(description: "Engine Decodes base64 data")
        let b64String = "baGVsbG8NCg=="
        let packetString = "451-[\"test\",{\"test\":{\"_placeholder\":true,\"num\":0}}]"

        socket.on("test") {data, ack in
            if let data = data[0] as? Data, let string = String(data: data, encoding: .utf8) {
                XCTAssertEqual(string, "hello")
            }

            expect.fulfill()
        }

        engine.parseEngineMessage(packetString)
        engine.parseEngineMessage(b64String)

        waitForExpectations(timeout: 3, handler: nil)
    }

    func testSettingExtraHeadersBeforeConnectSetsEngineExtraHeaders() {
        let newValue = ["hello": "world"]

        manager.engine = engine
        manager.setTestStatus(.notConnected)
        manager.config = [.extraHeaders(["new": "value"])]
        manager.config.insert(.extraHeaders(newValue), replacing: true)

        XCTAssertEqual(2, manager.config.count)
        XCTAssertEqual(manager.engine!.extraHeaders!, newValue)

        for config in manager.config {
            switch config {
            case let .extraHeaders(headers):
                XCTAssertTrue(headers.keys.contains("hello"), "It should contain hello header key")
                XCTAssertFalse(headers.keys.contains("new"), "It should not contain old data")
            case .path:
                continue
            default:
                XCTFail("It should only have two configs")
            }
        }
    }

    func testSettingExtraHeadersAfterConnectDoesNotIgnoreChanges() {
        let newValue = ["hello": "world"]

        manager.engine = engine
        manager.setTestStatus(.connected)
        engine.setConnected(true)
        manager.config = [.extraHeaders(["new": "value"])]
        manager.config.insert(.extraHeaders(["hello": "world"]), replacing: true)

        XCTAssertEqual(2, manager.config.count)
        XCTAssertEqual(manager.engine!.extraHeaders!, newValue)
    }

    func testSettingPathAfterConnectDoesNotIgnoreChanges() {
        let newValue = "/newpath/"

        manager.engine = engine
        manager.setTestStatus(.connected)
        engine.setConnected(true)
        manager.config.insert(.path(newValue))

        XCTAssertEqual(1, manager.config.count)
        XCTAssertEqual(manager.engine!.socketPath, newValue)
    }

    func testSettingCompressAfterConnectDoesNotIgnoreChanges() {
        manager.engine = engine
        manager.setTestStatus(.connected)
        engine.setConnected(true)
        manager.config.insert(.compress)

        XCTAssertEqual(2, manager.config.count)
        XCTAssertTrue(manager.engine!.compress)
    }

    func testSettingForcePollingAfterConnectDoesNotIgnoreChanges() {
        manager.engine = engine
        manager.setTestStatus(.connected)
        engine.setConnected(true)
        manager.config.insert(.forcePolling(true))

        XCTAssertEqual(2, manager.config.count)
        XCTAssertTrue(manager.engine!.forcePolling)
    }

    func testSettingForceWebSocketsAfterConnectDoesNotIgnoreChanges() {
        manager.engine = engine
        manager.setTestStatus(.connected)
        engine.setConnected(true)
        manager.config.insert(.forceWebsockets(true))

        XCTAssertEqual(2, manager.config.count)
        XCTAssertTrue(manager.engine!.forceWebsockets)
    }

    /// Engine.IO has to pause the polling transport before it sends the upgrade
    /// packet. Sending it while a POST is still on the wire makes the server
    /// answer that late POST with HTTP 400; the client discards the error and
    /// never resends, so the payload is lost without a trace.
    func testUpgradeIsDeferredUntilPollAndPostSettled() {
        engine.setConnected(true)
        engine.setFastUpgrade(true)

        engine.waitingForPoll = true
        engine.waitingForPost = true
        XCTAssertFalse(engine.canSendUpgradePacket, "Neither poll nor post settled")

        engine.waitingForPoll = false
        XCTAssertFalse(
            engine.canSendUpgradePacket, "A POST is still on the wire; upgrading loses it")

        engine.waitingForPost = false
        XCTAssertTrue(engine.canSendUpgradePacket, "Both settled, the upgrade may proceed")

        engine.waitingForPoll = true
        XCTAssertFalse(engine.canSendUpgradePacket, "An outstanding poll still blocks the upgrade")
    }

    /// `upgradeTransport()` enables `fastUpgrade` and only then enqueues its noop.
    /// That POST can never be sent, because `doRequest` refuses to write on a
    /// transport that is upgrading. It must therefore not mark the transport as
    /// writing, or the deferred upgrade would wait for a callback that never comes
    /// and the engine would end up with no active transport at all.
    func testPendingUpgradeDoesNotMarkTheTransportAsWriting() {
        engine.setConnected(true)
        engine.setFastUpgrade(true)
        engine.waitingForPoll = false
        engine.waitingForPost = false

        engine.sendPollMessage("", withType: .noop, withData: [])

        XCTAssertFalse(engine.waitingForPost, "A POST that cannot start must not block the upgrade")
        XCTAssertTrue(engine.canSendUpgradePacket)
    }

    func testNoUpgradePacketWithoutAPendingUpgrade() {
        engine.setConnected(true)
        engine.waitingForPoll = false
        engine.waitingForPost = false

        XCTAssertFalse(
            engine.canSendUpgradePacket, "Without fastUpgrade there is nothing to upgrade")
    }

    /// engine.io v4 servers advertise a `maxPayload` in the handshake and answer
    /// a POST above it with HTTP 413, discarding every packet it carried. The
    /// batch therefore has to stop short of the limit, like `getWritablePackets()`
    /// in engine.io-client does.
    func testPostBatchStopsAtTheServersMaxPayload() {
        engine.setMaxPayload(20)
        engine.postWait = [
            (msg: "4aaaaaaaaa", completion: nil), // 10 bytes
            (msg: "4bbbbbbbbb", completion: nil), // would make 21 with the separator
            (msg: "4ccccccccc", completion: nil)
        ]

        let req = engine.createRequestForPostWithPostWait()

        XCTAssertEqual(String(data: req.httpBody!, encoding: .utf8), "4aaaaaaaaa")
        XCTAssertEqual(engine.postWait.count, 2, "Packets that did not fit stay queued for the next POST")
    }

    func testPostBatchFillsUpToTheLimitExactly() {
        engine.setMaxPayload(21)
        engine.postWait = [
            (msg: "4aaaaaaaaa", completion: nil),
            (msg: "4bbbbbbbbb", completion: nil),
            (msg: "4ccccccccc", completion: nil)
        ]

        let req = engine.createRequestForPostWithPostWait()

        XCTAssertEqual(req.httpBody!.count, 21, "A payload of exactly maxPayload is still allowed")
        XCTAssertEqual(engine.postWait.count, 1)
    }

    /// A packet cannot be split, so the reference client sends it alone and lets
    /// the server reject it, rather than stalling the queue forever.
    func testAPacketLargerThanMaxPayloadIsStillSentOnItsOwn() {
        engine.setMaxPayload(5)
        engine.postWait = [
            (msg: "4aaaaaaaaa", completion: nil),
            (msg: "4b", completion: nil)
        ]

        let req = engine.createRequestForPostWithPostWait()

        XCTAssertEqual(String(data: req.httpBody!, encoding: .utf8), "4aaaaaaaaa")
        XCTAssertEqual(engine.postWait.count, 1)
    }

    func testMaxPayloadCountsBytesNotCharacters() {
        engine.setMaxPayload(12)
        engine.postWait = [
            (msg: "4\u{e4}\u{e4}\u{e4}\u{e4}\u{e4}", completion: nil), // 11 bytes, 6 characters
            (msg: "4b", completion: nil)
        ]

        let req = engine.createRequestForPostWithPostWait()

        XCTAssertEqual(req.httpBody!.count, 11)
        XCTAssertEqual(engine.postWait.count, 1, "Counting characters instead of bytes would have fit both")
    }

    func testWithoutAnAdvertisedMaxPayloadEverythingGoesInOneBatch() {
        XCTAssertNil(engine.maxPayload, "No handshake happened, so there is no limit to respect")
        engine.postWait = [
            (msg: "4aaaaaaaaa", completion: nil),
            (msg: "4bbbbbbbbb", completion: nil)
        ]

        let req = engine.createRequestForPostWithPostWait()

        XCTAssertEqual(req.httpBody!.count, 21)
        XCTAssertTrue(engine.postWait.isEmpty)
    }

    /// engine.io v3 has neither the handshake field nor this payload format, so
    /// the v2 path must stay exactly as it was.
    func testMaxPayloadIsIgnoredOnEngineIOV3() {
        engine.setConfigs([.version(.two)])
        engine.setMaxPayload(5)
        engine.postWait = [
            (msg: "4aaaaaaaaa", completion: nil),
            (msg: "4bbbbbbbbb", completion: nil)
        ]

        _ = engine.createRequestForPostWithPostWait()

        XCTAssertTrue(engine.postWait.isEmpty, "v2 servers advertise no limit and use a different payload format")
    }

    func testOnlyTheSentPacketsGetTheirCompletionCalled() {
        engine.setMaxPayload(20)
        var firstFired = false
        var secondFired = false
        engine.postWait = [
            (msg: "4aaaaaaaaa", completion: { firstFired = true }),
            (msg: "4bbbbbbbbb", completion: { secondFired = true })
        ]

        _ = engine.createRequestForPostWithPostWait()

        XCTAssertTrue(firstFired)
        XCTAssertFalse(secondFired, "A packet that is still queued has not been written yet")
    }

    /// A batch capped at `maxPayload` can leave packets queued. They belong to the
    /// session that was closed, and their ack ids mean nothing to the next one.
    func testANewSessionDoesNotInheritUnsentPackets() {
        engine.postWait = [(msg: "4left over from the previous session", completion: nil)]

        let reset = expectation(description: "engine reset")
        engine.connect()
        engine.engineQueue.async { reset.fulfill() }
        wait(for: [reset], timeout: 3)

        XCTAssertTrue(engine.postWait.isEmpty, "Stale packets would be sent under a sid that never issued their ack ids")
    }

    /// url.ts — "works with ipv6". A bracketed IPv6 literal has to survive URL
    /// construction; losing the brackets produces a host nothing can resolve.
    func testIpv6HostSurvivesEngineUrlConstruction() {
        let engine = SocketEngine(client: manager, url: URL(string: "http://[::1]:8080")!, options: nil)

        XCTAssertEqual(engine.urlPolling.host, "::1")
        XCTAssertEqual(engine.urlPolling.port, 8080)
        XCTAssertEqual(engine.urlWebSocket.host, "::1")
        XCTAssertEqual(engine.urlWebSocket.scheme, "ws")
    }

    func testChangingEngineHeadersAfterInit() {
        engine.extraHeaders = ["Hello": "World"]

        let req = engine.createRequestForPostWithPostWait()

        XCTAssertEqual("World", req.allHTTPHeaderFields?["Hello"])
    }

    var manager: SocketManager!
    var socket: SocketIOClient!
    var engine: SocketEngine!

    override func setUp() {
        super.setUp()

        manager = SocketManager(socketURL: URL(string: "http://localhost")!)
        socket = manager.defaultSocket
        engine = SocketEngine(client: manager, url: URL(string: "http://localhost")!, options: nil)

        socket.setTestable()
    }
}
