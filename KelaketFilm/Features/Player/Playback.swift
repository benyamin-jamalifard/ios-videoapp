import UIKit

/// What to play and where to report progress for it.
struct PlaybackItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let postId: Int
    /// "film" or "series" — matches the plugin's `content_type`.
    let contentType: String
    var seasonNo = 0
    var episodeNo = 0
    var movieRowNo = 0
    var startAt: Double = 0
    /// The site's soft subtitle (.vtt/.srt) for this video, if it has one.
    var subtitleURL: URL?
}

enum ContentAccess {
    case allowed, needsLogin, needsSubscription
}

extension AppState {
    /// Mirrors the plugin's gating, using the `vip_lock` option.
    ///
    /// - Parameter feature: "playonline" or "download".
    func access(to feature: String, paid: Bool) -> ContentAccess {
        if !isSignedIn && (paid || config.requireLoginPosts) {
            return .needsLogin
        }
        if paid, config.activeVip, config.vipLock.contains(feature),
           !(subscription?.hasActiveSub ?? false) {
            return .needsSubscription
        }
        return .allowed
    }
}

enum Playback {
    /// AVPlayer handles MP4/MOV/HLS. MKV and AVI (common for download links) need an external player.
    static func isNativelyPlayable(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty || ["mp4", "m4v", "mov", "m3u8", "mp3", "m4a"].contains(ext)
    }

    /// VLC for iOS, when installed (declared in LSApplicationQueriesSchemes).
    @MainActor
    static func externalPlayerURL(for url: URL) -> URL? {
        guard let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let vlc = URL(string: "vlc-x-callback://x-callback-url/stream?url=\(encoded)"),
              UIApplication.shared.canOpenURL(vlc)
        else { return nil }
        return vlc
    }
}
