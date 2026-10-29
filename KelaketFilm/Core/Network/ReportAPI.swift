import Foundation

/// "گزارش مشکل": the theme's report form on film pages. It has no REST
/// route; it posts to admin-ajax (`kelaket_submit_report`) with a guest
/// nonce printed into the film page, so the app reads that page first.
extension APIClient {
    func reportProblem(postId: Int, name: String, description: String) async throws -> String {
        guard let siteURL else { throw APIError.notConfigured }

        // A fresh copy of the page: a cached one may carry an expired nonce.
        var page = URLComponents(url: siteURL, resolvingAgainstBaseURL: false)
        page?.queryItems = [URLQueryItem(name: "p", value: String(postId)),
                            URLQueryItem(name: "nocache", value: String(Int(Date().timeIntervalSince1970)))]
        guard let pageURL = page?.url else { throw APIError.notConfigured }
        var pageRequest = URLRequest(url: pageURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        pageRequest.setValue("text/html", forHTTPHeaderField: "Accept")
        let html: String
        do {
            let (data, _) = try await URLSession.shared.data(for: pageRequest)
            html = String(decoding: data, as: UTF8.self)
        } catch {
            throw APIError.transport(error)
        }
        guard let nonce = Self.reportNonce(in: html) else {
            throw APIError.badStatus(0, "گزارش برای این عنوان فعال نیست.")
        }

        var request = URLRequest(url: siteURL.appendingPathComponent("wp-admin/admin-ajax.php"),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formBody([
            "action": "kelaket_submit_report",
            "post_id": String(postId),
            "report_nonce": nonce,
            "guest_name": name,
            "description": description,
        ])
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
        // WordPress answers a rejected nonce with a bare "-1".
        guard let response = try? JSONDecoder().decode(ActionResponse.self, from: data) else {
            throw APIError.badStatus(0, "ارسال گزارش انجام نشد. دوباره تلاش کنید.")
        }
        guard response.success else {
            throw APIError.badStatus(0, response.text ?? "ارسال گزارش انجام نشد.")
        }
        return response.text ?? "گزارش شما ثبت شد. ممنون!"
    }

    /// `<input type="hidden" id="report_nonce" name="report_nonce" value="…" />`
    static func reportNonce(in html: String) -> String? {
        guard let field = html.range(of: #"name="report_nonce"[^>]*"#, options: .regularExpression),
              let value = html[field].range(of: #"value="[^"]+""#, options: .regularExpression)
        else { return nil }
        return String(html[field][value].dropFirst(7).dropLast())
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        // ASCII only: `.alphanumerics` would let Persian letters through unencoded.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&").utf8)
    }
}
