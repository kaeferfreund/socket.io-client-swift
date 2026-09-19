import Foundation
import XCTest
@testable import SocketIO

final class SocketRemainingBinaryParserTest: XCTestCase {
    private func assertRoundTrip(_ items: [Any], ack: Bool = false) throws {
        let safe = try SocketPacket.jsonSafeEmitData(items, allowBinary: true)
        let packet = SocketPacket.packetFromEmit(safe, id: 0, nsp: "/binary", ack: ack)
        XCTAssertEqual(packet.type, ack ? .binaryAck : .binaryEvent)
        let manager = SocketManager(socketURL: URL(string: "http://localhost")!, config: [.log(false)])
        var decoded = try XCTUnwrap(manager.parseSocketMessage(packet.encodedPacketString()))
        for attachment in packet.binary { _ = decoded.addData(attachment) }
        XCTAssertFalse(decoded.reconstructionFailed)
        XCTAssertEqual(decoded.id, 0); XCTAssertEqual(decoded.nsp, "/binary")
        XCTAssertTrue((decoded.data as NSArray).isEqual(to: items))
    }
    func testArrayBufferEquivalentHasExactWireAndAttachment() throws {
        let bytes = Data([0, 1, 2, 3, 4])
        let packet = SocketPacket.packetFromEmit(["hello", bytes], id: 0, nsp: "/binary", ack: false)
        XCTAssertEqual(try packet.encodedPacketString(), "51-/binary,0[\"hello\",{\"_placeholder\":true,\"num\":0}]")
        XCTAssertEqual(packet.binary, [bytes])
        try assertRoundTrip(["hello", bytes])
    }
    func testTypedArrayEquivalentEncodesOnlySelectedBytes() throws {
        let source = Data([99, 0, 1, 2, 3, 4, 88])
        let slice = source.subdata(in: 1..<6)
        let packet = SocketPacket.packetFromEmit(["slice", slice], id: 0, nsp: "/binary", ack: false)
        XCTAssertEqual(packet.binary, [Data([0, 1, 2, 3, 4])])
        XCTAssertEqual(source, Data([99, 0, 1, 2, 3, 4, 88]))
        try assertRoundTrip(["slice", slice])
    }
    func testNativeDictionaryHasNoPrototypeAndPreservesSpecialKeys() throws {
        try assertRoundTrip(["dictionary", ["__proto__": Data([1]), "constructor": "value"] as [String: Any]])
    }
    func testBlobEquivalentPreservesEmptyAndNonemptyData() throws {
        for data in [Data(), Data([0, 1, 127, 128, 255])] { try assertRoundTrip(["blob", data]) }
    }
    func testBlobEquivalentDeepInJSON() throws {
        try assertRoundTrip(["deep", ["a": [NSNull(), ["b": Data([1, 2, 3])]]]])
    }
    func testBinaryAckBlobEquivalent() throws { try assertRoundTrip([Data([0, 1, 2, 3, 4])], ack: true) }
    func testPublicPacketTypesMatchWireNumbers() {
        let types: [SocketPacket.PacketType] = [.connect, .disconnect, .event, .ack, .error, .binaryEvent, .binaryAck]
        XCTAssertEqual(types.map { $0.rawValue }, Array(0...6))
    }
}
