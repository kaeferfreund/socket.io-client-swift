//
//  SocketEnginePacketCodecTest.swift
//  Socket.IO-Client-Swift
//
//  Round 2 of the JavaScript-parity port: `engine.io-parser/test/index.ts` and
//  `test/node.ts`.
//
//  This client has no standalone engine.io codec: encoding lives in
//  `SocketEngine.sendWebSocketMessage` / `SocketEnginePollable` (the
//  `"<type><payload>"` frame, the `\u{1e}` payload joiner and
//  `createBinaryDataForSend`), and decoding in `parseEngineMessage` /
//  `parsePollingMessage` / `parseEngineData`, which dispatch as they decode.
//  The assertions below are therefore on the wire strings and on what the
//  engine hands its client — `decodePacket`/`encodePacket`'s observable
//  contract — rather than on a parser object that does not exist here.
//

import Foundation
import XCTest
@testable import SocketIO

/// Captures everything the engine hands up.
private final class EngineCodecClient: NSObject, SocketEngineClient {
    var errors = [String]()
    var closes = [String]()
    var opens = 0
    var messages = [String]()
    var binary = [Data]()
    var deliveries = [String]()
    var pings = 0
    var pongs = 0

    func engineDidError(reason: String) { errors.append(reason) }
    func engineDidClose(reason: String) { closes.append(reason) }
    func engineDidOpen(reason: String) { opens += 1 }
    func engineDidReceivePing() { pings += 1 }
    func engineDidReceivePong() { pongs += 1 }
    func engineDidSendPong() { pongs += 1 }
    func parseEngineMessage(_ msg: String) { messages.append(msg); deliveries.append("text:" + msg) }
    func parseEngineBinaryData(_ data: Data) { binary.append(data); deliveries.append("binary:" + data.base64EncodedString()) }
    func engineDidWebsocketUpgrade(headers: [String: String]) {}
}

final class SocketEnginePacketCodecTest: XCTestCase {
    private var client: EngineCodecClient!
    private var engine: SocketEngine!

    override func setUp() {
        super.setUp()

        client = EngineCodecClient()
        engine = SocketEngine(client: client, url: URL(string: "http://localhost/")!, config: [.log(false)])
    }

    override func tearDown() {
        engine = nil
        client = nil
        super.tearDown()
    }

    private func settle() {
        engine.engineQueue.sync { /* barrier */ }
    }

    /// The body a polling POST carries for `messages`.
    private func postBody(_ messages: [String]) -> String {
        return String(decoding: engine.createRequestForPost(with: messages).httpBody ?? Data(), as: UTF8.self)
    }

    // MARK: engine.io-parser/test/index.ts > single packet — "should encode/decode a string"

    /// `encodePacket({type:"message", data:"test"})` is `"4test"`, and decoding
    /// it yields the same packet — here: the engine hands `"test"` to its client.
    func testEncodeDecodeAString() {
        let encoded = engine.engineQueue.sync {
            engine.waitingForPost = true
            engine.sendPollMessage("test", withType: .message, withData: [], completion: nil)
            return engine.postWait.map { $0.msg }
        }
        XCTAssertEqual(encoded, ["4test"])
        XCTAssertEqual(postBody(encoded), "4test")

        engine.parseEngineMessage("4test")
        settle()

        XCTAssertEqual(client.messages, ["test"])
        XCTAssertTrue(client.errors.isEmpty)
    }

    // MARK: engine.io-parser/test/index.ts > single packet — "should fail to decode a malformed packet"

    /// JS turns `""` and `"a123"` into `{type:"error", data:"parser error"}`,
    /// which `_onPacket` routes through `_onError` → `_onClose`.
    func testFailToDecodeAMalformedPacket() {
        for malformed in ["", "a123"] {
            let client = EngineCodecClient()
            let engine = SocketEngine(client: client, url: URL(string: "http://localhost/")!, config: [.log(false)])

            engine.parseEngineMessage(malformed)
            engine.engineQueue.sync { }

            XCTAssertEqual(client.errors, ["parser error"], malformed.debugDescription)
            XCTAssertTrue(client.messages.isEmpty)
            engine.engineQueue.sync { XCTAssertTrue(engine.closed, "\(malformed.debugDescription) must close the engine") }
        }
    }

    func testMalformedPollingPayloadReportsParserErrorAndCloses() {
        for malformed in ["{", "{}", "[\"a123\", \"a456\"]", ""] {
            let client = EngineCodecClient()
            let engine = SocketEngine(client: client, url: URL(string: "http://localhost")!, config: [])
            engine.engineQueue.sync { engine.parsePollingMessage(malformed) }
            engine.engineQueue.sync {
                XCTAssertEqual(client.errors, ["parser error"], malformed.debugDescription)
                XCTAssertTrue(engine.closed)
                XCTAssertEqual(client.closes, ["transport error"])
                XCTAssertTrue(client.deliveries.isEmpty)
            }
        }
    }

    func testEnginePacketTypeRequiresAnASCIIDigit() {
        for malformed in ["٤test", "４test", "²test"] {
            let client = EngineCodecClient()
            let engine = SocketEngine(client: client, url: URL(string: "http://localhost")!, config: [])
            engine.engineQueue.sync { engine.parseEngineMessage(malformed) }
            engine.engineQueue.sync {
                XCTAssertEqual(client.errors, ["parser error"])
                XCTAssertTrue(client.deliveries.isEmpty)
                XCTAssertTrue(engine.closed)
            }
        }
    }

    func testEngineMessagePreservesCombiningScalarAfterTypeDigit() {
        engine.engineQueue.sync { engine.parseEngineMessage("4\u{0301}test") }
        XCTAssertEqual(client.messages, ["\u{0301}test"])
    }

    // MARK: engine.io-parser/test/index.ts > payload — "should encode/decode all packet types"

    /// `encodePayload([open, close, ping "probe", pong "probe", message "test"])`
    /// is `"0\x1e1\x1e2probe\x1e3probe\x1e4test"`.
    func testEncodeAllPacketTypesIntoOnePayload() {
        let encoded = engine.engineQueue.sync {
            engine.waitingForPost = true
            for (type, payload): (SocketEnginePacketType, String) in
                [(.open, ""), (.close, ""), (.ping, "probe"), (.pong, "probe"), (.message, "test")] {
                engine.sendPollMessage(payload, withType: type, withData: [], completion: nil)
            }
            return engine.postWait.map { $0.msg }
        }
        XCTAssertEqual(postBody(encoded), "0\u{1e}1\u{1e}2probe\u{1e}3probe\u{1e}4test")
    }

    /// The decode half. Swift decodes and dispatches in one pass, so a CLOSE in
    /// the middle of a payload ends the session and the packets after it are
    /// not delivered — that is the transport's contract, not the parser's.
    /// Splitting and per-type handling are asserted without it.
    func testDecodeEveryPacketTypeOfAPayload() {
        engine.parsePollingMessage("2probe\u{1e}3probe\u{1e}4test")
        settle()

        XCTAssertEqual(client.messages, ["test"])
        XCTAssertTrue(client.errors.isEmpty)

        engine.parseEngineMessage("1")
        settle()

        XCTAssertEqual(client.closes, ["transport close"])
    }

    /// A CLOSE inside a payload stops the rest of it.
    func testCloseInsideAPayloadEndsTheSession() {
        engine.parsePollingMessage("1\u{1e}4test")
        settle()

        XCTAssertEqual(client.closes, ["transport close"])
        XCTAssertTrue(client.messages.isEmpty, "Nothing after the CLOSE may still be delivered")
    }

    // MARK: engine.io-parser/test/node.ts > single packet — "should encode/decode a Buffer"

    /// With `supportsBinary` (this client's WebSocket transport) a Buffer is
    /// sent as-is — `encodePacket` is a no-op — and decoding gives it back.
    func testEncodeDecodeABuffer() {
        let payload = Data([1, 2, 3, 4])
        let websocket = MockEngine()
        websocket.polling = false

        guard case let .left(encoded) = websocket.createBinaryDataForSend(using: payload) else {
            return XCTFail("A WebSocket transport sends binary without a prefix")
        }
        XCTAssertEqual(encoded, payload)

        engine.parseEngineData(payload)
        settle()

        XCTAssertEqual(client.binary, [payload])
    }

    // MARK: engine.io-parser/test/node.ts > single packet — "should encode/decode a Buffer as base64"

    /// Without binary support (HTTP long-polling) `encodePacket` produces
    /// `"b" + base64`, and `decodePacket` reads it back.
    func testEncodeDecodeABufferAsBase64() {
        let payload = Data([1, 2, 3, 4])
        let polling = MockEngine()
        polling.polling = true

        guard case let .right(encoded) = polling.createBinaryDataForSend(using: payload) else {
            return XCTFail("A polling transport base64-encodes binary")
        }
        XCTAssertEqual(encoded, "bAQIDBA==")

        engine.parseEngineMessage("bAQIDBA==")
        settle()

        XCTAssertEqual(client.binary, [payload])
    }

    // MARK: engine.io-parser/test/node.ts > single packet — "should decode an ArrayBuffer as ArrayBuffer"

    /// JS can ask its decoder for an `ArrayBuffer`; this client has exactly one
    /// binary representation, `Data`, so the contract is that the bytes arrive
    /// unchanged and are not reinterpreted as a text frame.
    func testDecodeBinaryAsData() {
        let payload = Data([1, 2, 3, 4])

        engine.parseEngineData(payload)
        settle()

        XCTAssertEqual(client.binary, [payload])
        XCTAssertTrue(client.messages.isEmpty)
    }

    // MARK: engine.io-parser/test/node.ts > payload — "should encode/decode a string + Buffer payload"

    /// `encodePayload([message "test", message <Buffer 01 02 03 04>])` is
    /// `"4test\x1ebAQIDBA=="`.
    func testEncodeDecodeAStringPlusBufferPayload() {
        let payload = Data([1, 2, 3, 4])
        let encoded = engine.engineQueue.sync {
            engine.waitingForPost = true
            engine.sendPollMessage("test", withType: .message, withData: [payload], completion: nil)
            return engine.postWait.map { $0.msg }
        }
        XCTAssertEqual(postBody(encoded), "4test\u{1e}bAQIDBA==")

        engine.parsePollingMessage("4test\u{1e}bAQIDBA==")
        settle()

        XCTAssertEqual(client.messages, ["test"])
        XCTAssertEqual(client.binary, [payload])
        XCTAssertEqual(client.deliveries, ["text:test", "binary:AQIDBA=="])
    }
}
