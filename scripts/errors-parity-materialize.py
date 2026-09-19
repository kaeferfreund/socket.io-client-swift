from pathlib import Path
R=Path('.')
def edit(p,a,b):
 p=R/p;s=p.read_text();assert a in s,(str(p),a[:150]);p.write_text(s.replace(a,b,1))
p='Source/SocketIO/Engine/SocketEngineClient.swift'
edit(p,'    func engineDidError(reason: String)','''    func engineDidError(reason: String)

    /// Native transport details. Existing delegates may keep the reason-only method.
    @objc optional func engineDidError(reason: String, error: SocketTransportError)''')
edit(p,'    func engineDidClose(reason: String)','''    func engineDidClose(reason: String)

    /// Carries HTTP status/body or WebSocket close metadata without losing the close reason.
    @objc optional func engineDidClose(reason: String, error: SocketTransportError)''')
with (R/p).open('a') as f:f.write('''
/// Structured native counterpart of Engine.IO's TransportError/CloseEvent.
/// Error and disconnect event data retain the reason at index 0 and append this
/// object at index 1. It intentionally has no request URL, cookies or headers.
/// Response text is untrusted, capped at 4 KiB, and never included in description.
public final class SocketTransportError: NSObject, LocalizedError {
    public let transport: String
    public let operation: String
    public let httpStatusCode: Int?
    public let closeCode: Int?
    public let closeReason: String?
    public let responseText: String?
    public let responseTruncated: Bool
    public let underlyingError: Error?

    internal init(transport: String, operation: String, response: HTTPURLResponse? = nil,
                  body: Data? = nil, closeCode: Int? = nil, closeReason: String? = nil,
                  underlyingError: Error? = nil) {
        self.transport = transport
        self.operation = operation
        self.httpStatusCode = response?.statusCode
        self.closeCode = closeCode
        self.closeReason = closeReason
        self.responseText = body.map { String(decoding: $0.prefix(4096), as: UTF8.self) }
        self.responseTruncated = (body?.count ?? 0) > 4096
        self.underlyingError = underlyingError
    }

    public var errorDescription: String? {
        var value = "\\(transport) \\(operation)"
        if let status = httpStatusCode { value += " (HTTP \\(status))" }
        if let code = closeCode { value += " (WebSocket \\(code))" }
        return value
    }
    public override var description: String { errorDescription ?? "Transport error" }
}
''')
p='Source/SocketIO/Engine/SocketEngineSpec.swift'
edit(p,'    func didError(reason: String)','''    func didError(reason: String)

    /// Structured native details, with a source-compatible fallback for custom engines.
    func didError(reason: String, error: SocketTransportError)''')
edit(p,'    public var forceBase64: Bool { false }','''    public var forceBase64: Bool { false }
    public func didError(reason: String, error: SocketTransportError) { didError(reason: reason) }''')
p='Source/SocketIO/Engine/SocketEngine.swift'
edit(p,'''                                flushPollingQueue: Bool = false) {''','''                                flushPollingQueue: Bool = false, error: SocketTransportError? = nil) {''')
edit(p,'''        client?.engineDidClose(reason: reason)
        // The retiring sender''','''        if let error = error, let callback = client?.engineDidClose(reason:error:) {
            callback(reason, error)
        } else {
            client?.engineDidClose(reason: reason)
        }
        // The retiring sender''')
edit(p,'''    /// Disconnects from the server.
''','''    /// Structured transport failure, reported before the corresponding close.
    public func didError(reason: String, error: SocketTransportError) {
        let fail = { [weak self] in
            guard let self = self, !self.closed else { return }
            if let callback = self.client?.engineDidError(reason:error:) {
                callback(reason, error)
            } else {
                self.client?.engineDidError(reason: reason)
            }
            self.closeOutEngine(reason: "transport error", error: error)
        }
        if DispatchQueue.getSpecific(key: engineQueueKey) != nil { fail() }
        else { engineQueue.async(execute: fail) }
    }

    /// Disconnects from the server.
''')
edit(p,'''        let message = error?.localizedDescription ?? reason ?? "Socket Disconnected"''','''        let transportDetail = SocketTransportError(transport: "websocket", operation: "close",
                                          closeCode: closeCode, closeReason: reason, underlyingError: error)
        // A received close frame is a transport close, even if URLSession also
        // completes its outstanding receive with an error. No close frame means
        // a network/handshake failure (or an unclean 1006 close).
        let peerClosed = closeCode.map { $0 >= 1000 && $0 != 1006 } ?? false
        let message = error?.localizedDescription ?? reason ?? "Socket Disconnected"''')
edit(p,'''        if let error = error {
            let native = error as NSError''','''        if let error = error, !peerClosed {
            let native = error as NSError''')
edit(p,'''            client?.engineDidError(reason: reportSendError ? message : detail)''','''            if let callback = client?.engineDidError(reason:error:) {
                callback(reportSendError ? message : detail, transportDetail)
            } else {
                client?.engineDidError(reason: reportSendError ? message : detail)
            }''')
edit(p,'''        closeOutEngine(reason: error != nil ? "transport error" : "transport close")''','''        closeOutEngine(reason: error != nil && !peerClosed ? "transport error" : "transport close",
                       error: transportDetail)''')
p='Source/SocketIO/Engine/SocketEnginePollable.swift'
edit(p,'''                    this.didError(reason: err?.localizedDescription ?? "Error")''','''                    let detail = SocketTransportError(transport: "polling", operation: "read",
                                                      response: res as? HTTPURLResponse, body: data,
                                                      underlyingError: err)
                    this.didError(reason: err?.localizedDescription ?? detail.description, error: detail)''')
edit(p,'''        doRequest(for: req) {[weak self] _, res, err in''','''        doRequest(for: req) {[weak self] data, res, err in''')
edit(p,'''                    this.didError(reason: err?.localizedDescription ?? "Error")''','''                    let detail = SocketTransportError(transport: "polling", operation: "write",
                                                      response: res as? HTTPURLResponse, body: data,
                                                      underlyingError: err)
                    this.didError(reason: err?.localizedDescription ?? detail.description, error: detail)''')
p='Source/SocketIO/Manager/SocketManager.swift'
edit(p,'''    private func _engineDidClose(reason: String) {''','''    public func engineDidClose(reason: String, error: SocketTransportError) {
        handleQueue.async { self._engineDidClose(reason: reason, error: error) }
    }

    private func _engineDidClose(reason: String, error: SocketTransportError? = nil) {''')
edit(p,'''            didDisconnect(reason: reason)
        } else if !reconnecting {''','''            if let error = error {
                forAll { socket in
                    guard socket.status != .notConnected else { return }
                    socket.handleTransportClose(reason: reason, error: error, reconnecting: false)
                }
            } else {
                didDisconnect(reason: reason)
            }
        } else if !reconnecting {''')
edit(p,'''            tryReconnect(reason: reason)''','''            tryReconnect(reason: reason, error: error)''')
edit(p,'''    private func _engineDidError(reason: String) {''','''    public func engineDidError(reason: String, error: SocketTransportError) {
        handleQueue.async { self._engineDidError(reason: reason, error: error) }
    }

    private func _engineDidError(reason: String, error: SocketTransportError? = nil) {''')
edit(p,'''                socket.handleClientEvent(.error, data: [reason])''','''                socket.handleClientEvent(.error, data: error.map { [reason, $0] } ?? [reason])''')
edit(p,'''                socket.handleClientEvent(.connectError, data: [reason])''','''                socket.handleClientEvent(.connectError, data: error.map { [reason, $0] } ?? [reason])''')
edit(p,'''    private func tryReconnect(reason: String) {''','''    private func tryReconnect(reason: String, error: SocketTransportError? = nil) {''')
edit(p,'''            socket.setReconnecting(reason: reason)''','''            socket.handleTransportClose(reason: reason, error: error, reconnecting: true)''')
p='Source/SocketIO/Client/SocketIOClient.swift'
edit(p,'''    /// Called when the client has disconnected from socket.io.
''','''    private var pendingTransportCloseError: SocketTransportError?

    /// Preserves existing public close overrides while attaching detail only to
    /// this notification. Consume it before callbacks, so reentrancy cannot leak it.
    internal func handleTransportClose(reason: String, error: SocketTransportError?, reconnecting: Bool) {
        pendingTransportCloseError = error
        defer { pendingTransportCloseError = nil }
        if reconnecting { setReconnecting(reason: reason) }
        else { didDisconnect(reason: reason) }
    }

    /// Called when the client has disconnected from socket.io.
''')
edit(p,'''        handleClientEvent(.disconnect, data: [reason])
        performOnHandleQueue''','''        let error = pendingTransportCloseError
        pendingTransportCloseError = nil
        handleClientEvent(.disconnect, data: error.map { [reason, $0] } ?? [reason])
        performOnHandleQueue''')
p='Source/SocketIO/Engine/Transport/EngineWebSocketTransport.swift'
edit(p,'internal protocol EngineWebSocketConnection: AnyObject {','''internal protocol EngineWebSocketConnection: AnyObject {
    /// Snapshot before cancellation: a receive failure can precede the close delegate callback.
    var closeDetails: (code: Int?, reason: Data?) { get }''')
with (R/p).open('a') as f:f.write('''
extension EngineWebSocketConnection {
    var closeDetails: (code: Int?, reason: Data?) { (nil, nil) }
}
''')
p='Source/SocketIO/Engine/Transport/WebSocketSessionDelegateProxy.swift'
edit(p,'    internal func start() {','''    internal var closeDetails: (code: Int?, reason: Data?) {
        let code = task.closeCode
        return (code == .invalid ? nil : code.rawValue, task.closeReason)
    }

    internal func start() {''')
p='Source/SocketIO/Engine/Transport/URLSessionWebSocketTransport.swift'
edit(p,'        let oldConnection = connection','''        let oldConnection = connection
        let code = code ?? oldConnection?.closeDetails.code
        let reason = reason ?? oldConnection?.closeDetails.reason''')
