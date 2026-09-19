import Foundation
import XCTest
@testable import SocketIO

private final class NativeEngineClient: NSObject, SocketEngineClient {
    var errors = [String]()
    var closes = [String]()
    var opens = 0
    var headers = [[String: String]]()
    var messages = [String]()
    var binary = [Data]()
    func engineDidError(reason: String) { errors.append(reason) }
    func engineDidClose(reason: String) { closes.append(reason) }
    func engineDidOpen(reason: String) { opens += 1 }
    func engineDidReceivePing() {}
    func engineDidReceivePong() {}
    func engineDidSendPing() {}
    func engineDidSendPong() {}
    func parseEngineMessage(_ msg: String) { messages.append(msg) }
    func parseEngineBinaryData(_ data: Data) { binary.append(data) }
    func engineDidWebsocketUpgrade(headers: [String: String]) { self.headers.append(headers) }
}

private final class NativeEngineTransport: EngineWebSocketTransport {
    var onEvent: ((EngineWebSocketEvent) -> Void)?
    var isWritable = true
    var batches = [[EngineWebSocketMessage]]()
    var completions = [(Result<Void, Error>) -> Void]()
    var autoComplete = true
    var aborts = 0
    var connects = 0
    func connect() { connects += 1 }
    func sendBatch(_ messages: [EngineWebSocketMessage], completion: @escaping (Result<Void, Error>) -> Void) {
        batches.append(messages)
        if autoComplete { completion(.success(())) }
        else { completions.append(completion) }
    }
    func close(code: Int, reason: Data?) {}
    func abort() { aborts += 1 }
}

private final class NativePollingTestEngine: SocketEngine {
    var polls = 0
    var pollingWrites = [String]()
    override func doPoll() { polls += 1 }
    override func sendPollMessage(_ message: String, withType type: SocketEnginePacketType,
                                  withData datas: [Data], completion: (() -> ())?) {
        pollingWrites.append(String(type.rawValue) + message)
        completion?()
    }
}

final class SocketNativeEngineTest: XCTestCase {
    private let url = URL(string: "http://localhost:1")!
    private let handshake = "0{\"sid\":\"native\",\"upgrades\":[],\"pingInterval\":25000,\"pingTimeout\":20000}"
    private let upgradeHandshake = "0{\"sid\":\"polling\",\"upgrades\":[\"websocket\"],\"pingInterval\":25000,\"pingTimeout\":20000}"

    private func drain(_ engine: SocketEngine) { engine.engineQueue.sync {}; engine.engineQueue.sync {} }
    private func make(_ options: SocketIOClientConfiguration = [.forceWebsockets(true)])
        -> (SocketEngine, NativeEngineClient, NativeEngineTransport) {
        let client = NativeEngineClient()
        let engine = SocketEngine(client: client, url: url, config: options)
        let transport = NativeEngineTransport()
        engine.webSocketTransportFactory = { _ in transport }
        engine.connect(); drain(engine)
        return (engine, client, transport)
    }
    private func open(_ engine: SocketEngine, _ transport: NativeEngineTransport) {
        transport.onEvent?(.opened(protocol: nil)); drain(engine)
        transport.onEvent?(.message(.text(handshake))); drain(engine)
    }

    func testApplicationTrafficCannotRefreshTheServerHeartbeatDeadline() {
        let (engine, client, transport) = make()
        var now = DispatchTime.now()
        engine.engineQueue.sync { engine.heartbeatNow = { now } }
        open(engine, transport) // deadline: 25 + 20 seconds
        engine.engineQueue.sync {
            now = now + .seconds(46)
            engine.parseEngineMessage("4[\"still sending data\"]")
            engine.parseEngineData(Data([1]))
            XCTAssertTrue(engine.hasPingExpired)
        }
        drain(engine)
        engine.engineQueue.sync { XCTAssertEqual(client.closes, ["ping timeout"]) }
    }

    func testOnlyPingResetsTheDeadlineAndExpiredChecksCloseOnce() {
        let (engine, client, transport) = make()
        var now = DispatchTime.now()
        engine.engineQueue.sync { engine.heartbeatNow = { now } }
        open(engine, transport)
        engine.engineQueue.sync {
            now = now + .seconds(30)
            engine.parseEngineMessage("2")
            now = now + .seconds(30)
            XCTAssertFalse(engine.hasPingExpired) // inside the reset 45-second budget
            now = now + .seconds(16)
            XCTAssertTrue(engine.hasPingExpired)
            XCTAssertTrue(engine.hasPingExpired)
        }
        drain(engine)
        engine.engineQueue.sync { XCTAssertEqual(client.closes, ["ping timeout"]) }
    }

    /// Only timers this client cannot turn into a Dispatch deadline are a
    /// transport error. `1.5` and `0` used to be listed here and have moved to
    /// the two tests below: JS opens on both, so pinning them as errors was wrong.
    func testMalformedHeartbeatIntervalsCannotTrapOrOpenEngine() {
        for timers in ["\"pingInterval\":9223372036854775807,\"pingTimeout\":1",
                       "\"pingInterval\":-1,\"pingTimeout\":1",
                       "\"pingInterval\":1,\"pingTimeout\":-1",
                       "\"pingInterval\":true,\"pingTimeout\":1",
                       "\"pingInterval\":\"25000\",\"pingTimeout\":1",
                       "\"pingInterval\":2147483647,\"pingTimeout\":2147483647"] {
            let (engine, client, transport) = make()
            transport.onEvent?(.opened(protocol: nil)); drain(engine)
            transport.onEvent?(.message(.text("0{\"sid\":\"x\",\"upgrades\":[]," + timers + "}"))); drain(engine)
            engine.engineQueue.sync { XCTAssertTrue(engine.closed, timers); XCTAssertFalse(engine.connected, timers); XCTAssertEqual(client.opens, 0, timers) }
        }
    }

    /// engine.io-client `onHandshake` stores `pingInterval`/`pingTimeout` as-is:
    /// `pingInterval: 0, pingTimeout: 20000` opens with a 20 s deadline, and
    /// fractional milliseconds are ordinary values.
    func testJavaScriptAcceptedHeartbeatTimersOpenTheEngine() {
        for timers in ["\"pingInterval\":0,\"pingTimeout\":20000",
                       "\"pingInterval\":1.5,\"pingTimeout\":1000",
                       "\"pingInterval\":25000.9,\"pingTimeout\":20000.4"] {
            let (engine, client, transport) = make()
            defer { engine.disconnect(reason: "test"); drain(engine) }
            transport.onEvent?(.opened(protocol: nil)); drain(engine)
            transport.onEvent?(.message(.text("0{\"sid\":\"x\",\"upgrades\":[]," + timers + "}"))); drain(engine)
            engine.engineQueue.sync {
                XCTAssertFalse(engine.closed, timers)
                XCTAssertTrue(engine.connected, timers)
                XCTAssertEqual(client.opens, 1, timers)
                XCTAssertEqual(client.closes, [], timers)
            }
        }
    }

    /// A handshake whose timers are zero or absent sums to a zero-length (JS:
    /// `NaN`) deadline. JS opens the socket and then closes it from the
    /// heartbeat with "ping timeout"; it is never a transport error.
    func testZeroAndMissingHeartbeatTimersOpenThenPingTimeout() {
        for handshake in ["0{\"sid\":\"x\",\"upgrades\":[],\"pingInterval\":0,\"pingTimeout\":0}",
                          "0{\"sid\":\"x\",\"upgrades\":[]}"] {
            let (engine, client, transport) = make()
            transport.onEvent?(.opened(protocol: nil)); drain(engine)
            transport.onEvent?(.message(.text(handshake))); drain(engine)
            engine.engineQueue.sync { XCTAssertEqual(client.opens, 1, handshake) }
            // The zero-length heartbeat deadline is already in the past, so one
            // later engine-queue block observes the close it scheduled.
            let expired = expectation(description: "heartbeat deadline expired")
            engine.engineQueue.asyncAfter(deadline: .now() + .milliseconds(100)) { expired.fulfill() }
            wait(for: [expired], timeout: 5)
            engine.engineQueue.sync {
                XCTAssertTrue(engine.closed, handshake)
                XCTAssertEqual(client.closes, ["ping timeout"], handshake)
                XCTAssertEqual(client.errors, [], handshake)
            }
        }
    }

    func testMalformedLegacyPollingLengthsAreRejectedWithoutTrapping() {
        for message in ["-1:x", "999999999999999999999999:x", "99:x", "1:🦧", "3:ab", "x:abc"] {
            let (engine, client, _) = make()
            engine.engineQueue.sync {
                engine.setConfigs([.version(.two)])
                engine.parsePollingMessage(message)
                XCTAssertTrue(engine.closed, message)
                XCTAssertEqual(client.errors.count, 1, message)
            }
        }
    }

    func testWebSocketOpenAloneDoesNotOpenEngineIO() {
        let (engine, client, transport) = make()
        defer { engine.disconnect(reason: "test"); drain(engine) }
        transport.onEvent?(.opened(protocol: nil, headers: ["x-native": "yes"]))
        drain(engine)
        XCTAssertFalse(engine.connected)
        XCTAssertFalse(engine.writable)
        XCTAssertEqual(client.opens, 0)
        XCTAssertEqual(client.headers, [["x-native": "yes"]])
        transport.onEvent?(.message(.text(handshake))); drain(engine)
        XCTAssertTrue(engine.connected)
        XCTAssertEqual(client.opens, 1)
    }

    func testWholeBinaryPacketHasOneDelayedCompletion() {
        let (engine, _, transport) = make(); open(engine, transport)
        defer { engine.disconnect(reason: "test"); drain(engine) }
        transport.autoComplete = false
        var finished = 0
        engine.write("packet", withType: .message, withData: [Data([1]), Data([2])]) { finished += 1 }
        drain(engine)
        XCTAssertEqual(transport.batches.last, [.text("4packet"), .binary(Data([1])), .binary(Data([2]))])
        XCTAssertEqual(finished, 0)
        engine.engineQueue.sync { transport.completions.removeFirst()(.success(())) }
        XCTAssertEqual(finished, 1)
    }

    func testEngineIO3BinaryKeepsItsMessagePrefix() {
        let (engine, _, transport) = make([.forceWebsockets(true), .version(.two)])
        open(engine, transport)
        defer { engine.disconnect(reason: "test"); drain(engine) }
        engine.write("packet", withType: .message, withData: [Data([9])]); drain(engine)
        XCTAssertEqual(transport.batches.last, [.text("4packet"), .binary(Data([4, 9]))])
    }

    func testEngineIOHeartbeatRemainsText() {
        let (engine, _, transport) = make(); open(engine, transport)
        defer { engine.disconnect(reason: "test"); drain(engine) }
        transport.onEvent?(.message(.text("2"))); drain(engine)
        XCTAssertEqual(transport.batches.last, [.text("3")])
    }

    func testEstablishedReceiveFailureIsDisconnectNotConnectError() {
        let (engine, client, transport) = make(); open(engine, transport)
        transport.onEvent?(.closed(code: nil, reason: nil, error: EngineWebSocketError.closed))
        drain(engine)
        XCTAssertTrue(engine.closed)
        XCTAssertEqual(client.closes.count, 1)
        XCTAssertTrue(client.errors.isEmpty)
    }

    func testOpeningFailureStillSurfacesConnectionError() {
        let (engine, client, transport) = make()
        transport.onEvent?(.closed(code: nil, reason: nil, error: EngineWebSocketError.notOpen))
        drain(engine)
        XCTAssertTrue(engine.closed)
        XCTAssertEqual(client.closes.count, 1)
        XCTAssertEqual(client.errors.count, 1)
        XCTAssertEqual(client.opens, 0)
    }

    func testEngineIO3IncomingBinaryStripsExactlyItsPrefix() {
        let (engine, client, transport) = make([.forceWebsockets(true), .version(.two)])
        open(engine, transport)
        defer { engine.disconnect(reason: "test"); drain(engine) }
        transport.onEvent?(.message(.binary(Data([4, 9]))))
        transport.onEvent?(.message(.binary(Data([4]))))
        drain(engine)
        XCTAssertEqual(client.binary, [Data([9]), Data()])
    }

    func testMalformedEngineIO3BinaryClosesInsteadOfCrashing() {
        for data in [Data(), Data([1, 9])] {
            let (engine, client, transport) = make([.forceWebsockets(true), .version(.two)])
            open(engine, transport)
            transport.onEvent?(.message(.binary(data))); drain(engine)
            XCTAssertTrue(engine.closed)
            XCTAssertEqual(client.errors.count, 1)
            XCTAssertTrue(client.binary.isEmpty)
        }
    }

    func testDuplicateTerminalEventsCloseEngineOnlyOnce() {
        let (engine, client, transport) = make(); open(engine, transport)
        let callback = transport.onEvent!
        callback(.closed(code: 1001, reason: nil, error: nil))
        callback(.closed(code: nil, reason: nil, error: EngineWebSocketError.closed))
        drain(engine)
        XCTAssertEqual(client.closes.count, 1)
        XCTAssertTrue(engine.closed)
        XCTAssertNil(engine.webSocketTransport)
    }

    func testEngineIOCloseReleasesTransportAndSession() {
        let (engine, client, transport) = make(); open(engine, transport)
        transport.onEvent?(.message(.text("1"))); drain(engine)
        XCTAssertTrue(engine.closed)
        XCTAssertNil(engine.session)
        XCTAssertNil(engine.webSocketTransport)
        XCTAssertEqual(client.closes.count, 1)
    }

    func testOldCallbacksCannotOpenOrCloseReplacementConnection() {
        let (engine, client, first) = make()
        let stale = first.onEvent!
        engine.disconnect(reason: "timeout"); drain(engine)
        let second = NativeEngineTransport()
        engine.webSocketTransportFactory = { _ in second }
        engine.connect(); drain(engine); open(engine, second)
        stale(.opened(protocol: nil))
        stale(.message(.text("0{\"sid\":\"stale\"}")))
        stale(.closed(code: nil, reason: nil, error: EngineWebSocketError.closed))
        drain(engine)
        XCTAssertTrue(engine.connected)
        XCTAssertEqual(engine.sid, "native")
        XCTAssertEqual(client.opens, 1)
        XCTAssertEqual(client.closes, ["timeout"])
        engine.disconnect(reason: "test"); drain(engine)
    }

    func testWritableUsesNativeBackpressureAndIsSafeFromManagerQueue() {
        let (engine, _, transport) = make(); open(engine, transport)
        defer { engine.disconnect(reason: "test"); drain(engine) }
        XCTAssertTrue(engine.writable)
        engine.engineQueue.sync { transport.isWritable = false }
        XCTAssertFalse(engine.writable)
        engine.engineQueue.sync { XCTAssertFalse(engine.writable) }
    }

    func testSendFailureIsFatalOnAnActiveWebSocket() {
        let (engine, client, transport) = make(); open(engine, transport)
        transport.autoComplete = false
        var completed = 0
        engine.write("payload", withType: .message, withData: []) { completed += 1 }; drain(engine)
        engine.engineQueue.sync { transport.completions.removeFirst()(.failure(EngineWebSocketError.queueLimitExceeded)) }
        XCTAssertTrue(engine.closed)
        XCTAssertEqual(client.errors.count, 1)
        XCTAssertEqual(client.closes.count, 1)
        XCTAssertEqual(completed, 1)
    }

    func testFailedUpgradeKeepsHealthyPollingAndFlushesBufferedWrites() {
        let client = NativeEngineClient()
        let engine = NativePollingTestEngine(client: client, url: url, config: [])
        let candidate = NativeEngineTransport()
        engine.webSocketTransportFactory = { _ in candidate }
        engine.engineQueue.sync { engine.parseEngineMessage(upgradeHandshake) }
        candidate.onEvent?(.opened(protocol: nil)); drain(engine)
        engine.write("held", withType: .message, withData: []); drain(engine)
        XCTAssertTrue(engine.probing)
        XCTAssertFalse(engine.writable)
        candidate.onEvent?(.closed(code: nil, reason: nil, error: EngineWebSocketError.closed)); drain(engine)
        XCTAssertTrue(engine.connected)
        XCTAssertTrue(engine.polling)
        XCTAssertFalse(engine.probing)
        XCTAssertFalse(engine.fastUpgrade)
        XCTAssertTrue(client.closes.isEmpty)
        XCTAssertTrue(client.errors.isEmpty)
        XCTAssertTrue(engine.pollingWrites.contains("4held"))
        engine.disconnect(reason: "test"); drain(engine)
    }

    /// engine.io-client/test/connection.js — "should defer close when upgrading",
    /// "should send all buffered packets if closing is deferred" and "should not
    /// send packets if closing is deferred". JS `close()` calls `waitForUpgrade()`
    /// while upgrading; the buffer then leaves over the transport that won,
    /// followed by the close packet, and nothing new may be written meanwhile.
    func testCloseDeferredDuringUpgradeFlushesOverWebSocketAfterUpgrade() {
        let client = NativeEngineClient()
        let engine = NativePollingTestEngine(client: client, url: url, config: [])
        let candidate = NativeEngineTransport()
        engine.webSocketTransportFactory = { _ in candidate }
        engine.engineQueue.sync { engine.parseEngineMessage(upgradeHandshake) }
        candidate.onEvent?(.opened(protocol: nil)); drain(engine)
        engine.write("buffered", withType: .message, withData: []); drain(engine)
        engine.disconnect(reason: "io client disconnect"); drain(engine)
        XCTAssertFalse(engine.closed)
        XCTAssertTrue(engine.connected)
        XCTAssertTrue(client.closes.isEmpty)
        engine.write("late", withType: .message, withData: []); drain(engine)
        candidate.onEvent?(.message(.text("3probe"))); drain(engine)
        engine.engineQueue.sync { engine.doFastUpgrade() }
        drain(engine)
        XCTAssertFalse(engine.polling)
        XCTAssertEqual(candidate.batches.flatMap { $0 },
                       [.text("2probe"), .text("5"), .text("4buffered"), .text("1")])
        XCTAssertEqual(client.closes, ["io client disconnect"])
        XCTAssertTrue(client.errors.isEmpty)
    }

    /// engine.io-client/test/connection.js — "should close on upgradeError if
    /// closing is deferred": `waitForUpgrade()` also resumes on `upgradeError`,
    /// and the held packets then go out over polling before the close.
    func testCloseDeferredDuringUpgradeResumesOverPollingOnUpgradeError() {
        let client = NativeEngineClient()
        let engine = NativePollingTestEngine(client: client, url: url, config: [])
        let candidate = NativeEngineTransport()
        engine.webSocketTransportFactory = { _ in candidate }
        engine.engineQueue.sync { engine.parseEngineMessage(upgradeHandshake) }
        candidate.onEvent?(.opened(protocol: nil)); drain(engine)
        engine.write("held", withType: .message, withData: []); drain(engine)
        engine.disconnect(reason: "io client disconnect"); drain(engine)
        XCTAssertFalse(engine.closed)
        candidate.onEvent?(.closed(code: nil, reason: nil, error: EngineWebSocketError.closed)); drain(engine)
        XCTAssertTrue(engine.closed)
        XCTAssertTrue(engine.pollingWrites.contains("4held"))
        XCTAssertEqual(client.closes, ["io client disconnect"])
        XCTAssertTrue(client.errors.isEmpty)
    }

    /// engine.io-client `_onError`: the native failure is reported (`error`)
    /// before the close; the client used to swallow it under an established
    /// connection and only report "transport error".
    func testTransportFailureUnderAnEstablishedConnectionReportsItsDetailBeforeClosing() {
        let (engine, client, transport) = make()
        open(engine, transport)
        engine.engineQueue.sync { XCTAssertTrue(engine.connected) }

        let failure = NSError(domain: "NSPOSIXErrorDomain", code: 57,
                              userInfo: [NSLocalizedDescriptionKey: "Socket is not connected",
                                         NSUnderlyingErrorKey: NSError(domain: "kNWErrorDomainPOSIX", code: 57, userInfo: nil)])
        transport.onEvent?(.closed(code: 1006, reason: Data("gone".utf8), error: failure)); drain(engine)

        XCTAssertEqual(client.closes, ["transport error"])
        XCTAssertEqual(client.errors.count, 1)
        let detail = client.errors.first ?? ""
        XCTAssertTrue(detail.contains("NSPOSIXErrorDomain/57"), detail)
        XCTAssertTrue(detail.contains("Socket is not connected"), detail)
        XCTAssertTrue(detail.contains("underlying kNWErrorDomainPOSIX/57"), detail)
        XCTAssertTrue(detail.contains("close code 1006"), detail)
        XCTAssertTrue(detail.contains("reason gone"), detail)
    }

    /// A clean close under an established connection stays a plain
    /// "transport close" without an error event, like JS `_onClose`.
    func testCleanTransportCloseUnderAnEstablishedConnectionReportsNoError() {
        let (engine, client, transport) = make()
        open(engine, transport)
        transport.onEvent?(.closed(code: 1000, reason: nil, error: nil)); drain(engine)
        XCTAssertEqual(client.closes, ["transport close"])
        XCTAssertEqual(client.errors, [])
    }

    /// After `stopPolling()` retired the polling session, a failed upgrade
    /// candidate cannot fall back to polling: there is no transport to poll
    /// with, so the engine closes instead of staying "connected" without one.
    func testUpgradeFailureAfterStopPollingClosesInsteadOfResumingPolling() {
        let client = NativeEngineClient()
        let engine = NativePollingTestEngine(client: client, url: url, config: [])
        let candidate = NativeEngineTransport()
        engine.webSocketTransportFactory = { _ in candidate }
        engine.engineQueue.sync { engine.parseEngineMessage(upgradeHandshake) }
        candidate.onEvent?(.opened(protocol: nil)); drain(engine)
        engine.engineQueue.sync { engine.stopPolling() }
        let pollsBefore = engine.polls
        candidate.onEvent?(.closed(code: nil, reason: nil, error: EngineWebSocketError.closed)); drain(engine)
        engine.engineQueue.sync {
            XCTAssertTrue(engine.closed)
            XCTAssertFalse(engine.connected)
        }
        XCTAssertEqual(engine.polls, pollsBefore, "no poll may start on the retired session")
        XCTAssertEqual(client.closes, ["transport error"])
    }

    func testUpgradeWaitsForGetAndPostAndQueuesUpgradeFirst() {
        let client = NativeEngineClient()
        let engine = NativePollingTestEngine(client: client, url: url, config: [])
        let candidate = NativeEngineTransport()
        engine.webSocketTransportFactory = { _ in candidate }
        engine.engineQueue.sync { engine.parseEngineMessage(upgradeHandshake) }
        candidate.onEvent?(.opened(protocol: nil)); drain(engine)
        engine.write("new", withType: .message, withData: []); drain(engine)
        engine.engineQueue.sync {
            engine.postWait = [("4old", nil)]
            engine.waitingForPoll = true
            engine.waitingForPost = true
        }
        candidate.onEvent?(.message(.text("3probe"))); drain(engine)
        engine.engineQueue.sync {
            engine.doFastUpgrade()
            XCTAssertTrue(engine.polling)
            engine.waitingForPoll = false
            engine.doFastUpgrade()
            XCTAssertTrue(engine.polling)
            engine.waitingForPost = false
            engine.doFastUpgrade()
        }
        drain(engine)
        XCTAssertFalse(engine.polling)
        XCTAssertEqual(candidate.batches.flatMap { $0 }, [.text("2probe"), .text("5"), .text("4old"), .text("4new")])
        engine.disconnect(reason: "test"); drain(engine)
    }

    func testUnsupportedOptionsFailBeforeOpeningTransport() {
        let invalid: [SocketIOClientConfiguration] = [
            [.forceWebsockets(true), .selfSigned(true)],
            [.forceWebsockets(true), .enableSOCKSProxy(true)],
            [.forceWebsockets(true), .compress],
            [.forceWebsockets(true), .webSocketOptions(.init(maximumMessageSize: 0))],
            [.forceWebsockets(true), .forcePolling(true)],
            [.forceWebsockets(true), .security(.certificatePinning([]))]
        ]
        for config in invalid {
            let (engine, client, transport) = make(config)
            XCTAssertTrue(engine.closed)
            XCTAssertEqual(transport.connects, 0)
            XCTAssertEqual(client.errors.count, 1)
            XCTAssertEqual(client.closes.count, 1)
        }
    }

    func testInvalidDictionarySecurityNeverDisappears() {
        for key in ["security", "secure", "selfSigned", "sessionDelegate", "enableSOCKSProxy", "webSocketOptions"] {
            let config = ["forceWebsockets": true, key: "invalid legacy object"] as [String: Any]
            let (engine, client, transport) = make(config.toSocketConfiguration())
            XCTAssertTrue(engine.closed, key)
            XCTAssertEqual(transport.connects, 0, key)
            XCTAssertEqual(client.errors.count, 1, key)
        }
    }

    func testFalseLegacyProxyAndBackendOptionsUseNativeTransport() {
        let (engine, client, transport) = make([.forceWebsockets(true), .enableSOCKSProxy(false), .useCustomEngine(false)])
        XCTAssertEqual(transport.connects, 1)
        XCTAssertTrue(client.errors.isEmpty)
        engine.disconnect(reason: "test"); drain(engine)
    }

    func testRequestPreservesHeadersCookiePrecedencePathAndParameters() {
        let client = NativeEngineClient()
        let cookie = HTTPCookie(properties: [.domain: "localhost", .path: "/", .name: "configured", .value: "yes"])!
        let engine = SocketEngine(client: client, url: url, config: [
            .forceWebsockets(true), .cookies([cookie]), .path("/custom"), .connectParams(["hello": "a b"]),
            .extraHeaders(["Cookie": "explicit=yes", "Authorization": "Bearer test"])
        ])
        let transport = NativeEngineTransport()
        var captured: URLRequest?
        engine.webSocketTransportFactory = { captured = $0; return transport }
        engine.connect(); drain(engine)
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Cookie"), "explicit=yes")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer test")
        XCTAssertEqual(URLComponents(url: captured!.url!, resolvingAgainstBaseURL: false)?.path, "/custom/")
        let params = URLComponents(url: captured!.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(params.contains(URLQueryItem(name: "hello", value: "a b")))
        XCTAssertTrue(params.contains(URLQueryItem(name: "EIO", value: "4")))
        engine.disconnect(reason: "test"); drain(engine)
    }

    func testManagerConnectTimeoutIgnoresLateNativeHandshake() {
        let config: SocketIOClientConfiguration = [.forceWebsockets(true), .reconnects(false), .connectTimeout(0.05)]
        let manager = SocketManager(socketURL: url, config: config)
        let engine = SocketEngine(client: manager, url: url, config: config)
        let transport = NativeEngineTransport()
        engine.webSocketTransportFactory = { _ in transport }
        manager.engine = engine
        let socket = manager.defaultSocket
        let timedOut = expectation(description: "manager timeout")
        socket.on(clientEvent: .connectError) { values, _ in
            if values.first as? String == "timeout" { timedOut.fulfill() }
        }
        socket.connect(); drain(engine)
        let stale = transport.onEvent
        wait(for: [timedOut], timeout: 3)
        drain(engine)
        stale?(.opened(protocol: nil))
        stale?(.message(.text(handshake)))
        drain(engine)
        XCTAssertTrue(engine.closed)
        XCTAssertFalse(engine.connected)
        XCTAssertNotEqual(socket.status, .connected)
        manager.disconnect()
    }
}
