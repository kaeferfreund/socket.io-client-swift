from pathlib import Path
R=Path('.')
def edit(p,a,b):
 p=R/p; s=p.read_text(); assert a in s,(p,a[:100]); p.write_text(s.replace(a,b,1))
p='Source/SocketIO/Client/SocketIOClientOption.swift'
edit(p,'    case cookies([HTTPCookie])','''    case cookies([HTTPCookie])

    /// Accept and resend server cookies in an isolated, engine-owned cookie jar.
    /// Default false, like JS withCredentials. Explicit cookies/headers remain explicit.
    case withCredentials(Bool)

    /// Encode binary WebSocket messages as Engine.IO base64 text. Polling always does so.
    case forceBase64(Bool)

    /// Append a trailing slash to the transport path. Default true, like JS.
    case addTrailingSlash(Bool)''')
edit(p,'        case .cookies:\n','''        case .withCredentials:
            description = "withCredentials"
        case .forceBase64:
            description = "forceBase64"
        case .addTrailingSlash:
            description = "addTrailingSlash"
        case .cookies:
''')
edit(p,'        case let .cookies(cookies):\n','''        case let .withCredentials(enabled):
            value = enabled
        case let .forceBase64(enabled):
            value = enabled
        case let .addTrailingSlash(enabled):
            value = enabled
        case let .cookies(cookies):
''')
p='Source/SocketIO/Util/SocketExtensions.swift'
edit(p,'        case let ("cookies", cookies as [HTTPCookie]):','''        case let ("withCredentials", enabled as Bool):
            return .withCredentials(enabled)
        case let ("forceBase64", enabled as Bool):
            return .forceBase64(enabled)
        case let ("addTrailingSlash", enabled as Bool):
            return .addTrailingSlash(enabled)
        case let ("cookies", cookies as [HTTPCookie]):''')
edit(p,'        case ("parserOptions", _):','''        case ("withCredentials", _), ("forceBase64", _), ("addTrailingSlash", _):
            return .invalidConfiguration("invalid value for " + key + "; expected Bool")
        case ("parserOptions", _):''')
p='Source/SocketIO/Engine/SocketEngineSpec.swift'
edit(p,'    var cookies: [HTTPCookie]? { get }','''    var cookies: [HTTPCookie]? { get }

    /// Whether binary WebSocket payloads must use Engine.IO base64 text.
    var forceBase64: Bool { get }''')
edit(p,'extension SocketEngineSpec {','''extension SocketEngineSpec {
    /// Existing custom engines retain their historical binary transport behaviour.
    public var forceBase64: Bool { false }
''')
edit(p,'        if polling {\n            return .right(prefixB64','        if polling || forceBase64 {\n            return .right(prefixB64')
p='Source/SocketIO/Engine/SocketEngine.swift'
edit(p,'    private var configurationError: String?','''    private var configurationError: String?

    /// Server cookies are opt-in and never use the application's shared cookie store.
    public private(set) var withCredentials = false
    public private(set) var forceBase64 = false
    public private(set) var addTrailingSlash = true
    /// Kept across reconnects and polling-to-WebSocket upgrades, not across engines.
    internal let credentialCookieStorage = URLSessionConfiguration.ephemeral.httpCookieStorage''')
edit(p,'urlWebSocket.percentEncodedQuery = "transport=websocket" + suffix + engineIOParam','urlWebSocket.percentEncodedQuery = "transport=websocket" + (forceBase64 ? "&b64=1" : "") + suffix + engineIOParam')
edit(p,'''        addHeaders(to: &request, includingCookies:
            session?.configuration.httpCookieStorage?.cookies(for: urlPollingWithSid))''','''        addHeaders(to: &request, includingCookies:
            withCredentials ? credentialCookieStorage?.cookies(for: urlPollingWithSid) : nil)''')
edit(p,'''            request: request, queue: engineQueue,
            tlsConfiguration:''','''            request: request, queue: engineQueue,
            configuration: .ephemeral,
            tlsConfiguration:''')
edit(p,'''                case .opened(_, let headers):
                    self.wsConnected = true''','''                case .opened(_, let headers):
                    if self.withCredentials {
                        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: self.urlPolling)
                        self.credentialCookieStorage?.setCookies(cookies, for: self.urlPolling, mainDocumentURL: nil)
                    }
                    self.wsConnected = true''')
edit(p,'''        messages += data.map { .binary(version.rawValue >= 3 ? $0 : Data([0x4]) + $0) }''','''        messages += data.map {
            if forceBase64 {
                return .text((version.rawValue >= 3 ? "b" : "b4") + $0.base64EncodedString())
            }
            return .binary(version.rawValue >= 3 ? $0 : Data([0x4]) + $0)
        }''')
edit(p,'''        session = Foundation.URLSession(configuration: pollingSessionConfigurationFactory(),
                                        delegate: proxy, delegateQueue: queue)''','''        let configuration = pollingSessionConfigurationFactory()
        configuration.httpCookieStorage = withCredentials ? credentialCookieStorage : nil
        configuration.httpShouldSetCookies = withCredentials
        configuration.httpCookieAcceptPolicy = withCredentials ? .always : .never
        session = Foundation.URLSession(configuration: configuration,
                                        delegate: proxy, delegateQueue: queue)''')
edit(p,'''            case let .cookies(cookies):
                self.cookies = cookies''','''            case let .cookies(cookies):
                self.cookies = cookies
            case let .withCredentials(enabled):
                withCredentials = enabled
            case let .forceBase64(enabled):
                forceBase64 = enabled
            case let .addTrailingSlash(enabled):
                addTrailingSlash = enabled''')
edit(p,'''                socketPath = path

                if !socketPath.hasSuffix("/") {
                    socketPath += "/"
                }''','''                socketPath = path''')
edit(p,'''        }
    }

    // Moves from long-polling to websockets''','''        }
        // Normalize after all options: configuration ordering must not matter.
        if socketPath.hasSuffix("/") { socketPath.removeLast() }
        if addTrailingSlash { socketPath += "/" }
        (urlPolling, urlWebSocket) = createURLs()
    }

    // Moves from long-polling to websockets''')
