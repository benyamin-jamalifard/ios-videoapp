import Foundation

/// Where the device connects from. Outside Iran the app is an English
/// catalogue only: no playback, downloads, comments or sign-in.
///
/// Decided by the public IP alone (a VPN counts as abroad). The last answer is
/// kept, so a launch where every lookup fails behaves like the previous one;
/// the very first launch defaults to Iran.
enum Region {
    private(set) static var isInternational = UserDefaults.standard.bool(forKey: storageKey)

    private static let storageKey = "kf.region.international"

    /// Looks the country up and stores the result. Call before showing the UI.
    @discardableResult
    static func refresh() async -> Bool {
        if let country = await lookUpCountry() {
            isInternational = country != "IR"
            UserDefaults.standard.set(isInternational, forKey: storageKey)
        }
        return isInternational
    }

    /// Two-letter country code of the public IP, trying a few services in turn.
    private static func lookUpCountry() async -> String? {
        if let trace = await text(from: "https://www.cloudflare.com/cdn-cgi/trace"),
           let line = trace.split(separator: "\n").first(where: { $0.hasPrefix("loc=") }) {
            return String(line.dropFirst(4)).uppercased()
        }
        struct CountryIs: Decodable { let country: String }
        if let data = await data(from: "https://api.country.is/"),
           let result = try? JSONDecoder().decode(CountryIs.self, from: data) {
            return result.country.uppercased()
        }
        struct IPWho: Decodable { let country_code: String? }
        if let data = await data(from: "https://ipwho.is/"),
           let code = (try? JSONDecoder().decode(IPWho.self, from: data))?.country_code {
            return code.uppercased()
        }
        return nil
    }

    private static func text(from address: String) async -> String? {
        (await data(from: address)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func data(from address: String) async -> Data? {
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.setValue("KelaketFilm-iOS", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }
}

/// The Persian text, or the English one when the app runs in international mode.
func L(_ persian: String, _ english: String) -> String {
    Region.isInternational ? english : persian
}
