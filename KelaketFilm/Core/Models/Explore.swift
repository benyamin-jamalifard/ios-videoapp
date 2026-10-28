import Foundation

/// `GET mobile/v1/searchTerms` — the values for each archive filter.
struct SearchTerms: Decodable {
    @LossyArray var postType: [FilterTerm]
    @LossyArray var genres: [FilterTerm]
    @LossyArray var year: [FilterTerm]
    @LossyArray var country: [FilterTerm]
}

struct FilterTerm: Decodable, Hashable, Identifiable {
    @LossyInt var termId: Int?
    @LossyString var termName: String?
    @LossyString var termSlug: String?

    var id: Int { termId ?? 0 }
}

/// Filters for `GET mobile/v2/archive`. Term ids, nil meaning "all".
struct ArchiveFilter: Hashable {
    var postType: Int?
    var genre: Int?
    var year: Int?
    var country: Int?
    var category: Int?
    var actor: Int?
    /// "newest", "oldest", "imdb_score" or "updated"; nil for the default order.
    var sort: String?

    var isEmpty: Bool { self == ArchiveFilter() }

    var query: [String: String] {
        var query: [String: String] = [:]
        if let postType { query["type_of_post"] = String(postType) }
        if let genre { query["genre"] = String(genre) }
        if let year { query["yearr"] = String(year) }
        if let country { query["country"] = String(country) }
        if let category { query["category"] = String(category) }
        if let actor { query["actor"] = String(actor) }
        if let sort { query["sort"] = sort }
        return query
    }

    static var sortOptions: [(value: String?, label: String)] {
        [
            (nil, L("پیش‌فرض", "Default")),
            ("newest", L("جدیدترین", "Newest")),
            ("oldest", L("قدیمی‌ترین", "Oldest")),
            ("imdb_score", L("امتیاز IMDb", "IMDb rating")),
            ("updated", L("به‌روزشده", "Recently updated")),
        ]
    }
}

/// Filters for `GET mobile/v1/search`. Unlike the archive, it takes term slugs.
struct SearchFilter: Hashable {
    var postType: String?
    var genre: String?
    var fromYear: Int?
    var toYear: Int?
    var country: String?
    var dubbed = false
    var subtitled = false
    var streamable = false

    var isEmpty: Bool { self == SearchFilter() }

    /// How many filters are set, for the badge on the filter button.
    var count: Int {
        [postType != nil, genre != nil, fromYear != nil || toYear != nil, country != nil,
         dubbed, subtitled, streamable].filter { $0 }.count
    }

    var query: [String: String] {
        var query = ["type_of_post": postType ?? "all"]
        if let genre { query["genre"] = genre }
        // The plugin needs both ends of the year range.
        if fromYear != nil || toYear != nil {
            let from = fromYear ?? 1900, to = toYear ?? Calendar.current.component(.year, from: Date()) + 1
            query["from_year"] = String(min(from, to))
            query["to_year"] = String(max(from, to))
        }
        if let country { query["country"] = country }
        if dubbed { query["has_dubbed"] = "1" }
        if subtitled { query["has_subtitle"] = "1" }
        if streamable { query["has_playonline"] = "1" }
        return query
    }
}

struct ArchivePage: Decodable {
    @LossyArray var data: [Post]
    @LossyObject var paginationValues: Pagination?

    struct Pagination: Decodable, Hashable {
        @LossyInt var current: Int?
        @LossyInt var maxPages: Int?
        @LossyInt var total: Int?
    }
}

/// `GET mobile/v1/fetchGenres`
struct Genre: Decodable, Hashable, Identifiable {
    let id: Int
    @LossyString var title: String?
    @LossyString var slug: String?
    @LossyInt var count: Int?
    /// ACF image: a URL string, or an image array with `url`.
    @LossyObject var image: ImageField?
}

struct ImageField: Decodable, Hashable {
    let url: URL?

    init(from decoder: Decoder) throws {
        struct Object: Decodable { @LossyString var url: String? }
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            url = URL(string: string)
        } else {
            url = (try? container.decode(Object.self))?.url.flatMap(URL.init(string:))
        }
    }
}

/// `GET mobile/v2/actors/archive`
struct ActorsPage: Decodable {
    @LossyArray var data: [ActorSummary]
    @LossyObject var pagination: Pagination?

    struct Pagination: Decodable, Hashable {
        @LossyInt var totalPages: Int?
        @LossyBool var hasMore: Bool
    }
}

struct ActorSummary: Decodable, Hashable, Identifiable {
    let id: Int
    @LossyString var name: String?
    @LossyString var image: String?
    @LossyInt var count: Int?
}

/// `GET mobile/v2/get_boxoffice`
struct BoxOffice: Decodable {
    @LossyString var lastUpdateHuman: String?
    @LossyString var message: String?
    @LossyArray var data: [BoxOfficeItem]
}

struct BoxOfficeItem: Decodable, Hashable {
    @LossyInt var rank: Int?
    @LossyString var title: String?
    @LossyString var poster: String?
    @LossyString var weekend: String?
    @LossyString var gross: String?
    @LossyString var weeks: String?
    /// Set when the film exists on the site.
    @LossyInt var postId: Int?
}

/// `GET mobile/v1/getWeeklySeries/{day}`
struct WeeklySeries: Decodable, Hashable, Identifiable {
    let id: Int
    @LossyString var name: String?
    @LossyString var poster: String?
    @LossyString var update: String?
    @LossyString var imdbRating: String?
}

/// A Top 250 row. Titles on the site come as full posts with a numeric id;
/// the rest only carry the IMDb id ("tt…") as `id`.
struct RankedTitle: Decodable, Hashable {
    @LossyString var id: String?
    @LossyString var name: String?
    @LossyString var poster: String?
    @LossyString var imdbRating: String?
    @LossyInt var rank: Int?
    @LossyString var badgeText: String?

    var postId: Int? { id.flatMap(Int.init) }
}

struct RankedPage: Decodable {
    @LossyArray var data: [RankedTitle]
    @LossyInt var pages: Int?
    @LossyString var message: String?
}

/// A child of the theme's collection category.
struct CollectionItem: Decodable, Hashable, Identifiable {
    let id: Int
    @LossyString var name: String?
    @LossyInt var count: Int?
    @LossyString var poster: String?
}

struct CollectionsPage: Decodable {
    @LossyArray var data: [CollectionItem]
    @LossyInt var pages: Int?
}

/// A user-made list (`kelaket_lists`).
struct UserList: Decodable, Hashable, Identifiable {
    let id: Int
    @LossyString var name: String?
    @LossyString var listDesc: String?
    @LossyString var userName: String?
    @LossyBool var isPrivate: Bool
    @LossyArray var films: [Post]
}

struct UserListsPage: Decodable {
    @LossyArray var lists: [UserList]
    @LossyInt var pages: Int?
}
