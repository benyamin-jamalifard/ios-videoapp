import SwiftUI

enum AppTab: Hashable {
    case home, explore, search, downloads, profile
}

/// Cross-cutting navigation: deep links from notifications and the
/// `kelaketfilm://` URL scheme, plus the latest FCM token.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var tab: AppTab = .home
    @Published var homePath = NavigationPath()
    @Published var pushToken: String?
    /// A web link to show in the in-app page (never in Safari, so it stays hidden).
    @Published var webLink: WebLink?

    func open(_ url: URL) {
        if let tab = Self.tab(in: url) {
            self.tab = tab
        } else if let id = Self.filmID(in: url) {
            tab = .home
            homePath.append(FilmRoute(id: id))
        } else if url.scheme == "http" || url.scheme == "https" {
            webLink = WebLink(url: url)
        }
    }

    /// `kelaketfilm://app/tab/search` (home, search, explore, downloads, profile).
    static func tab(in url: URL) -> AppTab? {
        guard url.scheme == "kelaketfilm" else { return nil }
        let parts = ([url.host ?? ""] + url.pathComponents).filter { $0 != "/" && !$0.isEmpty }
        guard let index = parts.firstIndex(of: "tab"), parts.indices.contains(index + 1) else { return nil }
        switch parts[index + 1] {
        case "home": return .home
        case "search": return .search
        case "explore": return .explore
        case "downloads": return .downloads
        case "profile": return .profile
        default: return nil
        }
    }

    /// Reads the post id from links such as `kelaketfilm://app/film/12392`
    /// or `kelaketfilm://film/12392` (also `post`, `series`, `serial`).
    static func filmID(in url: URL) -> Int? {
        guard url.scheme == "kelaketfilm" else { return nil }
        let parts = ([url.host ?? ""] + url.pathComponents).filter { $0 != "/" && !$0.isEmpty }
        guard let index = parts.firstIndex(where: { ["film", "post", "series", "serial"].contains($0) }),
              parts.indices.contains(index + 1)
        else { return nil }
        return Int(parts[index + 1])
    }
}
