import Foundation
import Security
import XCTest
@testable import SocketIO

internal enum NativeTLSFixtures {
    private static let generated: Result<URL, Error> = Result {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("socketio-native-tls-" + UUID().uuidString)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", TestServerProcess.fixturesDir()
            .appendingPathComponent("generate-native-tls.mjs").path, directory.path]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "NativeTLSFixtures", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        return directory
    }
    static func directory() throws -> URL { try generated.get() }
    static func certificate(_ name: String) throws -> Data {
        try Data(contentsOf: directory().appendingPathComponent("\(name).der"))
    }
    static func trust(_ name: String = "leaf") throws -> SecTrust {
        let leaf = try XCTUnwrap(SecCertificateCreateWithData(nil, certificate(name) as CFData))
        let ca = try XCTUnwrap(SecCertificateCreateWithData(nil, certificate("ca") as CFData))
        var trust: SecTrust?
        XCTAssertEqual(SecTrustCreateWithCertificates([leaf, ca] as CFArray,
            SecPolicyCreateSSL(true, "localhost" as CFString), &trust), errSecSuccess)
        let result = try XCTUnwrap(trust)
        SecTrustSetNetworkFetchAllowed(result, false)
        return result
    }
    static func policy(pinned: Bool = true) throws -> SocketTLSConfiguration {
        .customTrust(anchors: [try certificate("ca")], pins: pinned ? [try certificate("leaf")] : [])
    }
}

final class SocketNativeTLSConfigurationTest: XCTestCase {
    func testRedirectCannotDowngradeAfterAnInitiallyInsecureHop() {
        let proxy = SocketSessionDelegateProxy(tlsConfiguration: .systemDefault, forwardingDelegate: nil)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "http://example.test/start")!)
        let response = HTTPURLResponse(url: URL(string: "https://example.test/secure")!, statusCode: 302,
                                       httpVersion: nil, headerFields: nil)!
        var calls = 0
        proxy.urlSession(session, task: task, willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: "http://example.test/downgrade")!)) { request in
            XCTAssertNil(request); calls += 1
        }
        XCTAssertEqual(calls, 1)
    }

    func testExplicitAnchorAndMatchingLeafAcceptValidLocalhost() throws {
        XCTAssertTrue(SocketServerTrustEvaluator.evaluate(try NativeTLSFixtures.trust(), host: "localhost",
                                                         configuration: try NativeTLSFixtures.policy()))
    }
    func testExplicitAnchorWithoutPinStillValidatesTrust() throws {
        XCTAssertTrue(SocketServerTrustEvaluator.evaluate(try NativeTLSFixtures.trust(), host: "localhost",
                                                         configuration: try NativeTLSFixtures.policy(pinned: false)))
    }
    func testWrongHostnameIsRejectedEvenWithMatchingPin() throws {
        XCTAssertFalse(SocketServerTrustEvaluator.evaluate(try NativeTLSFixtures.trust(), host: "wrong.example",
                                                          configuration: try NativeTLSFixtures.policy()))
    }
    func testExpiredCertificateIsRejected() throws {
        XCTAssertFalse(SocketServerTrustEvaluator.evaluate(try NativeTLSFixtures.trust("expired"), host: "localhost",
                                                          configuration: try NativeTLSFixtures.policy(pinned: false)))
    }
    func testWrongLeafPinIsRejected() throws {
        let policy = SocketTLSConfiguration.customTrust(anchors: [try NativeTLSFixtures.certificate("ca")],
                                                        pins: [try NativeTLSFixtures.certificate("expired")])
        XCTAssertFalse(SocketServerTrustEvaluator.evaluate(try NativeTLSFixtures.trust(), host: "localhost", configuration: policy))
    }
    func testPinDoesNotMakeAnUntrustedCAValid() throws {
        let policy = SocketTLSConfiguration.certificatePinning([try NativeTLSFixtures.certificate("leaf")])
        XCTAssertFalse(SocketServerTrustEvaluator.evaluate(try NativeTLSFixtures.trust(), host: "localhost", configuration: policy))
    }
    func testMalformedOrEmptyPoliciesAreRejected() {
        XCTAssertNotNil(SocketTLSConfiguration.certificatePinning([]).validationError)
        XCTAssertNotNil(SocketTLSConfiguration.certificatePinning([Data([1, 2])]).validationError)
        XCTAssertNotNil(SocketTLSConfiguration.customTrust(anchors: [], pins: []).validationError)
        XCTAssertNil(SocketTLSConfiguration.systemDefault.validationError)
    }
    func testForwardedAuthenticationCompletionIsOnceOnly() {
        let delegate = DoubleCompletingAuthDelegate()
        let proxy = SocketSessionDelegateProxy(tlsConfiguration: .systemDefault, forwardingDelegate: delegate)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let space = URLProtectionSpace(host: "localhost", port: 80, protocol: "http", realm: "test",
                                       authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil,
            previousFailureCount: 0, failureResponse: nil, error: nil, sender: NativeChallengeSender())
        var count = 0
        proxy.urlSession(session, didReceive: challenge) { disposition, _ in
            XCTAssertEqual(disposition, .performDefaultHandling)
            count += 1
        }
        XCTAssertEqual(delegate.calls, 1)
        XCTAssertEqual(count, 1)
    }
    func testInvalidationPreservesInternalAndExternalCallbacks() {
        let delegate = DoubleCompletingAuthDelegate()
        let proxy = SocketSessionDelegateProxy(tlsConfiguration: .systemDefault, forwardingDelegate: delegate)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var internalCalls = 0
        proxy.onInvalidation = { _, _ in internalCalls += 1 }
        proxy.urlSession(session, didBecomeInvalidWithError: nil)
        XCTAssertEqual(internalCalls, 1)
        XCTAssertEqual(delegate.invalidations, 1)
    }
}

private final class DoubleCompletingAuthDelegate: NSObject, URLSessionDelegate {
    var calls = 0
    var invalidations = 0
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        calls += 1
        completionHandler(.performDefaultHandling, nil)
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) { invalidations += 1 }
}
private final class NativeChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}

extension SocketNativeTLSConfigurationTest {
    func testMissingAuthenticationHandlersDefaultExactlyOnceAtBothDelegateLevels() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "http://example.test")!)
        let space = URLProtectionSpace(host: "example.test", port: 80, protocol: "http", realm: "test",
                                       authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil,
            previousFailureCount: 0, failureResponse: nil, error: nil, sender: NativeChallengeSender())
        let proxy = SocketSessionDelegateProxy(tlsConfiguration: .systemDefault, forwardingDelegate: nil)
        var sessionCalls = 0
        var taskCalls = 0
        proxy.urlSession(session, didReceive: challenge) { disposition, credential in
            XCTAssertEqual(disposition, .performDefaultHandling)
            XCTAssertNil(credential)
            sessionCalls += 1
        }
        proxy.urlSession(session, task: task, didReceive: challenge) { disposition, credential in
            XCTAssertEqual(disposition, .performDefaultHandling)
            XCTAssertNil(credential)
            taskCalls += 1
        }
        XCTAssertEqual(sessionCalls, 1)
        XCTAssertEqual(taskCalls, 1)
    }

    func testTaskAuthenticationForwardsCredentialsButCompletesOnlyOnce() {
        let delegate = RepeatedTaskCompletionDelegate(redirect: nil)
        let proxy = SocketSessionDelegateProxy(tlsConfiguration: .systemDefault, forwardingDelegate: delegate)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "http://example.test")!)
        let space = URLProtectionSpace(host: "example.test", port: 80, protocol: "http", realm: "test",
                                       authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil,
            previousFailureCount: 0, failureResponse: nil, error: nil, sender: NativeChallengeSender())
        var calls = 0
        proxy.urlSession(session, task: task, didReceive: challenge) { disposition, credential in
            XCTAssertEqual(disposition, .useCredential)
            XCTAssertEqual(credential?.user, "user")
            XCTAssertEqual(credential?.password, "password")
            calls += 1
        }
        XCTAssertEqual(calls, 1)
    }

    func testRedirectDelegateCannotOverrideSecureOriginOrCompleteTwice() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://example.test/start")!)
        let response = HTTPURLResponse(url: task.originalRequest!.url!, statusCode: 302,
                                       httpVersion: nil, headerFields: nil)!
        for destination in [nil, "http://example.test/insecure", "https://example.test/allowed"] as [String?] {
            let candidate = destination.map { URLRequest(url: URL(string: $0)!) }
            let delegate = RepeatedTaskCompletionDelegate(redirect: candidate)
            let proxy = SocketSessionDelegateProxy(tlsConfiguration: .systemDefault, forwardingDelegate: delegate)
            var calls = 0
            proxy.urlSession(session, task: task, willPerformHTTPRedirection: response,
                             newRequest: URLRequest(url: URL(string: "https://example.test/proposed")!)) { request in
                calls += 1
                XCTAssertEqual(request?.url?.absoluteString,
                               destination?.hasPrefix("https:") == true ? destination : nil)
            }
            XCTAssertEqual(calls, 1)
        }
    }
}

private final class RepeatedTaskCompletionDelegate: NSObject, URLSessionTaskDelegate {
    let redirect: URLRequest?
    init(redirect: URLRequest?) { self.redirect = redirect }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.useCredential, URLCredential(user: "user", password: "password", persistence: .none))
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(redirect)
        completionHandler(request)
    }
}
