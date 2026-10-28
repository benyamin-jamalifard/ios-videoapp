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
}

enum APIError: LocalizedError {
    case notConfigured
    case badStatus(Int, String?)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "آدرس سایت در تنظیمات اپ وارد نشده است."
        case .badStatus(_, let message?):
            return message
        case .badStatus(let code, nil):
            return "خطای سرور (\(code))"
        case .decoding:
            return "پاسخ سرور قابل خواندن نبود."
        case .transport:
            return "اتصال به اینترنت برقرار نیست."
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

    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type = T.self) async throws -> T {
        let request = try makeRequest(endpoint)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode, Self.wordpressMessage(in: data))
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("Decoding \(endpoint.path) failed:", error)
            #endif
            throw APIError.decoding(error)
        }
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

        // Some routes are slow on the server (top 250 has taken over 40 s).
        var request = URLRequest(url: url, timeoutInterval: 90)
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
