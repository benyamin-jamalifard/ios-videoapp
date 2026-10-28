import Foundation

/// One quality of the same video.
struct PlaybackSource: Hashable {
    let label: String
    let url: URL
}

/// What to play and where to report progress for it.
struct PlaybackItem: Identifiable {
    let id = UUID()
    var url: URL
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
    /// Shown on the TV while casting.
    var posterURL: URL?
    /// Other qualities of the same video, for switching in the player.
    var sources: [PlaybackSource] = []
    /// The following episodes of the season, in order.
    var upNext: [PlaybackItem] = []
    /// A downloaded file, played without the network.
    var isOffline = false

    /// "S1 · E3" for series, used under the title.
    var episodeLabel: String? {
        contentType == "series" && episodeNo > 0 ? "فصل \(seasonNo) · قسمت \(episodeNo)" : nil
    }
}

enum ContentAccess {
    case allowed, needsLogin, needsSubscription, unavailableInRegion
}

extension AppState {
    /// Mirrors the plugin's gating, using the `vip_lock` option. Outside Iran
    /// nothing plays or downloads.
    ///
    /// - Parameter feature: "playonline" or "download".
    func access(to feature: String, paid: Bool) -> ContentAccess {
        if isInternational {
            return .unavailableInRegion
        }
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
    /// AVPlayer handles MP4/MOV/HLS; MKV and AVI do not play on iOS.
    static func isNativelyPlayable(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty || ["mp4", "m4v", "mov", "m3u8", "mp3", "m4a"].contains(ext)
    }
}
