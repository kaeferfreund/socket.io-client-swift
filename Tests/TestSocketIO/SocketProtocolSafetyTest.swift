import Foundation
import XCTest
@testable import SocketIO

/// Malformed-peer regressions. Each input used to reach an unchecked index/cast,
/// or could retain an unbounded/incoherent binary reconstruction.
final class SocketProtocolSafetyTest: XCTestCase {
    private func parser(_ options: SocketParserOptions = SocketParserOptions()) -> SocketManager {
        SocketManager(socketURL: URL(string: "http://localhost")!, config: [.log(false), .parserOptions(options)])
    }

    func testTruncatedAndOverflowingHeadersAreRejectedWithoutTrapping() {
        let manager = parser()
        for input in ["", "2", "3", "5", "6", "2123", "51-", "51", "5-", "5x-[\"x\"]",
                      "50-[\"x\"]", "511-[\"x\"]", "299999999999999999999999999[\"x\"]",
                      "2/namespace,", "2[]", "2{}", "2[true]", "2[null]", "3{}", "1[]", "8"] {
            XCTAssertThrowsError(try manager.parseString(input), input)
        }
    }

    func testAllProtocolReservedNamesAreRejectedAsIncomingEvents() {
        let manager = parser()
        for name in ["connect", "connect_error", "disconnect", "disconnecting", "newListener", "removeListener"] {
            XCTAssertThrowsError(try manager.parseString("2[\"\(name)\"]"), name)
        }
    }

    func testInvalidBinaryPlaceholderIndicesFailAtTheHeader() {
        let manager = parser()
        for index in ["-1", "1", "99", "true", "0.5", "1e300", "\"0\"", "null"] {
            XCTAssertThrowsError(try manager.parseString("51-[\"x\",{\"_placeholder\":true,\"num\":\(index)}]"), index)
        }
        XCTAssertThrowsError(try manager.parseString("51-[\"x\",{\"_placeholder\":true}]"))
    }

    func testUnicodeNamespaceAckAndNestedBinaryRoundTrip() throws {
        let manager = parser()
        var packet = try manager.parseString("52-/é🦧,123[\"x\",{\"nested\":[{\"_placeholder\":true,\"num\":1}]},{\"_placeholder\":true,\"num\":0}]")
        XCTAssertEqual(packet.nsp, "/é🦧")
        XCTAssertEqual(packet.id, 123)
        XCTAssertFalse(packet.addData(Data([1])))
        XCTAssertTrue(packet.addData(Data([2, 3])))
        XCTAssertEqual(packet.args.last as? Data, Data([1]))
        let nested = try XCTUnwrap(packet.args.first as? [String: [Data]])
        XCTAssertEqual(nested["nested"], [Data([2, 3])])
    }

    func testJSONNestingAndTextByteLimitsIncludingEscapedQuotes() throws {
        let manager = parser(SocketParserOptions(maximumTextPacketBytes: 64, maximumNestingDepth: 3))
        XCTAssertNotNil(try manager.parseString("2[\"x\",{\"v\":[1]}]"))
        XCTAssertNotNil(try manager.parseString("2[\"x\",\"[[[\\\"\"]"))
        XCTAssertThrowsError(try manager.parseString("2[\"x\",{\"v\":[[1]]}]"))
        XCTAssertThrowsError(try manager.parseString("2[\"x\",\"" + String(repeating: "ä", count: 40) + "\"]"))
    }

    func testModernConnectErrorPayloadAndLegacyCompatibility() throws {
        let manager = parser()
        XCTAssertNotNil(try manager.parseString("4{\"message\":\"denied\",\"data\":{\"code\":3}}"))
        XCTAssertNotNil(try manager.parseString("4\"denied\""))
        XCTAssertThrowsError(try manager.parseString("41"))
        XCTAssertThrowsError(try manager.parseString("4[1,\"denied\"]"))
        manager.setConfigs([.version(.two)])
        XCTAssertEqual(try manager.parseString("41").data.first as? Int, 1)
    }

    func testAckZeroNumericEventsAndEmptyAckArray() throws {
        let manager = parser()
        XCTAssertEqual(try manager.parseString("20[\"x\"]").id, 0)
        XCTAssertEqual(try manager.parseString("2[123,\"x\"]").event, "123")
        XCTAssertTrue(try manager.parseString("30[]").data.isEmpty)
    }

    func testLowLevelPacketAlsoRejectsMalformedPlaceholderWithoutTrapping() {
        var packet = SocketPacket(type: .binaryEvent,
            data: ["x", ["_placeholder": true, "num": -1] as [String: Any]], nsp: "/", placeholders: 1)
        XCTAssertFalse(packet.addData(Data([1])))
        XCTAssertTrue(packet.reconstructionFailed)
        XCTAssertEqual(SocketPacket(type: .event, nsp: "/").event, "")
    }

    func testBinaryPacketBudgetIsAggregateAndReleasesOnFailure() throws {
        let manager = parser(SocketParserOptions(maximumBinaryPacketBytes: 3))
        manager.waitingPackets = [try manager.parseString("52-[\"x\",{\"_placeholder\":true,\"num\":0},{\"_placeholder\":true,\"num\":1}]")]
        XCTAssertNil(manager.parseBinaryData(Data([1, 2])))
        XCTAssertEqual(manager.waitingPackets.count, 1)
        XCTAssertNil(manager.parseBinaryData(Data([3, 4])))
        XCTAssertTrue(manager.waitingPackets.isEmpty)
    }

    func testAttachmentLimitCanBeConfiguredWithoutDisablingValidation() throws {
        let manager = parser(SocketParserOptions(maximumAttachments: 12))
        XCTAssertNotNil(try manager.parseString("512-[\"x\"]"))
        XCTAssertThrowsError(try manager.parseString("513-[\"x\"]"))
        XCTAssertFalse(SocketParserOptions(maximumAttachments: 0).isValid)
        XCTAssertFalse(SocketParserOptions(maximumNestingDepth: 513).isValid)
    }

    func testUTF16ReaderRejectsNegativeOversizedAndSplitSurrogateReads() {
        for count in [-1, Int.max, 1] {
            var reader = SocketStringReader(message: "🦧")
            XCTAssertNil(reader.readSafely(count: count))
            XCTAssertFalse(reader.hasNext)
        }
        var reader = SocketStringReader(message: "🦧é")
        XCTAssertEqual(reader.readSafely(count: 2), "🦧")
        XCTAssertEqual(reader.readSafely(count: 1), "é")
        XCTAssertEqual(reader.currentCharacter, "")
    }

    func testTextCannotInterleaveBinaryAndFailureIsTerminalUntilReconnect() {
        let manager = parser()
        let engine = ReviewParseEngine(client: manager, url: manager.socketURL, options: nil)
        manager.engine = engine
        manager.setTestStatus(.connected)
        let socket = manager.defaultSocket
        socket.setTestStatus(.connected)
        var events = 0
        socket.on("x") { _, _ in events += 1 }
        manager.parseEngineMessage("51-[\"x\",{\"_placeholder\":true,\"num\":0}]")
        manager.parseEngineMessage("2[\"x\"]")
        manager.parseEngineBinaryData(Data([1]))
        manager.parseEngineMessage("2[\"x\"]")
        let finished = expectation(description: "queued parser operations finished")
        manager.handleQueue.async { finished.fulfill() }
        wait(for: [finished], timeout: 3)
        XCTAssertEqual(engine.reasons, ["parse error"])
        XCTAssertTrue(manager.waitingPackets.isEmpty)
        XCTAssertEqual(events, 0)
    }

    func testTwoBinaryHeadersAndEmptyEngineMessageAreFatal() {
        for second in ["51-[\"x\"]", ""] {
            let manager = parser()
            let engine = ReviewParseEngine(client: manager, url: manager.socketURL, options: nil)
            manager.engine = engine
            manager.setTestStatus(.connected)
            manager.parseEngineMessage("51-[\"x\"]")
            manager.parseEngineMessage(second)
            let finished = expectation(description: "second header processed")
            manager.handleQueue.async { finished.fulfill() }
            wait(for: [finished], timeout: 3)
            XCTAssertEqual(engine.reasons, ["parse error"])
        }
    }
}

/// Deliberately delays engineDidClose so the parser's own terminal fence is tested.
private final class ReviewParseEngine: TestEngine {
    var reasons = [String]()
    override func disconnect(reason: String) { reasons.append(reason) }
}
