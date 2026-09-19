import Foundation
import XCTest
@testable import SocketIO

final class SocketPacketDiagnosticsTest: XCTestCase {
    func testLocalizedEncoderErrorsRetainPathTypeOrLimit() {
        let cases: [(SocketPacketError, [String])] = [
            (.unsupportedValue(path: "$[1]", type: "Custom"), ["$[1]", "Custom"]),
            (.nonStringKey(path: "$[2]"), ["$[2]", "String"]),
            (.nestingTooDeep(path: "$[3]", limit: 7), ["$[3]", "7"]),
            (.cyclicPayload(path: "$[4]"), ["$[4]", "cyclic"]),
            (.tooManyNodes(limit: 9), ["9", "node"]),
            (.payloadTooLarge(limit: 123), ["123", "byte"]),
            (.unserializablePayload("unsupported test object"), ["unsupported test object"])
        ]
        for (error, details) in cases {
            XCTAssertEqual(error.localizedDescription, error.description)
            for detail in details { XCTAssertTrue(error.localizedDescription.contains(detail)) }
        }
    }

    func testManualPacketLegacyFallbackNeverMasqueradesAsSuccessfulEncoding() {
        let logger = CoverageRecordingLogger()
        DefaultSocketLogger.Logger = logger
        defer { DefaultSocketLogger.Logger = DefaultSocketLogger() }
        let event = SocketPacket(type: .event, data: ["event", NSObject()], nsp: "/manual")
        XCTAssertThrowsError(try event.encodedPacketString())
        XCTAssertEqual(event.packetString, "2/manual,[]")
        let connect = SocketPacket(type: .connect, data: [NSObject()], nsp: "/manual")
        XCTAssertThrowsError(try connect.encodedPacketString())
        XCTAssertEqual(connect.packetString, "0/manual,")
        XCTAssertEqual(logger.entries.count, 2)
        XCTAssertTrue(logger.entries.allSatisfy { $0.contains("encodedPacketString()") })
    }

    func testFoundationDictionaryRejectsNonStringKeysWithPayloadPath() {
        let dictionary = NSDictionary(object: "value", forKey: NSNumber(value: 42))
        XCTAssertThrowsError(try SocketPacket.jsonSafeEmitData([dictionary])) { error in
            guard case SocketPacketError.nonStringKey(let path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, "payload[0]")
        }
    }

    func testAcknowledgementArgumentsDoNotLoseTheirFirstValue() {
        let packet = SocketPacket(type: .ack, data: [42, "value"], id: 7, nsp: "/")
        XCTAssertEqual(packet.args as NSArray, [42, "value"] as NSArray)
    }

    func testNonFragmentEncodingRejectsScalarButAllowsFragmentEncoding() throws {
        XCTAssertThrowsError(try SocketPacket.jsonString(from: "scalar", fragmentsAllowed: false)) { error in
            guard case SocketPacketError.unserializablePayload = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try SocketPacket.jsonString(from: "scalar", fragmentsAllowed: true), "\"scalar\"")
    }

    func testBinaryDecoderRejectsOverlappingHeadersAndChangedLimits() throws {
        let manager = SocketManager(socketURL: URL(string: "http://localhost")!, config: [])
        let packet = try manager.parseString("51-[\"event\",{\"_placeholder\":true,\"num\":0}]")
        manager.waitingPackets = [packet, packet]
        XCTAssertNil(manager.parseBinaryData(Data([1])))
        XCTAssertTrue(manager.waitingPackets.isEmpty)
        let limited = SocketManager(socketURL: URL(string: "http://localhost")!,
                                    config: [.parserOptions(SocketParserOptions(maximumBinaryPacketBytes: 1))])
        limited.waitingPackets = [packet]
        XCTAssertNil(limited.parseBinaryData(Data([1, 2])))
        XCTAssertTrue(limited.waitingPackets.isEmpty)
    }
}
