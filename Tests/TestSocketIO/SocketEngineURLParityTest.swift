import XCTest
@testable import SocketIO

/// Native absolute-URL equivalents of engine.io-client URI construction.
/// Relative/browser location inference is deliberately not claimed here.
final class SocketEngineURLParityTest: XCTestCase {
    // SocketEngine keeps its client weakly; retain the owner while rebuilding URLs.
    private var manager: SocketManager?

    override func tearDown() {
        manager = nil
        super.tearDown()
    }
    private func engine(_ url: String, _ options: SocketIOClientOption...) -> SocketEngine {
        let url = URL(string: url)!
        var config: SocketIOClientConfiguration = [.log(false), .autoConnect(false)]
        for option in options { config.insert(option) }
        let manager = SocketManager(socketURL: url, config: config)
        self.manager = manager
        return SocketEngine(client: manager, url: url, config: config)
    }

    private func assertURI(_ input: String, secure: Bool, port: Int? = nil,
                           host: String = "localhost", file: StaticString = #filePath, line: UInt = #line) {
        let engine = self.engine(input)
        let polling = URLComponents(url: engine.urlPolling, resolvingAgainstBaseURL: false)!
        let websocket = URLComponents(url: engine.urlWebSocket, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(polling.scheme, secure ? "https" : "http", file: file, line: line)
        XCTAssertEqual(websocket.scheme, secure ? "wss" : "ws", file: file, line: line)
        XCTAssertEqual(polling.host, host, file: file, line: line)
        XCTAssertEqual(websocket.host, host, file: file, line: line)
        XCTAssertEqual(polling.port, port, file: file, line: line)
        XCTAssertEqual(websocket.port, port, file: file, line: line)
        XCTAssertEqual(polling.path, "/engine.io/", file: file, line: line)
        XCTAssertEqual(websocket.path, "/engine.io/", file: file, line: line)
        XCTAssertEqual(polling.query, "transport=polling&b64=1&EIO=4", file: file, line: line)
        XCTAssertEqual(websocket.query, "transport=websocket&EIO=4", file: file, line: line)
    }

    func testHTTPWithoutPort() { assertURI("http://localhost", secure: false) }
    func testHTTPWithPort() { assertURI("http://localhost:8080", secure: false, port: 8080) }
    func testHTTPSWithoutPort() { assertURI("https://localhost", secure: true) }
    func testHTTPSWithPort() { assertURI("https://localhost:8443", secure: true, port: 8443) }
    func testWSWithoutPort() { assertURI("ws://localhost", secure: false) }
    func testWSSWithoutPort() { assertURI("wss://localhost", secure: true) }
    func testWSSWithPort() { assertURI("wss://localhost:8443", secure: true, port: 8443) }
    func testIPv6WithoutPort() { assertURI("http://[::1]", secure: false, host: "[::1]") }
    func testIPv6WithPort() { assertURI("http://[::1]:8080", secure: false, port: 8080, host: "[::1]") }
    func testWebSocketIPv6WithoutPort() { assertURI("ws://[::1]", secure: false, host: "[::1]") }
    func testWebSocketIPv6WithPort() { assertURI("wss://[::1]:8443", secure: true, port: 8443, host: "[::1]") }

    func testConfiguredPathAppliesToBothTransports() {
        let engine = self.engine("http://localhost/ignored", .path("/custom/engine/"))
        XCTAssertEqual(engine.urlPolling.path, "/custom/engine")
        XCTAssertEqual(engine.urlWebSocket.path, "/custom/engine")
        XCTAssertTrue(engine.urlPolling.absoluteString.contains("/custom/engine/?"))
        XCTAssertTrue(engine.urlWebSocket.absoluteString.contains("/custom/engine/?"))
    }

    func testProtocolIsNotSuppressedByEIOInsideAValueOrAnotherName() {
        let engine = self.engine("http://localhost/?token=EIO&notEIO=1")
        XCTAssertEqual(engine.urlPolling.query, "transport=polling&b64=1&token=EIO&notEIO=1&EIO=4")
        XCTAssertEqual(engine.urlWebSocket.query, "transport=websocket&token=EIO&notEIO=1&EIO=4")
    }

    func testCallerCannotOverrideEngineOwnedQueryKeys() {
        let engine = self.engine("http://localhost/?%45IO=3&transport=bad&sid=old&b64=0&token=x")
        XCTAssertEqual(engine.urlPolling.query, "transport=polling&b64=1&token=x&EIO=4")
        XCTAssertEqual(engine.urlWebSocket.query, "transport=websocket&token=x&EIO=4")
    }

    func testExplicitParametersReplaceURLAndProtocolVersionStaysAuthoritative() {
        let engine = self.engine("https://localhost/?old=secret",
                                 .connectParams(["EIO": "wrong", "transport": "bad", "token": "a&b"]),
                                 .version(.two))
        XCTAssertEqual(engine.urlPolling.query, "transport=polling&b64=1&token=a%26b&EIO=3")
        XCTAssertEqual(engine.urlWebSocket.query, "transport=websocket&token=a%26b&EIO=3")
    }

    func testResettingExplicitQueryToNilRestoresURLQuery() {
        let engine = self.engine("http://localhost/?token=original", .connectParams([:]))
        XCTAssertEqual(engine.urlPolling.query, "transport=polling&b64=1&EIO=4")
        engine.connectParams = nil
        XCTAssertEqual(engine.urlPolling.query, "transport=polling&b64=1&token=original&EIO=4")
    }
}
