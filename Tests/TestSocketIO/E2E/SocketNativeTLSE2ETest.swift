import Foundation
import Security
import XCTest
@testable import SocketIO

final class SocketNativeTLSE2ETest: XCTestCase {
    private func roundTrip(forcePolling: Bool) throws {
        let server = try TestServerProcess.start(serverScript: "native-tls-server.mjs",
            extraEnvironment: ["NATIVE_TLS_DIR": try NativeTLSFixtures.directory().path])
        defer { server.stop() }
        let manager = SocketManager(socketURL: URL(string: "https://localhost:\(server.port)")!, config: [
            .forcePolling(forcePolling), .forceWebsockets(!forcePolling), .reconnects(false),
            .connectTimeout(5), .security(try NativeTLSFixtures.policy())
        ])
        defer { manager.disconnect() }
        let socket = manager.defaultSocket
        let echoed = expectation(description: "TLS multipart binary acknowledgement")
        socket.on(clientEvent: .connect) { _, _ in
            socket.emitWithAck("echoTwo", Data([1, 2, 3]), Data([4, 5, 6])).timingOut(after: 5) { values in
                XCTAssertEqual(values.count, 2)
                XCTAssertEqual(values.first as? Data, Data([1, 2, 3]))
                XCTAssertEqual(values.last as? Data, Data([4, 5, 6]))
                echoed.fulfill()
            }
        }
        socket.connect()
        wait(for: [echoed], timeout: 10)
    }

    func testNativeWebSocketTLSBinaryRoundTripWithPrivateCA() throws { try roundTrip(forcePolling: false) }
    func testPollingUsesTheSameTLSPolicyAndBinaryRoundTrip() throws { try roundTrip(forcePolling: true) }

    private func reject(host: String = "localhost", forcePolling: Bool = false, expired: Bool = false,
                        policy: SocketTLSConfiguration, delegate: URLSessionDelegate? = nil) throws {
        let server = try TestServerProcess.start(serverScript: expired ? "native-tls-expired.mjs" : "native-tls-server.mjs",
            extraEnvironment: ["NATIVE_TLS_DIR": try NativeTLSFixtures.directory().path])
        defer { server.stop() }
        var config: SocketIOClientConfiguration = [
            .forcePolling(forcePolling), .forceWebsockets(!forcePolling), .reconnects(false),
            .connectTimeout(5), .security(policy)
        ]
        if let delegate = delegate { config.insert(.sessionDelegate(delegate)) }
        let manager = SocketManager(socketURL: URL(string: "https://\(host):\(server.port)")!, config: config)
        defer { manager.disconnect() }
        let socket = manager.defaultSocket
        let failed = expectation(description: "TLS must be rejected")
        failed.assertForOverFulfill = false
        socket.on(clientEvent: .error) { data, _ in
            XCTAssertNotEqual(data.first as? String, "timeout", "TLS must fail explicitly, not by connection timeout")
            failed.fulfill()
        }
        socket.on(clientEvent: .connect) { _, _ in XCTFail("Invalid TLS was accepted") }
        socket.connect()
        wait(for: [failed], timeout: 7)
        XCTAssertNotEqual(socket.status, .connected)
    }

    func testSystemTrustRejectsUntrustedFixtureCA() throws { try reject(policy: .systemDefault) }
    func testRealWebSocketRejectsWrongHostname() throws { try reject(host: "127.0.0.1", policy: NativeTLSFixtures.policy()) }
    func testRealWebSocketRejectsExpiredCertificate() throws { try reject(expired: true, policy: NativeTLSFixtures.policy(pinned: false)) }
    func testRealPollingRejectsWrongPin() throws {
        try reject(forcePolling: true, policy: .customTrust(anchors: [NativeTLSFixtures.certificate("ca")],
                                                          pins: [NativeTLSFixtures.certificate("expired")]))
    }
    func testExternalTrustAllDelegateCannotOverrideNativePins() throws {
        let delegate = AttemptedTrustBypassDelegate()
        try reject(policy: .customTrust(anchors: [NativeTLSFixtures.certificate("ca")],
                                        pins: [NativeTLSFixtures.certificate("expired")]), delegate: delegate)
        XCTAssertEqual(delegate.serverTrustCalls, 0)
    }
}

private final class AttemptedTrustBypassDelegate: NSObject, URLSessionDelegate {
    var serverTrustCalls = 0
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            serverTrustCalls += 1
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else { completionHandler(.performDefaultHandling, nil) }
    }
}
