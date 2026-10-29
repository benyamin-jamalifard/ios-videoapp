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
    /// Gives up after four seconds (in a shutdown these services are out of
    /// reach) and keeps the previous answer.
    @discardableResult
    static func refresh() async -> Bool {
        #if DEBUG
        // For screenshots of both modes in CI: `-kf.region.override ir|intl`.
        if let override = UserDefaults.standard.string(forKey: "kf.region.override") {
            isInternational = override == "intl"
            return isInternational
        }
        #endif
        if let country = await lookUpCountry() {
            isInternational = country != "IR"
            UserDefaults.standard.set(isInternational, forKey: storageKey)
        }
        return isInternational
    }

    /// Two-letter country code of the public IP: the first of several services to answer.
    static func lookUpCountry() async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await cloudflare() }
            group.addTask { await countryIs() }
            group.addTask { await ipWho() }
            group.addTask {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                return "timeout"
            }
            var failed = 0
            for await result in group {
                if result == "timeout" { break }
                if let result, result.count == 2 {
                    group.cancelAll()
                    return result
                }
                failed += 1
                if failed == 3 { break }
            }
            group.cancelAll()
            return nil
        }
    }

    private static func cloudflare() async -> String? {
        guard let trace = await text(from: "https://www.cloudflare.com/cdn-cgi/trace"),
              let line = trace.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("loc=") })
        else { return nil }
        return String(line.dropFirst(4)).uppercased()
    }

    private static func countryIs() async -> String? {
        struct Response: Decodable { let country: String }
        guard let data = await data(from: "https://api.country.is/") else { return nil }
        return (try? JSONDecoder().decode(Response.self, from: data))?.country.uppercased()
    }

    private static func ipWho() async -> String? {
        struct Response: Decodable { let country_code: String? }
        guard let data = await data(from: "https://ipwho.is/") else { return nil }
        return (try? JSONDecoder().decode(Response.self, from: data))?.country_code?.uppercased()
    }

    private static func text(from address: String) async -> String? {
        (await data(from: address)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func data(from address: String) async -> Data? {
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
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
