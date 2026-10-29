import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
}

struct Endpoint {
    let path: String
    var method: HTTPMethod = .get
    var query: [String: String] = [:]
    var body: Encodable?
    /// Extra headers for this request only.
    var headers: [String: String] = [:]
    /// Most routes answer in seconds; a few (top 250) are slow on the server.
    var timeout: TimeInterval = 25
}

enum APIError: LocalizedError {
    case notConfigured
    case badStatus(Int, String?)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return L("آدرس سایت در تنظیمات اپ وارد نشده است.", "The app isn't set up yet.")
        case .badStatus(_, let message?):
            // The site's own messages are Persian.
            return Localizer.shown(message) ?? "Something went wrong. Try again."
        case .badStatus(let code, nil):
            return L("خطای سرور (\(code))", "Server error (\(code))")
        case .decoding:
            return L("پاسخ سرور قابل خواندن نبود.", "The server's answer couldn't be read.")
        case .transport(let error):
            // Only say "no internet" when the phone really has none.
            switch (error as? URLError)?.code {
            case .notConnectedToInternet?, .dataNotAllowed?, .internationalRoamingOff?:
                return L("اتصال به اینترنت برقرار نیست.", "You're not connected to the internet.")
            case .timedOut?:
                return L("سرور دیر پاسخ داد. دوباره تلاش کنید.", "The server took too long. Try again.")
            default:
                return L("ارتباط با سرور برقرار نشد. دوباره تلاش کنید.", "Couldn't reach the server. Try again.")
            }
        }
    }
}

/// Talks to the WordPress REST API exposed by the kelaketfilm plugins.
///
/// Every request carries `X-API-KEY` (checked by `kelaket_check_api_key`) and,
/// when signed in, `X-USER-TOKEN`, which the plugin maps onto the `user_token`
/// parameter for all `mobile/v1` and `mobile/v2` routes.
final class APIClient {
    static let shared = APIClient()

    var userToken: String?

    /// The address built into the app; used when the address file can't be read.
    let defaultHost: String?
    private let hostListURL: URL?
    private let lock = NSLock()
    private var _baseURL: URL?
    private let apiKey: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private static let cachedHostKey = "kf.siteHost"
    private var lastHostRecovery = Date.distantPast

    init(bundle: Bundle = .main, session: URLSession = .shared) {
        let host = (bundle.object(forInfoDictionaryKey: "KFSiteHost") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        defaultHost = host.isEmpty || host == "example.com" ? nil : host
        let list = (bundle.object(forInfoDictionaryKey: "KFHostListURL") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        hostListURL = list.isEmpty ? nil : URL(string: list.contains("://") ? list : "https://\(list)")
        apiKey = bundle.object(forInfoDictionaryKey: "KFApiKey") as? String ?? ""
        self.session = session

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        // Background refreshes run before the UI (and AppState) exist.
        userToken = Keychain.string(for: "jwt")

        // Start from the last address that worked, then the built-in one.
        let cached = UserDefaults.standard.string(forKey: Self.cachedHostKey)
        _baseURL = Self.apiURL(host: cached ?? defaultHost)
    }

    private var baseURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return _baseURL
    }

    var siteURL: URL? {
        baseURL?.deletingLastPathComponent()
    }

    var currentHost: String? { baseURL?.host }

    /// Points every request at `host` and remembers it for the next launch.
    func useHost(_ host: String) {
        guard let url = Self.apiURL(host: host) else { return }
        lock.lock()
        _baseURL = url
        lock.unlock()
        UserDefaults.standard.set(url.host, forKey: Self.cachedHostKey)
    }

    /// Anti-filter: the site's current address is published in a small text
    /// file (the same one the Android app reads), e.g. "https://onlinegmo.xyz".
    /// Returns the host found there, or nil when it can't be read.
    func fetchPublishedHost() async -> String? {
        guard let hostListURL else { return nil }
        var request = URLRequest(url: hostListURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let host = URL(string: line.contains("://") ? line : "https://\(line)")?.host
        return host?.contains(".") == true ? host : nil
    }

    private static func apiURL(host: String?) -> URL? {
        guard let host, !host.isEmpty else { return nil }
        let bare = host.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return URL(string: "https://\(bare)/wp-json/")
    }

    /// Sends a request. GET answers are saved, and when the site can't be
    /// reached the saved copy is returned instead, so screens keep working
    /// through outages. A dead address triggers a look-up of the current one.
    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type = T.self) async throws -> T {
        let cacheKey = endpoint.method == .get ? cacheKey(for: endpoint) : nil
        do {
            let data = try await fetch(endpoint, recoverHost: true)
            let value = try decode(T.self, from: data, path: endpoint.path)
            if let cacheKey { OfflineCache.responses.write(data, for: cacheKey) }
            await report(reachable: true)
            return value
        } catch let error as APIError {
            // A request the app cancelled itself (screen closed, search text
            // changed, lists reloading) says nothing about the site.
            if case .transport(let underlying) = error, Self.isCancellation(underlying) || Task.isCancelled {
                throw CancellationError()
            }
            guard Self.meansSiteDown(error) else { throw error }
            await report(reachable: false)
            if let cacheKey, let saved = OfflineCache.responses.read(cacheKey),
               let value = try? decode(T.self, from: saved, path: endpoint.path) {
                return value
            }
            throw error
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// No answer at all, or the CDN/gateway saying the site is down. A plain
    /// 500 from one route is that route's error, not an outage.
    private static func meansSiteDown(_ error: APIError) -> Bool {
        switch error {
        case .transport: return true
        case .badStatus(let code, _): return [502, 503, 504].contains(code) || (520...530).contains(code)
        default: return false
        }
    }

    /// The last saved answer for a GET, without asking the server.
    func saved<T: Decodable>(_ endpoint: Endpoint, as type: T.Type = T.self) -> T? {
        guard let data = OfflineCache.responses.read(cacheKey(for: endpoint)) else { return nil }
        return try? decode(T.self, from: data, path: endpoint.path)
    }

    /// True when the site answers at all; used to notice the end of an outage.
    func ping() async -> Bool {
        guard let request = try? makeRequest(Endpoint(path: "mobile/v2/config", timeout: 10)),
              let (_, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode
        else { return false }
        return status < 500
    }

    private func fetch(_ endpoint: Endpoint, recoverHost: Bool) async throws -> Data {
        let request = try makeRequest(endpoint)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if Self.isCancellation(error) { throw APIError.transport(error) }
            // The address may have been filtered or moved: find the current one and retry once.
            if recoverHost, await self.recoverHost() {
                return try await fetch(endpoint, recoverHost: false)
            }
            throw APIError.transport(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode, Self.wordpressMessage(in: data))
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, path: String) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("Decoding \(path) failed:", error)
            #endif
            throw APIError.decoding(error)
        }
    }

    @MainActor
    private func report(reachable: Bool) {
        NetworkStatus.shared.report(reachable: reachable)
    }

    /// The saved copy belongs to the route, its query and the signed-in user
    /// (film links differ per account); not to the host, which may change.
    private func cacheKey(for endpoint: Endpoint) -> String {
        let query = endpoint.query.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return "\(endpoint.path)?\(query)#\(userToken ?? "")"
    }

    /// Tries the published address, then the built-in one; switches to the
    /// first that answers. At most once a minute.
    private func recoverHost() async -> Bool {
        lock.lock()
        let due = Date().timeIntervalSince(lastHostRecovery) > 60
        if due { lastHostRecovery = Date() }
        lock.unlock()
        guard due else { return false }

        var candidates: [String] = []
        if let published = await fetchPublishedHost() { candidates.append(published) }
        if let defaultHost { candidates.append(defaultHost) }
        for host in candidates where host != currentHost {
            guard let url = Self.apiURL(host: host)?.appendingPathComponent("mobile/v2/config") else { continue }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
            if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY") }
            if let (_, response) = try? await session.data(for: request),
               ((response as? HTTPURLResponse)?.statusCode ?? 500) < 500 {
                useHost(host)
                return true
            }
        }
        return false
    }

    private func makeRequest(_ endpoint: Endpoint) throws -> URLRequest {
        guard let baseURL,
              var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path),
                                             resolvingAgainstBaseURL: false)
        else { throw APIError.notConfigured }

        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.notConfigured }

        // Always fresh from the server; outages are covered by `OfflineCache`.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: endpoint.timeout)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios", forHTTPHeaderField: "X-KELAKET-CLIENT")
        request.setValue(Self.appVersion, forHTTPHeaderField: "X-APP-VERSION")
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        }
        if let userToken, !userToken.isEmpty {
            request.setValue(userToken, forHTTPHeaderField: "X-USER-TOKEN")
        }
        for (name, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        return request
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// WP_Error responses look like {"code": "...", "message": "...", "data": {"status": 400}};
    /// `wp_send_json_error` ones like {"success": false, "data": {"msg": "..."}}.
    private static func wordpressMessage(in data: Data) -> String? {
        (try? JSONDecoder().decode(ActionResponse.self, from: data))?.text
    }
}
