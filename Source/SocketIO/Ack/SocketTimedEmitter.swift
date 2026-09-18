//
//  SocketTimedEmitter.swift
//  Socket.IO-Client-Swift
//
//  Phase 9: per-emit ack with typed SocketAckError.
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

import Foundation

/// A chainable handle returned from `SocketIOClient.timeout(after:)` that emits
/// an event with a typed-error per-emit ack callback.
///
/// JS analogue: `socket.timeout(2000).emit("ev", arg, (err, data) => ...)`.
///
/// Usage:
/// ```swift
/// socket.timeout(after: 2).emit("ping") { err, data in
///     if let err = err as? SocketAckError { /* .timeout or .disconnected */ }
///     else { /* server ack data in `data` */ }
/// }
/// ```
///
/// **Threading:** the underlying registration runs on
/// `socket.manager.handleQueue`, so the timer is scheduled before the emit
/// funnel is invoked. This means a disconnected emit still fires `.timeout`
/// after `seconds` — matching JS `_registerAckCallback` semantics.
public struct SocketTimedEmitter {
    let socket: SocketIOClient
    let timeout: Double

    /// Variadic callback overload.
    public func emit(_ event: String, _ items: SocketData...,
                     ack: @escaping (Error?, [Any]) -> Void) {
        emit(event, with: items, ack: ack)
    }

    /// Array callback overload.
    public func emit(_ event: String, with items: [SocketData],
                     ack: @escaping (Error?, [Any]) -> Void) {
        socket.emitTimed(event: event, items: items, timeout: timeout, ack: ack)
    }

    /// Variadic async/throws overload.
    public func emit(_ event: String, _ items: SocketData...) async throws -> [Any] {
        return try await emit(event, with: items)
    }

    /// Array async/throws overload.
    ///
    /// Throws `SocketAckError.timeout` / `.disconnected` for the corresponding
    /// fire reasons, or `CancellationError` if the awaiting `Task` is cancelled
    /// before the ack arrives.
    public func emit(_ event: String, with items: [SocketData]) async throws -> [Any] {
        // The token is set synchronously by cancellation, even if cancellation
        // arrives before emitTimed's queue block. ID allocation and registration
        // happen together on handleQueue; no actor/executor mutates currentAck.
        let state = SocketAsyncAckState()
        let socket = self.socket
        // `onCancel` is @Sendable and `SocketIOClient` is not: the box carries the
        // reference across that boundary, and the socket is only ever touched on
        // its manager's serial handleQueue.
        let boxed = SocketUncheckedSendableBox(socket)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                socket.emitTimed(event: event, items: items, timeout: timeout, cancellation: state) { error, data in
                    if let error = error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: data) }
                }
            }
        } onCancel: {
            state.cancel()
            boxed.value.manager?.handleQueue.async {
                if let id = state.registeredID {
                    boxed.value.ackHandlers.cancelTimedAck(id, fireWith: CancellationError())
                }
            }
        }
    }
}

/// Bridges Task cancellation to the serial ack registry. Only this tiny state
/// crosses executors; the socket and its ack IDs remain handleQueue-confined.
internal final class SocketAsyncAckState {
    private let lock = NSLock()
    private var cancelled = false
    private var id: Int?
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    var registeredID: Int? { lock.lock(); defer { lock.unlock() }; return id }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func register(_ id: Int) { lock.lock(); self.id = id; lock.unlock() }
}
#if compiler(>=5.5)
extension SocketAsyncAckState: @unchecked Sendable {}
#endif

/// Carries a handleQueue-confined reference across a `@Sendable` boundary.
/// Correctness relies on the caller dispatching to that queue, not on the box.
internal struct SocketUncheckedSendableBox<Value> {
    let value: Value
    init(_ value: Value) { self.value = value }
}
#if compiler(>=5.5)
extension SocketUncheckedSendableBox: @unchecked Sendable {}
#endif
