import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security)
import Security
#endif

/// Intercepts trust and lifecycle callbacks without replacing the internal
/// delegate. Server-trust challenges are reserved for the configured policy;
/// an external delegate cannot bypass hostname verification or configured pins.
internal class SocketSessionDelegateProxy: NSObject, URLSessionTaskDelegate {
    internal let tlsConfiguration: SocketTLSConfiguration
    internal weak var forwardingDelegate: URLSessionDelegate?
    internal var onInvalidation: ((URLSession, Error?) -> Void)?

    internal init(tlsConfiguration: SocketTLSConfiguration,
                  forwardingDelegate: URLSessionDelegate?) {
        self.tlsConfiguration = tlsConfiguration
        self.forwardingDelegate = forwardingDelegate
    }

    private func handleTrust(_ challenge: URLAuthenticationChallenge,
                             completion: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) -> Bool {
        #if canImport(Security)
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else { return false }
        if case .systemDefault = tlsConfiguration {
            completion(.performDefaultHandling, nil)
        } else if let trust = challenge.protectionSpace.serverTrust,
                  SocketServerTrustEvaluator.evaluate(trust, host: challenge.protectionSpace.host,
                                                      configuration: tlsConfiguration) {
            completion(.useCredential, URLCredential(trust: trust))
        } else {
            completion(.cancelAuthenticationChallenge, nil)
        }
        return true
        #else
        return false
        #endif
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let once = SocketOnce(completionHandler)
        guard !handleTrust(challenge, completion: { once.call(($0, $1)) }) else { return }
        #if canImport(ObjectiveC)
        if forwardingDelegate?.urlSession?(session, didReceive: challenge,
                                           completionHandler: { once.call(($0, $1)) }) == nil {
            once.call((.performDefaultHandling, nil))
        }
        #else
        if let delegate = forwardingDelegate {
            delegate.urlSession(session, didReceive: challenge, completionHandler: { once.call(($0, $1)) })
        } else { once.call((.performDefaultHandling, nil)) }
        #endif
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let once = SocketOnce(completionHandler)
        guard !handleTrust(challenge, completion: { once.call(($0, $1)) }) else { return }
        #if canImport(ObjectiveC)
        if (forwardingDelegate as? URLSessionTaskDelegate)?.urlSession?(session, task: task, didReceive: challenge,
                                                                       completionHandler: { once.call(($0, $1)) }) == nil {
            once.call((.performDefaultHandling, nil))
        }
        #else
        if let delegate = forwardingDelegate as? URLSessionTaskDelegate {
            delegate.urlSession(session, task: task, didReceive: challenge, completionHandler: { once.call(($0, $1)) })
        } else { once.call((.performDefaultHandling, nil)) }
        #endif
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let once = SocketOnce<URLRequest?>(completionHandler)
        // The redirect response is the current hop. Looking only at the
        // original URL permits http -> https -> http downgrades.
        let secureSchemes = ["https", "wss"]
        let secureOrigin = secureSchemes.contains(response.url?.scheme?.lowercased() ?? "") ||
            secureSchemes.contains(task.originalRequest?.url?.scheme?.lowercased() ?? "")
        let finish: @Sendable (URLRequest?) -> Void = { candidate in
            guard let candidate = candidate else { once.call(nil); return }
            let secureDestination = ["https", "wss"].contains(candidate.url?.scheme?.lowercased() ?? "")
            once.call(secureOrigin && !secureDestination ? nil : candidate)
        }
        #if canImport(ObjectiveC)
        if (forwardingDelegate as? URLSessionTaskDelegate)?.urlSession?(session, task: task,
            willPerformHTTPRedirection: response, newRequest: request, completionHandler: finish) == nil {
            finish(request)
        }
        #else
        if let delegate = forwardingDelegate as? URLSessionTaskDelegate {
            delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                                newRequest: request, completionHandler: finish)
        } else { finish(request) }
        #endif
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        onInvalidation?(session, error)
        #if canImport(ObjectiveC)
        forwardingDelegate?.urlSession?(session, didBecomeInvalidWithError: error)
        #else
        forwardingDelegate?.urlSession(session, didBecomeInvalidWithError: error)
        #endif
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        #if canImport(ObjectiveC)
        (forwardingDelegate as? URLSessionTaskDelegate)?.urlSession?(session, task: task, didCompleteWithError: error)
        #else
        (forwardingDelegate as? URLSessionTaskDelegate)?.urlSession(session, task: task, didCompleteWithError: error)
        #endif
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        #if canImport(ObjectiveC)
        (forwardingDelegate as? URLSessionTaskDelegate)?.urlSession?(session, task: task, didFinishCollecting: metrics)
        #else
        (forwardingDelegate as? URLSessionTaskDelegate)?.urlSession(session, task: task, didFinishCollecting: metrics)
        #endif
    }
}

/// Completion gates must tolerate external delegates invoking them more than once.
// The callback is taken exactly once under the lock, then invoked outside it.
// Callers are responsible for hopping any captured queue-owned state.
internal final class SocketOnce<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: ((Value) -> Void)?
    internal init(_ callback: @escaping (Value) -> Void) { self.callback = callback }
    internal func call(_ value: Value) {
        lock.lock()
        let action = callback
        callback = nil
        lock.unlock()
        action?(value)
    }
}

#if compiler(>=5.5)
extension SocketSessionDelegateProxy: @unchecked Sendable {}
#endif
