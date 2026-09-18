#!/usr/bin/env bash
# Offline crash-regression smoke test using the actual parser/packet source.
# The shims replace only manager/logging/JSON conveniences, not parsing logic.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/Shims.swift" <<'SWIFT'
import Foundation
public typealias JSON = [String: Any]
public enum SocketIOVersion { case two, three }
public protocol SocketManagerSpec: AnyObject {
    var version: SocketIOVersion { get }
    var parserOptions: SocketParserOptions { get }
}
enum DefaultSocketLogger { static let Logger = QuietLogger() }
struct QuietLogger {
    func log(_ text: String, type: String) {}
    func error(_ text: String, type: String) {}
}
extension Array { func toJSON() throws -> Data { try JSONSerialization.data(withJSONObject: self) } }
final class Parser: SocketManagerSpec, SocketDataBufferable, SocketParsable {
    let version = SocketIOVersion.three
    let parserOptions = SocketParserOptions()
    var waitingPackets = [SocketPacket]()
}
SWIFT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
let parser = Parser()
let rejected = ["", "2", "3", "5", "6", "2123", "51-", "51", "50-[\"x\"]",
    "51-[\"x\",{\"_placeholder\":true,\"num\":99}]",
    "51-[\"x\",{\"_placeholder\":true,\"num\":-1}]",
    "51-[\"x\",{\"_placeholder\":true}]", "29999999999999999999999[\"x\"]"]
for message in rejected {
    precondition((try? parser.parseString(message)) == nil, "Accepted invalid packet: \(message)")
}
let good = try parser.parseString("2/é🦧,0[\"x\"]")
precondition(good.id == 0 && good.nsp == "/é🦧")
var binary = try parser.parseString("51-[\"x\",{\"_placeholder\":true,\"num\":0}]")
precondition(binary.addData(Data([7])) && binary.args.first as? Data == Data([7]))
var state: UInt64 = 0x51234
let alphabet = Array("0123456789abcdef/-_,:\"[]{} nulltrue🦧é")
for _ in 0..<20000 {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    let size = Int((state >> 32) % 96)
    var text = ""
    for _ in 0..<size {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        text.append(alphabet[Int((state >> 32) % UInt64(alphabet.count))])
    }
    if var packet = try? parser.parseString(text) {
        _ = packet.event; _ = packet.args
        if packet.type.isBinary {
            for _ in 0..<parser.parserOptions.maximumAttachments {
                if packet.addData(Data([1])) { break }
            }
        }
    }
}
print("PASS: 13 known malformed headers rejected; Unicode/binary valid controls; 20,000 seeded malformed inputs, no crash")
SWIFT
swiftc "$TMP/Shims.swift" \
    "$ROOT/Source/SocketIO/Parse/SocketParsable.swift" \
    "$ROOT/Source/SocketIO/Parse/SocketPacket.swift" \
    "$ROOT/Source/SocketIO/Util/SocketStringReader.swift" \
    "$ROOT/Source/SocketIO/Client/SocketReservedEvent.swift" \
    "$TMP/main.swift" -o "$TMP/probe"
"$TMP/probe"
