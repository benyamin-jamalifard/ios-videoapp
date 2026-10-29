import Foundation

/// What the user typed, prepared for the site's search (WordPress `s`, which
/// matches words in the title and text).
struct SearchQuery: Equatable {
    /// The words sent to the site.
    let text: String
    /// A year typed after the title ("inception 2010", "جوکر ۲۰۱۹"), used as a filter.
    let year: Int?

    init(_ raw: String) {
        var words = Self.normalize(raw).split(separator: " ").map(String.init)
        var year: Int?
        if words.count > 1, let last = words.last,
           let value = Int(last.trimmingCharacters(in: CharacterSet(charactersIn: "()"))),
           (1900...2100).contains(value) || (1300...1499).contains(value) {
            year = value
            words.removeLast()
        }
        text = words.joined(separator: " ")
        self.year = year
    }

    /// Arabic keyboard letters to Persian ones (ي ك), Persian digits to ASCII,
    /// single spaces: the site stores titles in that form.
    static func normalize(_ text: String) -> String {
        text.latinDigits
            .replacingOccurrences(of: "ي", with: "ی")
            .replacingOccurrences(of: "ى", with: "ی")
            .replacingOccurrences(of: "ك", with: "ک")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// For comparing titles: no case, accents or half-spaces ("Amélie" ~ "amelie").
    static func folded(_ text: String) -> String {
        normalize(text.replacingOccurrences(of: "\u{200C}", with: " "))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Title matches first (exact, then starting with the words, then
    /// containing them) in Persian or English; the site's order otherwise,
    /// which also returns films that only mention the words in their story.
    func rank(_ posts: [Post]) -> [Post] {
        let needle = Self.folded(text)
        guard !needle.isEmpty else { return posts }
        func score(_ post: Post) -> Int {
            let titles = [post.name, post.title, post.enTitle].compactMap { $0 }.map(Self.folded)
            if titles.contains(needle) { return 0 }
            if titles.contains(where: { $0.hasPrefix(needle) }) { return 1 }
            if titles.contains(where: { $0.contains(needle) }) { return 2 }
            return 3
        }
        return posts.enumerated()
            .map { (offset: $0.offset, post: $0.element, score: score($0.element)) }
            .sorted { $0.score != $1.score ? $0.score < $1.score : $0.offset < $1.offset }
            .map(\.post)
    }
}
