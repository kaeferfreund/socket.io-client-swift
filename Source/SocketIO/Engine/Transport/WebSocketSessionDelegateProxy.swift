import Dispatch
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension URLSessionWebSocketTransport {
    /// Owns a session independent of the polling session. The supplied request
    /// carries headers/cookies prepared by the engine; this adapter never rewrites
    /// them. Uses system TLS validation only. Custom trust/delegate integration is
    /// deliberately NOT wired into SocketEngine in this foundational change.
    internal convenience init(request: URLRequest,
                              queue: DispatchQueue,
                              configuration: URLSessionConfiguration = .default,
                              maximumMessageSize: Int = 16 * 1024 * 1024,
                              maximumPendingBytes: Int = URLSessionWebSocketTransport.defaultMaximumPendingBytes,
                              maximumPendingBatches: Int = URLSessionWebSocketTransport.defaultMaximumPendingBatches,
                              maximumPendingMessages: Int = URLSessionWebSocketTransport.defaultMaximumPendingMessages) {
        precondition(maximumMessageSize > 0)
        let snapshot = configuration.copy() as! URLSessionConfiguration
        self.init(queue: queue, maximumPendingBytes: maximumPendingBytes,
                  maximumPendingBatches: maximumPendingBatches,
                  maximumPendingMessages: maximumPendingMessages) {
            URLSessionWebSocketConnection(request: request, queue: queue,
                                          configuration: snapshot,
                                          maximumMessageSize: maximumMessageSize)
        }
    }
}

/// Owns one concrete session/task pair. All mutable state is engine-queue confined.
/// Foundation completion closures do not mutate it; delegate callbacks hop onto
/// that queue through a weak proxy before validating session AND task identity.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
internal final class URLSessionWebSocketConnection: EngineWebSocketConnection {
    internal var onEvent: ((EngineWebSocketEvent) -> Void)?
    fileprivate let queue: DispatchQueue
    private let request: URLRequest
    private let configuration: URLSessionConfiguration
    private let maximumMessageSize: Int
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var started = false

    internal init(request: URLRequest, queue: DispatchQueue,
                  configuration: URLSessionConfiguration, maximumMessageSize: Int) {
        self.request = request
        self.queue = queue
        self.configuration = configuration
        self.maximumMessageSize = maximumMessageSize
    }

    internal func start() {
        guard !started else { return }
        started = true
        let proxy = WebSocketSessionDelegateProxy(owner: self)
        let session = URLSession(configuration: configuration, delegate: proxy, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = maximumMessageSize
        self.session = session
        self.task = task
        task.resume()
    }

    internal func send(_ message: EngineWebSocketMessage, completion: @escaping (Error?) -> Void) {
        guard let task = task else {
            completion(EngineWebSocketError.notOpen)
            return
        }
        let payload: URLSessionWebSocketTask.Message
        switch message {
        case .text(let text): payload = .string(text)
        case .binary(let data): payload = .data(data)
        }
        #if canImport(FoundationNetworking)
        // swift-corelibs-foundation exposes the async API rather than Apple's
        // completion-handler overload. This branch supports isolated Linux tests.
        Task {
            do { try await task.send(payload); completion(nil) }
            catch { completion(error) }
        }
        #else
        task.send(payload, completionHandler: completion)
        #endif
    }

    internal func receive(completion: @escaping (Result<EngineWebSocketMessage, Error>) -> Void) {
        guard let task = task else {
            completion(.failure(EngineWebSocketError.notOpen))
            return
        }
        let deliver: (Result<URLSessionWebSocketTask.Message, Error>) -> Void = { result in
            completion(result.flatMap { message in
                switch message {
                case .string(let text): return .success(.text(text))
                case .data(let data): return .success(.binary(data))
                @unknown default: return .failure(EngineWebSocketError.unsupportedMessage)
                }
            })
        }
        #if canImport(FoundationNetworking)
        Task {
            do { deliver(.success(try await task.receive())) }
            catch { deliver(.failure(error)) }
        }
        #else
        task.receive(completionHandler: deliver)
        #endif
    }

    internal func close(code: Int, reason: Data?) {
        guard let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) else {
            cancel()
            return
        }
        task?.cancel(with: closeCode, reason: reason)
        session?.finishTasksAndInvalidate()
        task = nil
        session = nil
    }

    internal func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
    }

    deinit { session?.invalidateAndCancel() }

    fileprivate func matches(_ session: URLSession, _ task: URLSessionTask? = nil) -> Bool {
        guard self.session === session else { return false }
        return task == nil || self.task === task
    }

    fileprivate func opened(_ session: URLSession, _ task: URLSessionWebSocketTask, _ protocolName: String?) {
        guard matches(session, task) else { return }
        onEvent?(.opened(protocol: protocolName))
    }

    fileprivate func closed(_ session: URLSession, _ task: URLSessionWebSocketTask,
                            _ code: URLSessionWebSocketTask.CloseCode, _ reason: Data?) {
        guard matches(session, task) else { return }
        onEvent?(.closed(code: code.rawValue, reason: reason, error: nil))
    }

    fileprivate func completed(_ session: URLSession, _ task: URLSessionTask, _ error: Error?) {
        guard matches(session, task) else { return }
        let code = self.task?.closeCode
        onEvent?(.closed(code: code == .invalid ? nil : code?.rawValue,
                         reason: self.task?.closeReason, error: error))
    }

    fileprivate func invalidated(_ session: URLSession, _ error: Error?) {
        guard matches(session) else { return }
        onEvent?(.closed(code: nil, reason: nil, error: error))
    }
}

/// URLSession retains its delegate; the proxy must not retain the connection.
/// No custom authentication handler is installed, so Foundation performs normal
/// platform trust evaluation. A future policy proxy must cover polling as well.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
internal final class WebSocketSessionDelegateProxy: NSObject, URLSessionWebSocketDelegate {
    private weak var owner: URLSessionWebSocketConnection?

    internal init(owner: URLSessionWebSocketConnection) { self.owner = owner }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocolName: String?) {
        owner?.queue.async { [weak owner] in owner?.opened(session, webSocketTask, protocolName) }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        owner?.queue.async { [weak owner] in owner?.closed(session, webSocketTask, closeCode, reason) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        owner?.queue.async { [weak owner] in owner?.completed(session, task, error) }
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        owner?.queue.async { [weak owner] in owner?.invalidated(session, error) }
    }
}

#if compiler(>=5.5)
// owner is assigned only during initialization and held weakly. Delegate methods
// only enqueue work; connection state is accessed exclusively on its serial queue.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension WebSocketSessionDelegateProxy: @unchecked Sendable {}
#endif
