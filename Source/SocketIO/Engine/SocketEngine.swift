//
//  SocketEngine.swift
//  Socket.IO-Client-Swift
//
//  Created by Erik Little on 3/3/15.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Dispatch
import Foundation

/// The class that handles the engine.io protocol and transports.
/// See `SocketEnginePollable` and `SocketEngineWebsocket` for transport specific methods.
open class SocketEngine: NSObject, URLSessionDelegate,
                         SocketEnginePollable, SocketEngineWebsocket, ConfigSettable {
  
  
    // MARK: Properties

    private static let logType = "SocketEngine"

    /// The queue that all engine actions take place on.
    public let engineQueue = DispatchQueue(label: "com.socketio.engineHandleQueue")
    private let engineQueueKey = DispatchSpecificKey<Bool>()
    private var generation: UInt64 = 0
    internal private(set) var webSocketTransport: EngineWebSocketTransport?
    internal var webSocketTransportFactory: ((URLRequest) -> EngineWebSocketTransport)?
    internal var webSocketProbeTimeout: TimeInterval = 10
    private var tlsConfiguration: SocketTLSConfiguration = .systemDefault
    private var webSocketOptions = SocketWebSocketOptions()
    private var configurationError: String?

    /// The connect parameters sent during a connect.
    public var connectParams: [String: Any]? {
        didSet {
            (urlPolling, urlWebSocket) = createURLs()
        }
    }

    /// A dictionary of extra http headers that will be set during connection.
    public var extraHeaders: [String: String]?

    /// A queue of engine.io messages waiting for POSTing
    ///
    /// **You should not touch this directly**
    public var postWait = [Post]()

    /// `true` if there is an outstanding poll. Trying to poll before the first is done will cause socket.io to
    /// disconnect us.
    ///
    /// **Do not touch this directly**
    public var waitingForPoll = false

    /// `true` if there is an outstanding post. Trying to post before the first is done will cause socket.io to
    /// disconnect us.
    ///
    /// **Do not touch this directly**
    public var waitingForPost = false

    /// `true` if this engine is closed.
    public private(set) var closed = false

    /// If `true` the engine will attempt to use WebSocket compression.
    public private(set) var compress = false

    /// `true` if this engine is connected. Connected means that the initial poll connect has succeeded.
    public private(set) var connected = false

    /// Whether the active transport can accept a volatile write without queuing.
    /// The manager reads this from its own queue; native transport state is always
    /// inspected on engineQueue, including while a polling upgrade is in progress.
    public var writable: Bool {
        let read = {
            self.connected && !self.closed && !self.probing && !self.fastUpgrade &&
                (self.polling ? !self.waitingForPost :
                    (self.wsConnected && self.webSocketTransport?.isWritable == true))
        }
        if DispatchQueue.getSpecific(key: engineQueueKey) != nil { return read() }
        return engineQueue.sync(execute: read)
    }

    /// An array of HTTPCookies that are sent during the connection.
    public private(set) var cookies: [HTTPCookie]?

    /// When `true`, the engine is in the process of switching to WebSockets.
    ///
    /// **Do not touch this directly**
    public private(set) var fastUpgrade = false

    /// When `true`, the engine will only use HTTP long-polling as a transport.
    public private(set) var forcePolling = false

    /// When `true`, the engine will only use WebSockets as a transport.
    public private(set) var forceWebsockets = false

    /// `true` If engine's session has been invalidated.
    public private(set) var invalidated = false

    /// If `true`, the engine is currently in HTTP long-polling mode.
    public private(set) var polling = true

    /// The maximum number of bytes this server accepts in a single polling POST,
    /// taken from the handshake. `nil` before the handshake, and on engine.io v3
    /// where servers do not advertise a limit.
    public private(set) var maxPayload: Int?

    /// If `true`, the engine is currently seeing whether it can upgrade to WebSockets.
    public private(set) var probing = false

    /// The URLSession that will be used for polling.
    public private(set) var session: URLSession?

    /// The session id for this engine.
    public private(set) var sid = ""

    /// The path to engine.io.
    public private(set) var socketPath = "/engine.io/"

    /// Whether polling/WebSocket requests carry a cache-busting timestamp
    /// query parameter. `nil` is the JS default (`timestampRequests` unset):
    /// polling requests carry it, WebSocket URLs do not. `true`: both carry
    /// it. `false`: neither does.
    public private(set) var timestampRequests: Bool? = nil

    /// The query parameter name used for the cache-busting timestamp.
    /// Default `"t"`, JS-aligned with `timestampParam` in engine.io-client.
    public private(set) var timestampParam = "t"

    /// The url for polling.
    public private(set) var urlPolling = URL(string: "http://localhost/")!

    /// The url for WebSockets.
    public private(set) var urlWebSocket = URL(string: "http://localhost/")!

    /// Compatibility property. The only WebSocket backend is URLSession.
    @available(*, deprecated, message: "URLSession is always used")
    public private(set) var useCustomEngine = false

    /// The version of engine.io being used. Default is three.
    public private(set) var version: SocketIOVersion = .three

    /// If `true`, then the engine is currently in WebSockets mode.
    @available(*, deprecated, message: "No longer needed, if we're not polling, then we must be doing websockets")
    public private(set) var websocket = false

    /// Requested legacy SOCKS option. `true` fails validation before any network request.
    public private(set) var enableSOCKSProxy = false


    /// Whether or not the WebSocket is currently connected.
    public private(set) var wsConnected = false

    /// The client for this engine.
    public weak var client: SocketEngineClient?

    private weak var sessionDelegate: URLSessionDelegate?

    private let url: URL

    private var lastCommunication: Date?
    private var pingInterval: Int?
    private var pingTimeout = 0 {
        didSet {
            pongsMissedMax = Int(pingTimeout / max(1, pingInterval ?? 25000))
        }
    }

    private var pongsMissed = 0
    private var pongsMissedMax = 0
    private var probeWait = ProbeWaitQueue()
    private var secure = false
    private var selfSigned = false

    // MARK: Initializers

    /// Creates a new engine.
    ///
    /// - parameter client: The client for this engine.
    /// - parameter url: The url for this engine.
    /// - parameter config: An array of configuration options for this engine.
    public init(client: SocketEngineClient, url: URL, config: SocketIOClientConfiguration) {
        self.client = client
        self.url = url
        self.secure = ["https", "wss"].contains(url.scheme?.lowercased() ?? "")

        super.init()

        setConfigs(config)

        engineQueue.setSpecific(key: engineQueueKey, value: true)

        (urlPolling, urlWebSocket) = createURLs()
    }

    /// Creates a new engine.
    ///
    /// - parameter client: The client for this engine.
    /// - parameter url: The url for this engine.
    /// - parameter options: The options for this engine.
    public required convenience init(client: SocketEngineClient, url: URL, options: [String: Any]?) {
        self.init(client: client, url: url, config: options?.toSocketConfiguration() ?? [])
    }

    /// :nodoc:
    deinit {
        DefaultSocketLogger.Logger.log("Engine is being released", type: SocketEngine.logType)
        closed = true
        session?.invalidateAndCancel()
        let abandoned = webSocketTransport
        engineQueue.async {
            abandoned?.onEvent = nil
            abandoned?.abort()
        }
    }

    // MARK: Methods

    private func checkAndHandleEngineError(_ msg: String) {
        do {
            let dict = try msg.toDictionary()
            guard let error = dict["message"] as? String else { return }

            /*
             0: Unknown transport
             1: Unknown sid
             2: Bad handshake request
             3: Bad request
             */
            didError(reason: error)
        } catch {
            client?.engineDidError(reason: "Got unknown error from server \(msg)")
        }
    }

    private func handleBase64(message: String) {
        let offset = version.rawValue >= 3 ? 1 : 2
        // binary in base64 string
        let noPrefix = String(message[message.index(message.startIndex, offsetBy: offset)..<message.endIndex])

        if let data = Data(base64Encoded: noPrefix, options: .ignoreUnknownCharacters) {
            client?.parseEngineBinaryData(data)
        }
    }

    private func closeOutEngine(reason: String, graceful: Bool = false) {
        guard !closed else { return }
        let oldTransport = webSocketTransport
        let wasWebSocketOpen = wsConnected
        let wasPolling = polling
        let pendingPosts = postWait
        let pendingProbes = probeWait
        sid = ""
        closed = true
        invalidated = true
        connected = false
        wsConnected = false
        probing = false
        fastUpgrade = false
        waitingForPoll = false
        waitingForPost = false
        webSocketTransport = nil
        postWait.removeAll()
        probeWait.removeAll()
        let oldSession = session
        session = nil
        if graceful && wasPolling {
            // Allow the already-enqueued final polling POST to leave before
            // invalidating the old session, but bound a stuck outstanding GET.
            oldSession?.finishTasksAndInvalidate()
            engineQueue.asyncAfter(deadline: .now() + 1) { oldSession?.invalidateAndCancel() }
        } else {
            oldSession?.invalidateAndCancel()
        }
        oldTransport?.onEvent = nil
        if graceful, !wasPolling, wasWebSocketOpen, let transport = oldTransport {
            // Send Engine.IO's close packet after earlier writes. Detach the old
            // transport first: neither its close nor its completions can affect
            // a replacement engine connection. Bound even a stalled final write.
            transport.sendBatch([.text("1")]) { [weak transport] result in
                if case .success = result { transport?.close(code: 1000, reason: nil) }
                else { transport?.abort() }
            }
            engineQueue.asyncAfter(deadline: .now() + 1) { transport.abort() }
        } else {
            oldTransport?.abort()
        }
        client?.engineDidClose(reason: reason)
        for pending in pendingPosts { pending.completion?() }
        for pending in pendingProbes { pending.completion?() }
    }

    /// Starts the connection to the server.
    open func connect() {
        engineQueue.async {
            self._connect()
        }
    }

    private func _connect() {
        if connected {
            DefaultSocketLogger.Logger.error("Engine tried opening while connected. Assuming this was a reconnect",
                                             type: SocketEngine.logType)
            _disconnect(reason: "transport close")
        }

        DefaultSocketLogger.Logger.log("Starting engine. Server: \(url)", type: SocketEngine.logType)
        DefaultSocketLogger.Logger.log("Handshaking", type: SocketEngine.logType)

        resetEngine()
        if let error = validateConfiguration() {
            didError(reason: "Invalid socket configuration: " + error)
            return
        }

        if forceWebsockets {
            polling = false
            createWebSocketAndConnect()
            return
        }

        var reqPolling = URLRequest(url: urlPollingHandshake, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60.0)

        addHeaders(to: &reqPolling)
        doLongPoll(for: reqPolling)
    }

    private func createURLs() -> (URL, URL) {
        if client == nil {
            return (URL(string: "http://localhost/")!, URL(string: "http://localhost/")!)
        }

        var urlPolling = URLComponents(string: url.absoluteString)!
        var urlWebSocket = URLComponents(string: url.absoluteString)!
        var queryString = ""

        urlWebSocket.path = socketPath
        urlPolling.path = socketPath

        if secure {
            urlPolling.scheme = "https"
            urlWebSocket.scheme = "wss"
        } else {
            urlPolling.scheme = "http"
            urlWebSocket.scheme = "ws"
        }

        if let connectParams = self.connectParams {
            for (key, value) in connectParams {
                let keyEsc = key.urlEncode()!
                let valueEsc = "\(value)".urlEncode()!

                queryString += "&\(keyEsc)=\(valueEsc)"
            }
        }

        urlWebSocket.percentEncodedQuery = "transport=websocket" + queryString
        urlPolling.percentEncodedQuery = "transport=polling&b64=1" + queryString

        if !urlWebSocket.percentEncodedQuery!.contains("EIO") {
            urlWebSocket.percentEncodedQuery = urlWebSocket.percentEncodedQuery! + engineIOParam
        }

        if !urlPolling.percentEncodedQuery!.contains("EIO") {
            urlPolling.percentEncodedQuery = urlPolling.percentEncodedQuery! + engineIOParam
        }

        return (urlPolling.url!, urlWebSocket.url!)
    }

    private func createWebSocketAndConnect() {
        var request = URLRequest(url: urlWebSocketWithSid)
        addHeaders(to: &request, includingCookies:
            session?.configuration.httpCookieStorage?.cookies(for: urlPollingWithSid))
        // addHeaders already applies explicit Cookie/extraHeaders precedence.
        request.httpShouldHandleCookies = false
        let options = webSocketOptions
        let transport = webSocketTransportFactory?(request) ?? URLSessionWebSocketTransport(
            request: request, queue: engineQueue,
            tlsConfiguration: tlsConfiguration, sessionDelegate: sessionDelegate,
            maximumMessageSize: options.maximumMessageSize,
            maximumPendingBytes: options.maximumPendingBytes,
            maximumPendingBatches: options.maximumPendingBatches,
            maximumPendingMessages: options.maximumPendingMessages)
        let attempt = generation
        webSocketTransport = transport
        transport.onEvent = { [weak self, weak transport] event in
            self?.engineQueue.async { [weak self, weak transport] in
                guard let self = self, let transport = transport,
                      self.generation == attempt, !self.closed,
                      self.webSocketTransport === transport else { return }
                switch event {
                case .opened(_, let headers):
                    self.wsConnected = true
                    self.client?.engineDidWebsocketUpgrade(headers: headers)
                    self.websocketDidConnect()
                case .message(.text(let message)):
                    self.parseEngineMessage(message)
                case .message(.binary(let data)):
                    self.parseEngineData(data)
                case .closed(_, let reason, let error):
                    self.websocketDidDisconnect(error: error, reason: reason.flatMap { String(data: $0, encoding: .utf8) })
                }
            }
        }
        transport.connect()
    }

    private func validateConfiguration() -> String? {
        if let error = configurationError { return error }
        if forcePolling && forceWebsockets { return "forcePolling and forceWebsockets cannot both be true" }
        if selfSigned { return "selfSigned(true) is unsupported; use security(.customTrust(anchors:pins:))" }
        if enableSOCKSProxy { return "enableSOCKSProxy(true) is unsupported by the native transport; refusing a direct connection" }
        if compress { return "compress is unsupported: URLSession does not expose compression negotiation controls" }
        if tlsConfiguration.requiresTLS && !secure { return "a custom security policy requires https/wss" }
        return tlsConfiguration.validationError ?? webSocketOptions.validationError
    }

    /// Called when an error happens during execution. Causes a disconnection.
    open func didError(reason: String) {
        let fail = { [weak self] in
            guard let self = self, !self.closed else { return }
            DefaultSocketLogger.Logger.error(reason, type: SocketEngine.logType)
            self.client?.engineDidError(reason: reason)
            self.closeOutEngine(reason: "transport error")
        }
        if DispatchQueue.getSpecific(key: engineQueueKey) != nil { fail() }
        else { engineQueue.async(execute: fail) }
    }

    /// Disconnects from the server.
    ///
    /// - parameter reason: The reason for the disconnection. This is communicated up to the client.
    open func disconnect(reason: String) {
        engineQueue.async {
            self._disconnect(reason: reason)
        }
    }

    private func _disconnect(reason: String) {
        guard connected && !closed else { return closeOutEngine(reason: reason) }

        DefaultSocketLogger.Logger.log("Engine is being closed.", type: SocketEngine.logType)

        if polling {
            disconnectPolling(reason: reason)
        } else {
            closeOutEngine(reason: reason, graceful: true)
        }
    }

    // We need to take special care when we're polling that we send it ASAP
    // Also make sure we're on the emitQueue since we're touching postWait
    private func disconnectPolling(reason: String) {
        postWait.append((String(SocketEnginePacketType.close.rawValue), {}))

        doRequest(for: createRequestForPostWithPostWait()) {_, _, _ in }
        closeOutEngine(reason: reason, graceful: true)
    }

    /// Called to switch from HTTP long-polling to WebSockets. After calling this method the engine will be in
    /// WebSocket mode.
    ///
    /// **You shouldn't call this directly**
    open func doFastUpgrade() {
        guard canSendUpgradePacket, wsConnected, !closed else { return }
        DefaultSocketLogger.Logger.log("Switching to WebSockets", type: SocketEngine.logType)
        polling = false
        fastUpgrade = false
        probing = false
        // Queue the upgrade packet before anything held by the polling transport.
        sendWebSocketMessage("", withType: .upgrade, withData: [], completion: nil)
        guard !closed else { return }
        flushWaitingForPostToWebSocket()
        flushProbeWait()
    }

    private func flushProbeWait() {
        let waiting = probeWait
        probeWait.removeAll(keepingCapacity: false)
        for waiter in waiting {
            _write(waiter.msg, withType: waiter.type, withData: waiter.data, completion: waiter.completion)
        }
    }

    /// Flush polling wire packets as one FIFO batch (base64 binary remains valid
    /// Engine.IO text). Detach before completions to make reentrancy safe.
    open func flushWaitingForPostToWebSocket() {
        guard webSocketTransport != nil, !postWait.isEmpty else { return }
        let waiting = postWait
        postWait.removeAll(keepingCapacity: false)
        sendWebSocketBatch(waiting.map { .text($0.msg) }) {
            for waiter in waiting { waiter.completion?() }
        }
    }

    /// Completes once for the entire text header plus binary attachments. The
    /// callback reports local completion, not a server acknowledgement.
    open func sendWebSocketMessage(_ str: String, withType type: SocketEnginePacketType,
                                   withData data: [Data], completion: (() -> ())?) {
        guard DispatchQueue.getSpecific(key: engineQueueKey) != nil else {
            engineQueue.async { self.sendWebSocketMessage(str, withType: type, withData: data, completion: completion) }
            return
        }
        var messages: [EngineWebSocketMessage] = [.text("\(type.rawValue)\(str)")]
        messages += data.map { .binary(version.rawValue >= 3 ? $0 : Data([0x4]) + $0) }
        sendWebSocketBatch(messages, completion: completion)
    }

    private func sendWebSocketBatch(_ messages: [EngineWebSocketMessage], completion: (() -> Void)?) {
        guard let transport = webSocketTransport, wsConnected, !closed else {
            completion?()
            return
        }
        let attempt = generation
        transport.sendBatch(messages) { [weak self, weak transport] result in
            defer { completion?() }
            guard let self = self, let transport = transport,
                  self.generation == attempt, self.webSocketTransport === transport, !self.closed else { return }
            if case .failure(let error) = result { self.websocketDidDisconnect(error: error, reportSendError: true) }
        }
    }

    private func handleClose(_ reason: String) {
        // JS: engine.io-client maps the server's CLOSE packet to
        // "transport close" (engine.io v4 close packets carry no reason).
        closeOutEngine(reason: "transport close")
    }

    private func handleMessage(_ message: String) {
        client?.parseEngineMessage(message)
    }

    private func handleNOOP() {
        doPoll()
    }

    private func handleOpen(openData: String) {
        guard !closed, !connected else { return }
        guard let json = try? openData.toDictionary() else {
            didError(reason: "Error parsing open packet")

            return
        }

        guard let sid = json["sid"] as? String else {
            didError(reason: "Open packet contained no sid")

            return
        }

        let upgradeWs: Bool

        self.sid = sid
        connected = true
        pongsMissed = 0

        if let upgrades = json["upgrades"] as? [String] {
            upgradeWs = upgrades.contains("websocket")
        } else {
            upgradeWs = false
        }

        if let pingInterval = json["pingInterval"] as? Int, let pingTimeout = json["pingTimeout"] as? Int {
            self.pingInterval = pingInterval
            self.pingTimeout = pingTimeout
        }

        // engine.io v4 only. v3 servers do not advertise a limit, and `nil` means
        // we batch without one, which is how this client always behaved.
        maxPayload = json["maxPayload"] as? Int

        if !forcePolling && !forceWebsockets && upgradeWs {
            createWebSocketAndConnect()
        }

        if version.rawValue >= 3 {
            checkPings()
        } else {
            sendPing()
        }

        if !forceWebsockets {
            doPoll()
        }

        client?.engineDidOpen(reason: "Connect")
    }

    private func handlePong(with message: String) {
        pongsMissed = 0

        // We should upgrade
        if message == "3probe" {
            DefaultSocketLogger.Logger.log("Received probe response, should upgrade to WebSockets",
                                           type: SocketEngine.logType)

            upgradeTransport()
        }

        client?.engineDidReceivePong()
    }

    private func handlePing(with message: String) {
        if version.rawValue >= 3 {
            write("", withType: .pong, withData: [])
        }

        client?.engineDidReceivePing()
    }

    private func checkPings() {
        let pingInterval = self.pingInterval ?? 25_000
        let deadlineMs = Double(pingInterval + pingTimeout) / 1000
        let timeoutDeadline = DispatchTime.now() + .milliseconds(pingInterval + pingTimeout)

        engineQueue.asyncAfter(deadline: timeoutDeadline) {[weak self, attempt = self.generation] in
            // Make sure not to ping old connections
            guard let this = self, this.generation == attempt && !this.closed else { return }

            if abs(this.lastCommunication?.timeIntervalSinceNow ?? deadlineMs) >= deadlineMs {
                this.closeOutEngine(reason: "ping timeout")
            } else {
                this.checkPings()
            }
        }
    }

    /// Parses raw binary received from engine.io.
    ///
    /// - parameter data: The data to parse.
    open func parseEngineData(_ data: Data) {
        guard !closed else {
            DefaultSocketLogger.Logger.log("Ignoring binary data received after close", type: SocketEngine.logType)

            return
        }

        DefaultSocketLogger.Logger.log("Got binary data: \(data)", type: SocketEngine.logType)

        lastCommunication = Date()

        guard version.rawValue >= 3 || data.first == 0x04 else {
            didError(reason: "Invalid Engine.IO 3 binary packet")
            return
        }
        client?.parseEngineBinaryData(version.rawValue >= 3 ? data : Data(data.dropFirst()))
    }

    /// Parses a raw engine.io packet.
    ///
    /// - parameter message: The message to parse.
    open func parseEngineMessage(_ message: String) {
        // JS-aligned (`_onPacket` in engine.io-client/lib/socket.ts ignores
        // packets unless readyState is opening/open/closing): after close the
        // session is over, so late packets — e.g. a handshake that finished
        // after a timeout-close — must not revive the engine.
        guard !closed else {
            DefaultSocketLogger.Logger.log("Ignoring packet received after close: \(message)", type: SocketEngine.logType)

            return
        }

        lastCommunication = Date()

        DefaultSocketLogger.Logger.log("Got message: \(message)", type: SocketEngine.logType)

        if message.hasPrefix(version.rawValue >= 3 ? "b" : "b4") {
            return handleBase64(message: message)
        }

        guard let type = SocketEnginePacketType(rawValue: message.first?.wholeNumberValue ?? -1) else {
            checkAndHandleEngineError(message)

            return
        }

        switch type {
        case .message:
            handleMessage(String(message.dropFirst()))
        case .noop:
            handleNOOP()
        case .ping:
            handlePing(with: message)
        case .pong:
            handlePong(with: message)
        case .open:
            handleOpen(openData: String(message.dropFirst()))
        case .close:
            handleClose(message)
        default:
            DefaultSocketLogger.Logger.log("Got unknown packet type", type: SocketEngine.logType)
        }
    }

    // Puts the engine back in its default state
    private func resetEngine() {
        // Retire all callbacks before constructing a new session. A SID alone is
        // not a sufficient identity while either attempt is still handshaking.
        generation &+= 1
        webSocketTransport?.onEvent = nil
        webSocketTransport?.abort()
        webSocketTransport = nil
        let oldSession = session
        session = nil
        oldSession?.invalidateAndCancel()
        let pendingPosts = postWait
        let pendingProbes = probeWait
        postWait.removeAll(keepingCapacity: true)
        probeWait.removeAll(keepingCapacity: false)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.underlyingQueue = engineQueue
        closed = false
        connected = false
        wsConnected = false
        fastUpgrade = false
        maxPayload = nil
        polling = true
        probing = false
        invalidated = false
        sid = ""
        waitingForPoll = false
        waitingForPost = false
        lastCommunication = nil
        pingInterval = nil
        pingTimeout = 0
        pongsMissed = 0
        let proxy = SocketSessionDelegateProxy(tlsConfiguration: tlsConfiguration, forwardingDelegate: sessionDelegate)
        proxy.onInvalidation = { [weak self] invalidSession, error in
            guard let self = self, self.session === invalidSession, self.polling, !self.closed,
                  let error = error else { return }
            self.didError(reason: error.localizedDescription)
        }
        session = Foundation.URLSession(configuration: .default, delegate: proxy, delegateQueue: queue)
        for pending in pendingPosts { pending.completion?() }
        for pending in pendingProbes { pending.completion?() }
    }

    private func sendPing() {
        guard connected, let pingInterval = pingInterval else {
            return
        }

        // Server is not responding
        if pongsMissed > pongsMissedMax {
            closeOutEngine(reason: "ping timeout")
            return
        }

        pongsMissed += 1
        write("", withType: .ping, withData: [], completion: nil)

        engineQueue.asyncAfter(deadline: .now() + .milliseconds(pingInterval)) {[weak self, attempt = self.generation] in
            // Make sure not to ping old connections
            guard let this = self, this.generation == attempt && !this.closed else {
                return
            }

            this.sendPing()
        }

        client?.engineDidSendPing()
    }

    /// Called when the engine should set/update its configs from a given configuration.
    ///
    /// parameter config: The `SocketIOClientConfiguration` that should be used to set/update configs.
    open func setConfigs(_ config: SocketIOClientConfiguration) {
        configurationError = nil
        for option in config {
            switch option {
            case let .connectParams(params):
                connectParams = params
            case let .cookies(cookies):
                self.cookies = cookies
            case let .extraHeaders(headers):
                extraHeaders = headers
            case let .sessionDelegate(delegate):
                sessionDelegate = delegate
            case let .forcePolling(force):
                forcePolling = force
            case let .forceWebsockets(force):
                forceWebsockets = force
            case let .path(path):
                socketPath = path

                if !socketPath.hasSuffix("/") {
                    socketPath += "/"
                }
            case let .secure(secure):
                self.secure = secure
            case let .selfSigned(selfSigned):
                self.selfSigned = selfSigned
            case let .security(policy):
                tlsConfiguration = policy
            case let .webSocketOptions(options):
                webSocketOptions = options
            case let .invalidConfiguration(reason):
                configurationError = reason
            case .compress:
                self.compress = true
            case let .timestampRequests(stamp):
                timestampRequests = stamp
            case let .timestampParam(param):
                timestampParam = param
            case let .enableSOCKSProxy(enable):
                self.enableSOCKSProxy = enable
            case .useCustomEngine:
                self.useCustomEngine = false // Deprecated compatibility option; native is the only backend.
            case let .version(num):
                version = num
            default:
                continue
            }
        }
    }

    // Moves from long-polling to websockets
    private func upgradeTransport() {
        if wsConnected {
            DefaultSocketLogger.Logger.log("Upgrading transport to WebSockets", type: SocketEngine.logType)

            fastUpgrade = true
            sendPollMessage("", withType: .noop, withData: [], completion: nil)
            // After this point, we should not send anymore polling messages
        }
    }

    /// Writes a message to engine.io, independent of transport.
    ///
    /// - parameter msg: The message to send.
    /// - parameter type: The type of this message.
    /// - parameter data: Any data that this message has.
    /// - parameter completion: Callback called on transport write completion.
    open func write(_ msg: String, withType type: SocketEnginePacketType, withData data: [Data], completion: (() -> ())? = nil) {
        engineQueue.async {
            self._write(msg, withType: type, withData: data, completion: completion)
        }
    }

    private func _write(_ msg: String, withType type: SocketEnginePacketType,
                        withData data: [Data], completion: (() -> Void)?) {
        guard connected, !closed else { completion?(); return }
        guard !probing else {
            probeWait.append((msg, type, data, completion))
            return
        }
        if polling { sendPollMessage(msg, withType: type, withData: data, completion: completion) }
        else { sendWebSocketMessage(msg, withType: type, withData: data, completion: completion) }
    }

    private func websocketDidConnect() {
        // RFC6455 open is not Engine.IO open. In forced-WebSocket mode only the
        // subsequent Engine.IO `0{...}` handshake may set `connected`.
        guard !forceWebsockets else { return }
        probing = true
        probeWebSocket()
        let attempt = generation
        let candidate = webSocketTransport
        engineQueue.asyncAfter(deadline: .now() + webSocketProbeTimeout) { [weak self, weak candidate] in
            guard let self = self, let candidate = candidate,
                  self.generation == attempt, self.webSocketTransport === candidate,
                  self.probing, !self.closed else { return }
            self.websocketDidDisconnect(error: nil, reason: "WebSocket probe timeout")
        }
    }

    private func websocketDidDisconnect(error: Error?, reason: String? = nil, reportSendError: Bool = false) {
        guard !closed else { return }
        let failed = webSocketTransport
        webSocketTransport = nil
        wsConnected = false
        failed?.onEvent = nil
        failed?.abort()
        if polling && connected {
            // An optional upgrade candidate may fail without ending a healthy
            // polling connection. Resume both paused write and poll paths.
            probing = false
            fastUpgrade = false
            if !waitingForPost { flushWaitingForPost() }
            flushProbeWait()
            doPoll()
            return
        }
        let message = error?.localizedDescription ?? reason ?? "Socket Disconnected"
        // JS parity: a receive failure on an established connection is a
        // disconnect, not CONNECT_ERROR (which the manager broadcasts to every
        // namespace, including previously refused ones). Opening failures and
        // explicit local send failures still surface the error as well.
        if error != nil && (!connected || reportSendError) {
            client?.engineDidError(reason: message)
        }
        // The disconnect reason is the JS close reason, not the error text —
        // the detail lives in the engineDidError payload above (engine.io-client
        // maps a failed transport to "transport error", a clean close to
        // "transport close").
        closeOutEngine(reason: error != nil ? "transport error" : "transport close")
    }

    /// Polling entry points retain the common implementation and its upgrade barrier.
    open func doPoll() { performPollingRead() }

    open func sendPollMessage(_ message: String, withType type: SocketEnginePacketType,
                              withData datas: [Data], completion: (() -> ())?) {
        performPollingWrite(message, withType: type, withData: datas, completion: completion)
    }

    // Test Properties

    func setConnected(_ value: Bool) {
        connected = value
    }

    func setClosed(_ value: Bool) {
        closed = value
    }

    func setFastUpgrade(_ value: Bool) {
        fastUpgrade = value
    }

    func setMaxPayload(_ value: Int?) {
        maxPayload = value
    }
}

extension SocketEngine {
    // MARK: URLSessionDelegate methods

    /// Delegate called when the session becomes invalid.
    public func URLSession(session: URLSession, didBecomeInvalidWithError error: NSError?) {
        DefaultSocketLogger.Logger.error("Engine URLSession became invalid", type: "SocketEngine")

        didError(reason: "Engine URLSession became invalid")
    }
}

enum EngineError: Error {
    case canceled
}
