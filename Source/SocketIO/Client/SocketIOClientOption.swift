//
//  SocketIOClientOption .swift
//  Socket.IO-Client-Swift
//
//  Created by Erik Little on 10/17/15.
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

/// The socket.io version being used.
public enum SocketIOVersion: Int {
    /// socket.io 2, engine.io 3
    case two = 2

    /// socket.io 3, engine.io 4
    case three = 3
}

protocol ClientOption : CustomStringConvertible, Equatable {
    func getSocketIOOptionValue() -> Any
}

/// The options for a client.
public enum SocketIOClientOption : ClientOption {
    /// The default timeout in seconds used when waiting for an acknowledgement
    /// from `emit(_:_:ack:)` / `emit(_:with:ack:)`. `nil` (unset) means no
    /// default — a plain ack that never times out. JS-aligned with the
    /// `ackTimeout` (milliseconds) option in `socket.io-client/lib/socket.ts`.
    case ackTimeout(Double)

    /// Whether the manager should automatically call `connect()` at the end of `init`.
    /// Default `false` to preserve existing behavior. JS `Manager` defaults to `true`;
    /// Swift inverts the default. When `true`, only the `defaultSocket` is auto-CONNECTed
    /// through `_engineDidOpen`. Sockets created later via `manager.socket(forNamespace:)`
    /// still require an explicit `socket.connect()` — matches JS where `Manager.autoConnect`
    /// only opens the engine, not arbitrary namespaces.
    /// **Note:** when `true`, engine I/O begins before `SocketManager.init` returns.
    /// Listener attachment on `defaultSocket` happens AFTER init in user code; events
    /// fire asynchronously on the configured `handleQueue` so they do reach attached
    /// listeners, but be aware of the ordering. JS-aligned with `Manager` constructor.
    case autoConnect(Bool)

    /// Legacy option. Fails connection validation because native compression controls are unavailable.
    case compress

    /// How many times an emit is re-sent when the server does not acknowledge
    /// it in time, JS-aligned with the `retries` option in
    /// `socket.io-client/lib/socket.ts`. Default `0` (retries disabled).
    ///
    /// When set, every event emit (plain, err-first ack, and
    /// `timeout(after:).emit`) goes through an ordered queue: each attempt
    /// waits `ackTimeout` (or the per-emit `timeout(after:)`) for the ack and
    /// is re-sent on failure until the budget is exhausted, in strict queue
    /// order. The final ack callback then fires with `SocketAckError.timeout`.
    ///
    /// Plain `emit` / `send` calls without a user acknowledgement callback require
    /// a finite, non-negative `ackTimeout` when retries are enabled. Otherwise
    /// the emit is rejected before queueing or sending, emits `.error` with
    /// `[eventName, items, NSError]` (domain `SocketIO.Emit`, code `2`), and invokes
    /// its local completion asynchronously, if provided. Zero is a valid timeout.
    /// Explicit acknowledgement APIs retain their existing no-timeout behavior.
    /// The server must acknowledge retried events even without a user callback.
    case retries(Int)

    /// A dictionary of GET parameters that will be included in the connect url.
    case connectParams([String: Any])

    /// Seconds the engine.io handshake may take before the attempt is failed with `.connectError("timeout")`
    /// and the engine is closed. Default `20`, JS-aligned with `Manager`'s `timeout` option
    /// (`socket.io-client/lib/manager.ts`). `.infinity` disables the timeout.
    case connectTimeout(Double)

    /// An array of cookies that will be sent during the initial connection.
    case cookies([HTTPCookie])

    /// Any extra HTTP headers that should be sent during the initial connection.
    case extraHeaders([String: String])

    /// If passed `true`, will cause the client to always create a new engine. Useful for debugging,
    /// or when you want to be sure no state from previous engines is being carried over.
    case forceNew(Bool)

    /// If passed `true`, the only transport that will be used will be HTTP long-polling.
    case forcePolling(Bool)

    /// If passed `true`, the only transport that will be used will be WebSockets.
    case forceWebsockets(Bool)

    /// Legacy option. `true` fails before connecting; it never silently bypasses the requested proxy.
    case enableSOCKSProxy(Bool)

    /// The queue that all interaction with the client should occur on. This is the queue that event handlers are
    /// called on.
    ///
    /// **This should be a serial queue! Concurrent queues are not supported and might cause crashes and races**.
    case handleQueue(DispatchQueue)

    /// If passed `true`, the client will log debug information. This should be turned off in production code.
    case log(Bool)

    /// Used to pass in a custom logger.
    case logger(SocketLogger)

    /// A custom path to socket.io. Only use this if the socket.io server is configured to look for this path.
    case path(String)

    /// If passed `false`, the client will not reconnect when it loses connection. Useful if you want full control
    /// over when reconnects happen.
    case reconnects(Bool)

    /// The number of times to try and reconnect before giving up. Pass `-1` to [never give up](https://www.youtube.com/watch?v=dQw4w9WgXcQ).
    case reconnectAttempts(Int)

    /// The minimum number of seconds to wait before reconnect attempts.
    case reconnectWait(Int)

    /// The maximum number of seconds to wait before reconnect attempts.
    case reconnectWaitMax(Int)

    /// The randomization factor for calculating reconnect jitter.
    case randomizationFactor(Double)

    /// Set `true` if your server is using secure transports.
    case secure(Bool)

    /// Whether to add a cache-busting timestamp query parameter with each
    /// transport request. `nil` (default, JS `timestampRequests` unset):
    /// polling requests carry it, WebSocket URLs do not. `true`: both carry
    /// it. `false`: neither does. JS-aligned with `timestampRequests` in
    /// engine.io-client (`Polling.uri()` vs `WS.uri()`).
    case timestampRequests(Bool)

    /// The query parameter name used for the cache-busting timestamp.
    /// Default `"t"`. JS-aligned with `timestampParam` in engine.io-client.
    case timestampParam(String)

    /// Shared native TLS policy for polling and WebSocket. Normal system trust is the default.
    case security(SocketTLSConfiguration)

    /// Legacy option. `true` fails; use an explicit customTrust anchor instead of trust-all.
    case selfSigned(Bool)

    /// Forwards authentication (except server trust), redirect, lifecycle and metrics events.
    /// Server trust is always controlled by `security`, never by this delegate.
    case sessionDelegate(URLSessionDelegate)

    /// Deprecated compatibility option. Both values use native URLSession.
    @available(*, deprecated, message: "URLSession is the only WebSocket backend; remove this option")
    case useCustomEngine(Bool)

    /// Native incoming-message and outgoing-queue limits.
    case webSocketOptions(SocketWebSocketOptions)

    /// Complete incoming packet, attachment-count and nesting limits for all transports.
    case parserOptions(SocketParserOptions)

    /// Pipeline-wide buffer/queue limits: send buffer, retry queue, recovery
    /// replay, engine-to-manager handoff, polling response body and binary
    /// reconstruction deadline. Everything is unlimited by default, which is
    /// the JavaScript behaviour.
    case bufferLimits(SocketBufferLimits)

    /// Carries a dictionary conversion failure to connection validation. No
    /// network request is started when this option is present.
    case invalidConfiguration(String)

    /// The version of socket.io being used. This should match the server version. Default is 3.
    case version(SocketIOVersion)

    // MARK: Properties

    /// The description of this option.
    public var description: String {
        let description: String

        switch self {
        case .webSocketOptions:
            description = "webSocketOptions"
        case .parserOptions:
            description = "parserOptions"
        case .bufferLimits:
            description = "bufferLimits"
        case .version:
            description = "version"
        case .invalidConfiguration:
            description = "invalidConfiguration"
        case .ackTimeout:
            description = "ackTimeout"
        case .autoConnect:
            description = "autoConnect"
        case .compress:
            description = "compress"
        case .retries:
            description = "retries"
        case .connectParams:
            description = "connectParams"
        case .connectTimeout:
            description = "connectTimeout"
        case .cookies:
            description = "cookies"
        case .extraHeaders:
            description = "extraHeaders"
        case .forceNew:
            description = "forceNew"
        case .forcePolling:
            description = "forcePolling"
        case .forceWebsockets:
            description = "forceWebsockets"
        case .handleQueue:
            description = "handleQueue"
        case .log:
            description = "log"
        case .logger:
            description = "logger"
        case .path:
            description = "path"
        case .reconnects:
            description = "reconnects"
        case .reconnectAttempts:
            description = "reconnectAttempts"
        case .reconnectWait:
            description = "reconnectWait"
        case .reconnectWaitMax:
            description = "reconnectWaitMax"
        case .randomizationFactor:
            description = "randomizationFactor"
        case .secure:
            description = "secure"
        case .timestampRequests:
            description = "timestampRequests"
        case .timestampParam:
            description = "timestampParam"
        case .selfSigned:
            description = "selfSigned"
        case .security:
            description = "security"
        case .sessionDelegate:
            description = "sessionDelegate"
        case .enableSOCKSProxy:
            description = "enableSOCKSProxy"
        case .useCustomEngine:
            description = "customEngine"
        }

        return description
    }

    func getSocketIOOptionValue() -> Any {
        let value: Any

        switch self {
        case let .webSocketOptions(options):
            value = options
        case let .parserOptions(options):
            value = options
        case let .bufferLimits(limits):
            value = limits
        case let .version(versionNum):
            value = versionNum
        case let .invalidConfiguration(reason):
            value = reason
        case let .ackTimeout(timeout):
            value = timeout
        case let .autoConnect(autoConnect):
            value = autoConnect
        case .compress:
            value = true
        case let .connectParams(params):
            value = params
        case let .retries(count):
            value = count
        case let .connectTimeout(timeout):
            value = timeout
        case let .cookies(cookies):
            value = cookies
        case let .extraHeaders(headers):
            value = headers
        case let .forceNew(force):
            value = force
        case let .forcePolling(force):
            value = force
        case let .forceWebsockets(force):
            value = force
        case let .handleQueue(queue):
            value = queue
        case let .log(log):
            value = log
        case let .logger(logger):
            value = logger
        case let .path(path):
            value = path
        case let .reconnects(reconnects):
            value = reconnects
        case let .reconnectAttempts(attempts):
            value = attempts
        case let .reconnectWait(wait):
            value = wait
        case let .reconnectWaitMax(wait):
            value = wait
        case let .randomizationFactor(factor):
            value = factor
        case let .secure(secure):
            value = secure
        case let .timestampRequests(timestampRequests):
            value = timestampRequests
        case let .timestampParam(timestampParam):
            value = timestampParam
        case let .security(security):
            value = security
        case let .selfSigned(signed):
            value = signed
        case let .sessionDelegate(delegate):
            value = delegate
        case let .enableSOCKSProxy(enable):
            value = enable
        case let .useCustomEngine(enable):
            value = enable
        }

        return value
    }

    // MARK: Operators

    /// Compares whether two options are the same.
    ///
    /// - parameter lhs: Left operand to compare.
    /// - parameter rhs: Right operand to compare.
    /// - returns: `true` if the two are the same option.
    public static func ==(lhs: SocketIOClientOption, rhs: SocketIOClientOption) -> Bool {
        return lhs.description == rhs.description
    }

}
