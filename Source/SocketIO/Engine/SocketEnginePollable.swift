//
//  SocketEnginePollable.swift
//  Socket.IO-Client-Swift
//
//  Created by Erik Little on 1/15/16.
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

/// Protocol that is used to implement socket.io polling support
public protocol SocketEnginePollable: SocketEngineSpec {
    // MARK: Properties

    /// `true` If engine's session has been invalidated.
    var invalidated: Bool { get }

    /// The maximum number of bytes the server accepts in a single polling POST,
    /// as advertised in the handshake. `nil` when the server does not advertise
    /// a limit, which is always the case on engine.io v3.
    ///
    /// **You should not touch this directly**
    var maxPayload: Int? { get }

    /// A queue of engine.io messages waiting for POSTing
    ///
    /// **You should not touch this directly**
    var postWait: [Post] { get set }

    /// The URLSession that will be used for polling.
    var session: URLSession? { get }

    /// `true` if there is an outstanding poll. Trying to poll before the first is done will cause socket.io to
    /// disconnect us.
    ///
    /// **Do not touch this directly**
    var waitingForPoll: Bool { get set }

    /// `true` if there is an outstanding post. Trying to post before the first is done will cause socket.io to
    /// disconnect us.
    ///
    /// **Do not touch this directly**
    var waitingForPost: Bool { get set }

    // MARK: Methods

    /// Call to send a long-polling request.
    ///
    /// You shouldn't need to call this directly, the engine should automatically maintain a long-poll request.
    func doPoll()

    /// Sends an engine.io message through the polling transport.
    ///
    /// You shouldn't call this directly, instead call the `write` method on `SocketEngine`.
    ///
    /// - parameter message: The message to send.
    /// - parameter withType: The type of message to send.
    /// - parameter withData: The data associated with this message.
    func sendPollMessage(_ message: String, withType type: SocketEnginePacketType, withData datas: [Data], completion: (() -> ())?)

    /// Call to stop polling and invalidate the URLSession.
    func stopPolling()
}

// Default polling methods
extension SocketEnginePollable {
    /// A server that advertises no limit imposes none on us.
    public var maxPayload: Int? {
        return nil
    }

    /// How many of the queued packets fit into a single POST.
    ///
    /// engine.io v4 servers advertise a `maxPayload` in the handshake and answer
    /// a POST that exceeds it with HTTP 413, discarding every packet it carried.
    /// The reference implementation therefore batches only as many packets as
    /// fit and leaves the rest for the next POST (`getWritablePackets()` in
    /// engine.io-client). A single packet larger than the limit is still sent on
    /// its own: it cannot be split, and sending it is what the reference client
    /// does too.
    func writablePostWaitPrefixCount() -> Int {
        return writablePrefixCount(of: postWait)
    }

    /// The same slicing applied to an arbitrary queue — used by the graceful
    /// close, which batches a queue it has already detached from the engine.
    /// Always at least 1 for a non-empty queue, so a caller can drain by
    /// repeatedly taking the prefix.
    func writablePrefixCount(of pending: [Post]) -> Int {
        guard let maxPayload = maxPayload, version.rawValue >= 3, pending.count > 1 else {
            return pending.count
        }

        var payloadSize = 0

        for (i, packet) in pending.enumerated() {
            payloadSize += packet.msg.utf8.count

            if i > 0 && payloadSize > maxPayload {
                return i
            }

            payloadSize += 1 // The record separator that precedes the next packet.
        }

        return pending.count
    }

    /// Detaches the bounded batch before invoking callbacks, which may re-enter
    /// the engine. Only packets actually selected for this request are completed.
    func createRequestForPostWithPostWait() -> URLRequest {
        let (request, completions) = takePostBatch()
        for completion in completions { completion() }
        return request
    }

    /// Selects a batch without entering user code. Production starts its POST
    /// before delivering these local callbacks, so a callback cannot overtake it.
    private func takePostBatch() -> (URLRequest, [() -> Void]) {
        let sending = Array(postWait.prefix(writablePostWaitPrefixCount()))
        postWait.removeFirst(sending.count)
        return (createRequestForPost(with: sending.map { $0.msg }), sending.compactMap { $0.completion })
    }

    /// Encodes explicit wire packets without draining the application queue.
    /// Used by normal batches and the close-only request for a retiring session.
    func createRequestForPost(with messages: [String]) -> URLRequest {
        let postStr: String
        if version.rawValue >= 3 {
            postStr = messages.joined(separator: "\u{1e}")
        } else {
            postStr = messages.map { "\($0.utf16.count):\($0)" }.joined()
        }
        DefaultSocketLogger.Logger.log("Created POST string: \(postStr)", type: "SocketEnginePolling")
        let postData = Data(postStr.utf8)
        var req = URLRequest(url: urlPollingWithSid)
        addHeaders(to: &req)
        req.httpMethod = "POST"
        req.setValue("text/plain; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = postData
        req.setValue(String(postData.count), forHTTPHeaderField: "Content-Length")
        return req
    }

    /// Whether the paused polling transport may now send the upgrade packet.
    ///
    /// Engine.IO requires the current transport to be PAUSED before upgrading.
    /// A POST still on the wire would reach the server after it switched to
    /// WebSocket, and the server answers such a late POST with HTTP 400. That
    /// response is then discarded (`polling` is already `false` by then) and the
    /// packet is never resent, so its payload is lost without any error. The
    /// reference implementation waits for both the poll and the write to settle
    /// (`pause()` in engine.io-client's polling transport); this mirrors it.
    var canSendUpgradePacket: Bool {
        fastUpgrade && !waitingForPoll && !waitingForPost
    }

    /// Call to send a long-polling request.
    ///
    /// You shouldn't need to call this directly, the engine should automatically maintain a long-poll request.
    public func doPoll() { performPollingRead() }

    func performPollingRead() {
        guard polling && !waitingForPoll && connected && !closed && !fastUpgrade else { return }

        var req = URLRequest(url: urlPollingWithSid)
        addHeaders(to: &req)

        doLongPoll(for: req)
    }

    /// Starts a request for the current polling session and rejects stale callbacks.
    /// Actual POST completion also releases that session's graceful-close barrier.
    func doRequest(for req: URLRequest, callbackWith callback: @escaping (Data?, URLResponse?, Error?) -> ()) {
        guard polling && !closed && !invalidated && !fastUpgrade else { return }
        // The engine object is reused across reconnects (`resetEngine` swaps in a NEW
        // URLSession), while an invalidated session still lets in-flight tasks finish.
        // Bind each request to the session it was issued on, so a late response (e.g.
        // the pre-timeout handshake) cannot reach the new session's state. JS gets this
        // by creating a fresh transport per attempt.

        DefaultSocketLogger.Logger.log("Doing polling \(req.httpMethod ?? "") \(req)", type: "SocketEnginePolling")

        guard let requestSession = session else { return }
        // Capture the concrete attempt's barrier, not the engine's future one.
        let postGroup = req.httpMethod == "POST" ? (self as? SocketEngine)?.pollingPostGroup : nil
        postGroup?.enter()
        requestSession.dataTask(with: req) { [weak self, weak requestSession] data, response, error in
            defer { postGroup?.leave() }
            guard let self = self else { return }
            self.engineQueue.async { [weak self, weak requestSession] in
                guard let self = self, let requestSession = requestSession,
                      self.session === requestSession, !self.closed, !self.invalidated else { return }
                callback(data, response, error)
            }
        }.resume()
    }

    func doLongPoll(for req: URLRequest) {
        waitingForPoll = true

        doRequest(for: req) {[weak self] data, res, err in
            guard let this = self, this.polling, !this.closed else { return }
            guard let data = data, let res = res as? HTTPURLResponse, res.statusCode == 200 else {
                if let err = err {
                    DefaultSocketLogger.Logger.error(err.localizedDescription, type: "SocketEnginePolling")
                } else {
                    DefaultSocketLogger.Logger.error("Error during long poll request", type: "SocketEnginePolling")
                }

                if this.polling && !this.closed {
                    this.didError(reason: err?.localizedDescription ?? "Error")
                }

                return
            }

            DefaultSocketLogger.Logger.log("Got polling response", type: "SocketEnginePolling")

            if let str = String(data: data, encoding: .utf8) {
                this.parsePollingMessage(str)
            }

            this.waitingForPoll = false

            if this.fastUpgrade {
                // Deferred while a POST is in flight; the POST callback upgrades then.
                if this.canSendUpgradePacket {
                    this.doFastUpgrade()
                }
            } else if !this.closed && this.polling {
                this.doPoll()
            }
        }
    }

    func flushWaitingForPost() {
        guard !postWait.isEmpty, connected, !closed, !invalidated, !waitingForPost else { return }
        guard polling else {
            flushWaitingForPostToWebSocket()

            return
        }
        // A pending upgrade stops polling writes: `doRequest` refuses them, so the
        // request below would never start while still marking the transport as
        // writing — and the deferred upgrade would then wait forever. The queued
        // packets leave over the WebSocket in `doFastUpgrade` instead.
        guard !fastUpgrade else { return }

        guard session != nil else { return }
        waitingForPost = true
        let (req, completions) = takePostBatch()

        DefaultSocketLogger.Logger.log("POSTing", type: "SocketEnginePolling")

        doRequest(for: req) {[weak self] _, res, err in
            guard let this = self, !this.closed else { return }
            guard let res = res as? HTTPURLResponse, res.statusCode == 200 else {
                if let err = err {
                    DefaultSocketLogger.Logger.error(err.localizedDescription, type: "SocketEnginePolling")
                } else {
                    DefaultSocketLogger.Logger.error("Error flushing waiting posts", type: "SocketEnginePolling")
                }

                if this.polling && !this.closed {
                    this.didError(reason: err?.localizedDescription ?? "Error")
                }

                return
            }

            this.waitingForPost = false

            if this.fastUpgrade {
                // The write settled, so a transport paused for the upgrade may go on.
                if this.canSendUpgradePacket {
                    this.doFastUpgrade()
                }
            } else {
                this.flushWaitingForPost()
                this.doPoll()
            }
        }
        // doRequest has now entered the concrete session's POST group. A
        // reentrant disconnect/emit can neither overlap nor bypass this write.
        for completion in completions { completion() }
    }

    func parsePollingMessage(_ str: String) {
        guard !str.isEmpty else { return }

        DefaultSocketLogger.Logger.log("Got poll message: \(str)", type: "SocketEnginePolling")

        if version.rawValue >= 3 {
            let records = str.components(separatedBy: "\u{1e}")

            for record in records {
                guard !closed else { break }
                parseEngineMessage(record)
            }
        } else {
            guard str.count != 1 else {
                parseEngineMessage(str)

                return
            }

            var reader = SocketStringReader(message: str)

            while reader.hasNext && !closed {
                let length = reader.readUntilOccurence(of: ":")
                guard !length.isEmpty, length.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                      let count = Int(length), count > 0, reader.hasNext,
                      let packet = reader.readSafely(count: count) else {
                    didError(reason: "Invalid Engine.IO 3 polling payload length")
                    return
                }
                parseEngineMessage(packet)
            }
        }
    }

    /// Sends an engine.io message through the polling transport.
    ///
    /// You shouldn't call this directly, instead call the `write` method on `SocketEngine`.
    ///
    /// - parameter message: The message to send.
    /// - parameter withType: The type of message to send.
    /// - parameter withData: The data associated with this message.
    /// - parameter completion: Callback called on transport write completion.
    public func sendPollMessage(_ message: String, withType type: SocketEnginePacketType, withData datas: [Data], completion: (() -> ())? = nil) {
        performPollingWrite(message, withType: type, withData: datas, completion: completion)
    }

    func performPollingWrite(_ message: String, withType type: SocketEnginePacketType, withData datas: [Data], completion: (() -> ())?) {
        DefaultSocketLogger.Logger.log("Sending poll: \(message) as type: \(type.rawValue)", type: "SocketEnginePolling")

        postWait.append((String(type.rawValue) + message, completion))

        for data in datas {
            if case let .right(bin) = createBinaryDataForSend(using: data) {
                postWait.append((bin, {}))
            }
        }

        if !waitingForPost {
            flushWaitingForPost()
        }
    }
}
