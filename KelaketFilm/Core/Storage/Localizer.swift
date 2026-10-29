import Foundation

/// English names for the site's Persian content in international mode. Most
/// terms already have English slugs ("action", "united-states"); the rest,
/// and the admin's section titles, go through a small dictionary.
enum Localizer {
    /// A genre, country or type name for the current mode.
    static func term(name: String?, slug: String?) -> String {
        guard Region.isInternational else { return persian(name: name, slug: slug) }
        return english(name: name, slug: slug) ?? name ?? ""
    }

    /// The site names a few terms in English ("Film-Noir", "movie"); the
    /// Persian app shows them in Persian.
    static func persian(name: String?, slug: String?) -> String {
        guard let name, !containsPersian(name) else { return name ?? "" }
        let key = (slug?.removingPercentEncoding ?? name).lowercased()
        return persianNames[key] ?? persianNames[name.lowercased()] ?? name
    }

    /// The English name, or nil when there is none.
    static func english(name: String?, slug: String?) -> String? {
        // All-lowercase names are slugs used as names ("movie").
        if let name, !containsPersian(name) {
            return name == name.lowercased() ? slugOverrides[name] ?? prettify(name) : name
        }
        if let name, let known = words[normalized(name)] { return known }
        if let slug = slug?.removingPercentEncoding, !slug.isEmpty, !containsPersian(slug),
           slug.rangeOfCharacter(from: .letters) != nil {
            return slugOverrides[slug] ?? prettify(slug)
        }
        return nil
    }

    /// A section title written by the admin, such as "فیلم های جدید".
    static func title(_ text: String?) -> String {
        guard let text else { return "" }
        guard Region.isInternational, containsPersian(text) else { return text }
        return translatePhrase(text) ?? text
    }

    /// Word by word, with "new"/"top"/"popular" moved to the front as in English.
    /// Nil when a word is unknown, so no half-translated title is shown.
    static func translatePhrase(_ text: String) -> String? {
        let clean = normalized(text)
        if let whole = phrases[clean] { return whole }
        var leading: [String] = []
        var rest: [String] = []
        let parts = clean.split(separator: " ").map(String.init)
        var index = 0
        while index < parts.count {
            // Two-word names first: "علمی تخیلی", "کره ای".
            if index + 1 < parts.count, let pair = words[parts[index] + " " + parts[index + 1]] {
                rest.append(pair)
                index += 2
                continue
            }
            let word = parts[index]
            index += 1
            if fillers.contains(word) { continue }
            if let adjective = leadingAdjectives[word] {
                if !adjective.isEmpty, !leading.contains(adjective) { leading.append(adjective) }
            } else if let english = words[word] {
                rest.append(english)
            } else {
                return nil
            }
        }
        // "فیلم های اکشن" reads "Movies Action"; English puts the kind last.
        if rest.count > 1, let kind = rest.first, kinds.contains(kind) {
            rest.removeFirst()
            rest.append(kind)
        }
        let result = (leading + rest).joined(separator: " ")
        return result.isEmpty ? nil : result
    }

    static func containsPersian(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) || (0xFB50...0xFEFF).contains($0.value) }
    }

    /// "united-states" → "United States", "sci-fi" → "Sci-Fi".
    static func prettify(_ slug: String) -> String {
        slug.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: slug.count <= 7 ? "-" : " ")
    }

    /// Joins half-spaces and spellings ("ها" with or without ZWNJ, Arabic ي/ك).
    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{200C}", with: " ")
            .replacingOccurrences(of: "ي", with: "ی")
            .replacingOccurrences(of: "ك", with: "ک")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static let slugOverrides = [
        "sci-fi": "Sci-Fi", "film-noir": "Film-Noir", "talk-show": "Talk Show", "game-show": "Game Show",
        "reality-tv": "Reality TV", "tv-movie": "TV Movie", "film": "Movies", "movie": "Movies",
        "series": "Series", "animation": "Animation", "usa": "USA", "uk": "UK",
    ]

    private static let kinds: Set<String> = ["Movies", "Series", "Animation", "Anime", "Cartoons", "Documentary"]

    private static let persianNames = [
        "movie": "فیلم", "film": "فیلم", "series": "سریال", "animation": "انیمیشن", "anime": "انیمه",
        "film-noir": "فیلم نوآر", "game-show": "مسابقه", "reality-tv": "ریالیتی شو", "news": "خبری",
        "talk-show": "تاک شو", "music": "موزیک", "musical": "موزیکال", "documentary": "مستند",
        "short": "کوتاه", "sport": "ورزشی", "biography": "بیوگرافی", "history": "تاریخی",
        "family": "خانوادگی", "fantasy": "فانتزی", "sci-fi": "علمی تخیلی", "adult": "بزرگسال",
        "tv-movie": "فیلم تلویزیونی", "western": "وسترن", "war": "جنگی",
    ]

    private static let fillers: Set<String> = ["ها", "های", "و", "با", "از"]

    private static let leadingAdjectives = [
        "جدید": "New", "تازه": "New", "برتر": "Top", "محبوب": "Popular", "پربازدید": "Most Watched",
        "پیشنهادی": "Recommended", "منتخب": "Featured", "ویژه": "Featured", "برگزیده": "Featured",
        "به": "", "روز": "Updated", "بروز": "Updated", "شده": "",
    ]

    private static let phrases = [
        "سریال های به روز شده": "Recently Updated Series",
        "سریال های بروز شده": "Recently Updated Series",
        "ادامه تماشا": "Continue Watching",
        "دوبله فارسی": "Persian Dub",
        "زیرنویس فارسی": "Persian Subtitles",
        "زیرنویس چسبیده": "Hardcoded Subtitles",
        "پخش آنلاین": "Watch Online",
        "به زودی": "Coming Soon",
        "در حال پخش": "Airing",
        "پایان یافته": "Ended",
    ]

    private static let words = [
        "فیلم": "Movies", "سینمایی": "Movies", "سریال": "Series", "انیمیشن": "Animation", "انیمه": "Anime",
        "مستند": "Documentary", "کارتون": "Cartoons", "ایرانی": "Iranian", "خارجی": "Foreign",
        "کره ای": "Korean", "کره": "Korean", "ترکی": "Turkish", "ترکیه": "Turkish",
        "هندی": "Indian", "ژاپنی": "Japanese", "چینی": "Chinese", "اسپانیایی": "Spanish",
        "دوبله": "Dubbed", "زیرنویس": "Subtitled", "فارسی": "Persian", "کلاسیک": "Classic",
        "کالکشن": "Collections", "کودک": "Kids", "کودکان": "Kids", "خانوادگی": "Family",
        "اکشن": "Action", "کمدی": "Comedy", "درام": "Drama", "ترسناک": "Horror", "وحشت": "Horror",
        "عاشقانه": "Romance", "علمی تخیلی": "Sci-Fi", "تخیلی": "Fantasy", "فانتزی": "Fantasy",
        "جنایی": "Crime", "معمایی": "Mystery", "هیجان انگیز": "Thriller", "هیجانی": "Thriller",
        "ماجراجویی": "Adventure", "تاریخی": "History", "جنگی": "War", "وسترن": "Western",
        "موزیکال": "Musical", "آهنگ": "Music", "موسیقی": "Music", "ورزشی": "Sport", "بیوگرافی": "Biography",
        "اجتماعی": "Social", "مذهبی": "Religious", "پلیسی": "Crime", "روانشناختی": "Psychological",
        "رزمی": "Martial Arts", "ابرقهرمانی": "Superhero", "نوجوان": "Teen", "مینی": "Mini",
        "آمریکا": "United States", "انگلیس": "United Kingdom", "ایران": "Iran", "فرانسه": "France",
        "آلمان": "Germany", "ژاپن": "Japan", "چین": "China", "هند": "India", "کانادا": "Canada",
        "اسپانیا": "Spain", "ایتالیا": "Italy", "روسیه": "Russia", "استرالیا": "Australia",
        "مکزیک": "Mexico", "برزیل": "Brazil", "سوئد": "Sweden", "دانمارک": "Denmark", "نروژ": "Norway",
        "انگلیسی": "English", "آلمانی": "German", "فرانسوی": "French", "روسی": "Russian", "عربی": "Arabic",
    ]
}
