import Foundation

/// `GET mobile/v2/film/{id}`
struct FilmDetail: Decodable, Hashable {
    let id: Int
    @LossyString var name: String?
    @LossyString var enTitle: String?
    @LossyString var poster: String?
    @LossyString var posterFullsize: String?
    @LossyString var cover: String?
    @LossyString var imdbRating: String?
    @LossyString var imdbVotes: String?
    @LossyString var rotten: String?
    @LossyString var metacritic: String?
    @LossyString var runtime: String?
    @LossyString var releasedDate: String?
    @LossyString var released: String?
    @LossyString var lastEpisode: String?
    @LossyString var updateInfo: String?
    @LossyString var airStatus: String?
    @LossyString var story: String?
    @LossyString var about: String?
    @LossyString var director: String?
    @LossyString var trailer: String?
    @LossyString var userVote: String?

    @LossyBool var isPaid: Bool
    @LossyBool var watchlisted: Bool
    @LossyBool var notified: Bool

    @LossyString var onlineSingle: String?
    @LossyObject var onlineQuality: QualityLinks?

    @LossyArray var genres: [Term]
    @LossyArray var countries: [Term]
    @LossyArray var fullActors: [Actor]
    @LossyArray var filmDl: [FilmDownloadGroup]
    @LossyArray var serialDl: [Season]
    @LossyArray var related: [Post]
    @LossyObject var collection: PostSection?
    @LossyObject var watchProgress: WatchProgressItem?

    /// First 5 top-level comments with their replies; more via `get_comments`.
    @LossyArray var comments: [Comment]
    @LossyInt var totalComments: Int?
    @LossyInt var totalPages: Int?

    var displayName: String { name ?? enTitle ?? "" }
    var isSeries: Bool { !serialDl.isEmpty }
    var backdropURL: URL? { URL(string: cover ?? posterFullsize ?? poster ?? "") }
    var posterURL: URL? { URL(string: posterFullsize ?? poster ?? "") }
}

/// The 1080/720/480 link map. Links the caller may not see arrive as "".
struct QualityLinks: Decodable, Hashable {
    @LossyString var q1080: String?
    @LossyString var q720: String?
    @LossyString var q480: String?

    enum CodingKeys: String, CodingKey {
        case q1080 = "1080"
        case q720 = "720"
        case q480 = "480"
    }

    /// Best first.
    var available: [(label: String, url: String)] {
        var result: [(label: String, url: String)] = []
        if let q1080 { result.append((label: "1080p", url: q1080)) }
        if let q720 { result.append((label: "720p", url: q720)) }
        if let q480 { result.append((label: "480p", url: q480)) }
        return result
    }
}

/// One version block of a film (e.g. dubbed / subtitled).
struct FilmDownloadGroup: Decodable, Hashable {
    @LossyString var rowInfo: String?
    /// "dub", "sub" or ""
    @LossyString var versionType: String?
    @LossyString var versionLabel: String?
    @LossyArray var playonline: [OnlineLink]
    @LossyArray var data: [DownloadLink]
}

struct OnlineLink: Decodable, Hashable {
    @LossyString var link: String?
    @LossyBool var hasLink: Bool
    @LossyObject var quality: QualityLinks?
    @LossyString var subtitle: String?
}

/// A download row; used for both film rows and serial episode rows.
struct DownloadLink: Decodable, Hashable {
    @LossyString var link: String?
    @LossyBool var hasLink: Bool
    @LossyString var quality: String?
    @LossyString var online: String?
    @LossyString var versionLabel: String?
    @LossyString var price: String?
    @LossyString var dlRowInfo: String?
    @LossyString var size: String?
}

struct Season: Decodable, Hashable, Identifiable {
    @LossyString var seasonName: String?
    @LossyString var seasonID: String?
    @LossyString var episodeCount: String?
    @LossyArray var episode: [Episode]

    var id: String { (seasonID ?? "") + (seasonName ?? "") }

    /// Season number used by watch progress; falls back to the position in the list.
    func number(fallback index: Int) -> Int {
        if let id = seasonID, let value = Int(id.filter(\.isNumber)) { return value }
        if let name = seasonName, let value = Int(name.filter(\.isNumber)) { return value }
        return index + 1
    }
}

struct Episode: Decodable, Hashable {
    @LossyString var title: String?
    @LossyInt var episodeNumber: Int?
    @LossyString var onlineLink: String?
    @LossyBool var hasOnlineLink: Bool
    @LossyString var subtitle: String?
    @LossyObject var quality: QualityLinks?
    @LossyString var versionType: String?
    @LossyString var versionLabel: String?
    @LossyString var rowInfo: String?
    @LossyArray var link: [DownloadLink]
}
