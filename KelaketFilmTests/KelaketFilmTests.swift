import SwiftUI
import UIKit
import XCTest

/// Logic tests. The test target compiles the model and helper sources
/// directly (see project.yml), so they run without the app or its pods.
final class SubtitleTests: XCTestCase {
    func testParsesWebVTT() {
        let vtt = """
        WEBVTT

        1
        00:00:01.000 --> 00:00:03.500 align:middle
        <i>سلام</i>

        00:01:02.250 --> 00:01:04.000
        خط اول
        خط دوم
        """
        let cues = Subtitles.parse(vtt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].start, 1, accuracy: 0.001)
        XCTAssertEqual(cues[0].end, 3.5, accuracy: 0.001)
        XCTAssertEqual(cues[0].text, "سلام")
        XCTAssertEqual(cues[1].start, 62.25, accuracy: 0.001)
        XCTAssertEqual(cues[1].text, "خط اول\nخط دوم")
    }

    func testParsesSRTWithCommasAndCRLF() {
        let srt = "1\r\n01:00:00,500 --> 01:00:02,000\r\nHello\r\n\r\n2\r\n01:00:05,000 --> 01:00:06,000\r\nWorld\r\n"
        let cues = Subtitles.parse(srt)
        XCTAssertEqual(cues.map(\.text), ["Hello", "World"])
        XCTAssertEqual(cues[0].start, 3600.5, accuracy: 0.001)
    }

    func testFindsTheCueOnScreen() {
        let cues = Subtitles.parse("1\n00:00:01,000 --> 00:00:02,000\nA\n\n2\n00:00:05,000 --> 00:00:07,000\nB\n")
        XCTAssertNil(Subtitles.cue(at: 0.5, in: cues))
        XCTAssertEqual(Subtitles.cue(at: 1.5, in: cues)?.text, "A")
        XCTAssertNil(Subtitles.cue(at: 3, in: cues))
        XCTAssertEqual(Subtitles.cue(at: 6.9, in: cues)?.text, "B")
        XCTAssertNil(Subtitles.cue(at: 8, in: cues))
    }

    func testDecodesWindows1256() {
        let text = "سلام"
        let cp1256 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.windowsArabic.rawValue)))
        let data = text.data(using: cp1256)!
        XCTAssertEqual(Subtitles.decode(data), text)
    }
}

final class LocalizerTests: XCTestCase {
    func testTranslatesSectionTitles() {
        XCTAssertEqual(Localizer.translatePhrase("فیلم های جدید"), "New Movies")
        XCTAssertEqual(Localizer.translatePhrase("سریال‌های جدید"), "New Series")
        XCTAssertEqual(Localizer.translatePhrase("انیمیشن جدید"), "New Animation")
        XCTAssertEqual(Localizer.translatePhrase("فیلم های علمی تخیلی"), "Sci-Fi Movies")
        XCTAssertEqual(Localizer.translatePhrase("سریال های کره ای جدید"), "New Korean Series")
        XCTAssertEqual(Localizer.translatePhrase("سریال های به روز شده"), "Recently Updated Series")
        XCTAssertEqual(Localizer.translatePhrase("زیرنویس فارسی"), "Persian Subtitles")
        // Unknown words: no half-English title.
        XCTAssertNil(Localizer.translatePhrase("فیلم های نوروزی"))
    }

    func testEnglishTermNames() {
        XCTAssertEqual(Localizer.english(name: "اکشن", slug: "action"), "Action")
        XCTAssertEqual(Localizer.english(name: "آمریکا", slug: "united-states"), "United States")
        XCTAssertEqual(Localizer.english(name: "کشور تازه", slug: "south-korea"), "South Korea")
        XCTAssertEqual(Localizer.english(name: "Film-Noir", slug: "film-noir"), "Film-Noir")
        XCTAssertEqual(Localizer.english(name: "آهنگ", slug: "%d8%a2%d9%87%d9%86%da%af"), "Music")
        XCTAssertNil(Localizer.english(name: "واژه ناشناخته", slug: "%d9%88"))
    }

    func testDetectsPersian() {
        XCTAssertTrue(Localizer.containsPersian("Evita اویتا"))
        XCTAssertFalse(Localizer.containsPersian("Evita (1996)"))
    }
}

final class ModelTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func testDecodesLooselyTypedFilm() throws {
        let json = """
        {"id": 81141, "name": "اویتا", "en_title": false, "imdbRating": 7.3, "imdbVotes": "17,932",
         "is_paid": "0", "online_quality": {"1080": "https://dl.example/a.1080.mp4", "720": "", "480": false},
         "genres": [{"name": "درام", "id": "244", "slug": "drama"}], "countries": [],
         "film_dl": [{"version_type": "sub", "playonline": [], "data": [{"link": "https://dl.example/a.mp4",
           "quality": "1080p", "size": "2.1 GB"}]}],
         "serial_dl": [], "related": {}, "collection": [], "comments": false}
        """
        let film = try decoder.decode(FilmDetail.self, from: Data(json.utf8))
        XCTAssertEqual(film.id, 81141)
        XCTAssertNil(film.enTitle)
        XCTAssertEqual(film.imdbRating, "7.3")
        XCTAssertFalse(film.isPaid)
        XCTAssertFalse(film.isSeries)
        XCTAssertEqual(film.onlineQuality?.available.map(\.label), ["1080p"])
        XCTAssertEqual(film.filmDl.first?.data.first?.size, "2.1 GB")
        XCTAssertEqual(film.genres.first?.id, 244)
        XCTAssertTrue(film.related.isEmpty)
        XCTAssertNil(film.collection)
    }

    func testSeasonNumbers() throws {
        let season = try decoder.decode(Season.self, from: Data(#"{"season_name": "فصل 3", "episode": []}"#.utf8))
        XCTAssertEqual(season.number(fallback: 0), 3)
        let unnamed = try decoder.decode(Season.self, from: Data(#"{"episode": []}"#.utf8))
        XCTAssertEqual(unnamed.number(fallback: 1), 2)
    }

    func testSearchFilterQuery() {
        var filter = SearchFilter()
        XCTAssertEqual(filter.query, ["type_of_post": "all"])
        XCTAssertEqual(filter.count, 0)

        filter.genre = "drama"
        filter.fromYear = 2020
        filter.toYear = 2010
        filter.dubbed = true
        let query = filter.query
        XCTAssertEqual(query["genre"], "drama")
        XCTAssertEqual(query["from_year"], "2010")
        XCTAssertEqual(query["to_year"], "2020")
        XCTAssertEqual(query["has_dubbed"], "1")
        XCTAssertNil(query["has_subtitle"])
        XCTAssertEqual(filter.count, 3)
    }

    func testSearchQueryNormalizesAndTakesTheYear() {
        let query = SearchQuery("  جوكر   ۲۰۱۹ ")
        XCTAssertEqual(query.text, "جوکر")
        XCTAssertEqual(query.year, 2019)
        XCTAssertNil(SearchQuery("1917").year, "a title that is a year stays the title")
        XCTAssertEqual(SearchQuery("1917").text, "1917")
        XCTAssertEqual(SearchQuery("علي (1402)").year, 1402)
        XCTAssertNil(SearchQuery("blade runner 2049x").year)
    }

    func testSearchRanksTitleMatchesFirst() throws {
        let json = """
        [{"id": 1, "name": "داستان عامه پسند", "en_title": "Pulp Fiction"},
         {"id": 2, "name": "جوکر: جنون مشترک", "en_title": "Joker: Folie à Deux"},
         {"id": 3, "name": "جوکر", "en_title": "Joker"},
         {"id": 4, "name": "بتمن", "en_title": "The Dark Knight"}]
        """
        let posts = try decoder.decode([Post].self, from: Data(json.utf8))
        XCTAssertEqual(SearchQuery("joker").rank(posts).map(\.id), [3, 2, 1, 4])
        XCTAssertEqual(SearchQuery("جوكر").rank(posts).map(\.id), [3, 2, 1, 4])
        XCTAssertEqual(SearchQuery("dark knight").rank(posts).map(\.id), [4, 1, 2, 3])
    }

    func testArchiveFilterQuery() {
        let filter = ArchiveFilter(postType: 995, genre: 1703, year: 1402, sort: "newest")
        XCTAssertEqual(filter.query, ["type_of_post": "995", "genre": "1703", "yearr": "1402", "sort": "newest"])
    }
}

final class ThemeTests: XCTestCase {
    /// The site's blue on the dark background must be lightened to WCAG AA.
    func testAccentTextIsReadable() {
        let background = Color(hex: "#141414")!
        let readable = Theme.readable(Color(hex: "#4050b5")!, on: background)
        XCTAssertGreaterThanOrEqual(contrast(UIColor(readable), UIColor(background)), 4.5)
        // A color that is already readable stays as it is.
        let white = Theme.readable(.white, on: background)
        XCTAssertEqual(contrast(UIColor(white), .white), 1, accuracy: 0.01)
    }

    func testHexParsing() {
        XCTAssertNotNil(Color(hex: "4050b5"))
        XCTAssertNil(Color(hex: "#12345"))
        XCTAssertNil(Color(hex: nil))
    }

    func testStringHelpers() {
        XCTAssertEqual("۰۹۱۲٣".latinDigits, "09123")
        XCTAssertEqual("<p>Hi&nbsp;there &amp; you</p>".plainText, "Hi there & you")
    }

    private func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
        func luminance(_ color: UIColor) -> CGFloat {
            var (r, g, bl, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            color.getRed(&r, green: &g, blue: &bl, alpha: &alpha)
            func linear(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(bl)
        }
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

final class OfflineCacheTests: XCTestCase {
    func testStoresAndReadsBack() {
        let key = "mobile/v2/film/1?#test-\(UUID().uuidString)"
        XCTAssertNil(OfflineCache.responses.read(key))
        OfflineCache.responses.write(Data("{}".utf8), for: key)
        XCTAssertEqual(OfflineCache.responses.read(key), Data("{}".utf8))
        XCTAssertNotNil(OfflineCache.responses.date(of: key))
    }

    func testFileNamesAreStableHashes() {
        let name = OfflineCache.fileName(for: "a")
        XCTAssertEqual(name, OfflineCache.fileName(for: "a"))
        XCTAssertEqual(name.count, 64)
        XCTAssertNotEqual(name, OfflineCache.fileName(for: "b"))
    }
}
