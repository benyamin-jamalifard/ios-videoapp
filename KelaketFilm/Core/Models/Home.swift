import Foundation

/// `GET mobile/v2/home_screen`
struct HomeScreen: Decodable {
    @LossyArray var featuredFilms: [Post]
    @LossyArray var selectedCats: [HomeCategory]
    @LossyObject var updatedSeries: PostSection?
    @LossyObject var watchProgress: WatchProgressBlock?
}

struct HomeCategory: Decodable, Hashable, Identifiable {
    @LossyString var catId: String?
    @LossyString var catName: String?
    @LossyString var postType: String?
    @LossyString var genre: String?
    @LossyArray var data: [Post]

    var id: String { "\(catId ?? "")-\(postType ?? "")-\(genre ?? "")-\(catName ?? "")" }

    /// The same query as the plugin's `getSelectedCats`: post type and/or
    /// genre when either is set, otherwise the category.
    var archiveFilter: ArchiveFilter {
        let type = postType.flatMap(Int.init)
        let genreId = genre.flatMap(Int.init)
        if type != nil || genreId != nil {
            return ArchiveFilter(postType: type, genre: genreId)
        }
        return ArchiveFilter(category: catId.flatMap(Int.init))
    }
}

/// A titled list of posts: updated series on home, or a film's collection.
struct PostSection: Decodable, Hashable {
    @LossyString var title: String?
    @LossyString var name: String?
    @LossyArray var data: [Post]
}
