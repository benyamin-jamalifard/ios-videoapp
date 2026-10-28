import Foundation

/// The "continue watching" block on the home screen.
struct WatchProgressBlock: Decodable, Hashable {
    @LossyString var title: String?
    @LossyBool var enabled: Bool
    @LossyArray var data: [WatchProgressItem]
}

struct WatchProgressItem: Decodable, Hashable, Identifiable {
    let id: Int
    @LossyString var name: String?
    @LossyString var title: String?
    @LossyString var poster: String?
    @LossyString var cover: String?
    /// "film" or "series"
    @LossyString var contentType: String?
    @LossyInt var seasonNo: Int?
    @LossyInt var episodeNo: Int?
    @LossyInt var movieRowNo: Int?
    @LossyString var episodeLabel: String?
    @LossyInt var positionSeconds: Int?
    @LossyInt var durationSeconds: Int?
    @LossyString var progressPercent: String?
    @LossyString var remainingLabel: String?

    var progress: Double {
        guard let percent = progressPercent.flatMap(Double.init) else { return 0 }
        return min(max(percent / 100, 0), 1)
    }

    var imageURL: URL? {
        URL(string: cover ?? poster ?? "")
    }
}

/// Body of `POST mobile/v2/watch_progress/save`.
struct WatchProgressSave: Encodable {
    let postId: Int
    /// "film" or "series"
    let contentType: String
    let seasonNo: Int
    let episodeNo: Int
    let movieRowNo: Int
    let positionSeconds: Int
    let durationSeconds: Int
    /// "interval", "pause" or "close"
    let reason: String
}
