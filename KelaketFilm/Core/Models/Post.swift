import Foundation

/// A film/series card, as returned by featured, home categories, search,
/// related posts and collections.
struct Post: Decodable, Identifiable, Hashable {
    let id: Int
    @LossyString var name: String?
    @LossyString var title: String?
    @LossyString var enTitle: String?
    @LossyString var poster: String?
    @LossyString var posterFullsize: String?
    /// Wide slider image (`slider_image`), only on featured posts.
    @LossyString var poster2: String?
    @LossyString var cover: String?
    @LossyString var imdbRating: String?
    @LossyString var sliderBadge: String?
    @LossyString var lastEpisode: String?
    @LossyString var story: String?
    @LossyString var released: String?
    @LossyString var badgeText: String?
    @LossyString var badgeColor: String?
    @LossyString var userVote: String?
    /// Has Persian subtitles (`def-version`).
    @LossyBool var def: Bool
    /// Has a Persian dub (`persian-doble`).
    @LossyBool var doble: Bool

    var displayName: String {
        if Region.isInternational {
            // Some lists (the archive) carry only the Persian title; then no
            // caption: the poster itself shows the English one.
            return enTitle ?? [name, title].compactMap { $0 }.first { !Localizer.containsPersian($0) } ?? ""
        }
        return name ?? title ?? enTitle ?? ""
    }

    var posterURL: URL? {
        URL(string: poster ?? posterFullsize ?? "")
    }

    var wideImageURL: URL? {
        URL(string: cover ?? poster2 ?? posterFullsize ?? poster ?? "")
    }

    /// The ribbon under the poster ("زیرنویس فارسی"), in English abroad.
    var badgeLabel: String? {
        guard let badgeText else { return nil }
        guard Region.isInternational, Localizer.containsPersian(badgeText) else { return badgeText }
        return Localizer.translatePhrase(badgeText)
    }
}

struct Term: Decodable, Hashable, Identifiable {
    @LossyInt var id: Int?
    @LossyString var name: String?
    @LossyString var slug: String?

    var displayName: String { Localizer.term(name: name, slug: slug) }
}

struct Actor: Decodable, Hashable, Identifiable {
    @LossyInt var id: Int?
    @LossyString var name: String?
    @LossyString var image: String?
    @LossyString var bio: String?
}
