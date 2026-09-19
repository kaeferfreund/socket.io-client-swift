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
