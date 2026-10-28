import Foundation

/// `GET mobile/v2/config` — admin-controlled switches from the app plugin.
/// Only the fields the iOS app uses are decoded.
struct AppConfig: Decodable {
    /// "sms" (OTP) or "email" (username + password)
    @LossyString var authMethod: String?
    /// When on, the login screen also offers the other method.
    @LossyBool var secondLoginMethod: Bool

    @LossyBool var activeVip: Bool
    @LossyString var vipSystem: String?
    @LossyArray var vipLock: [String]
    @LossyBool var requireLoginPosts: Bool

    @LossyString var adminMessageTitle: String?
    @LossyString var adminMessage: String?

    @LossyString var appLogo: String?
    @LossyString var appMainColor: String?
    @LossyObject var theme: ThemeConfig?

    /// The app color palettes from the theme settings.
    struct ThemeConfig: Decodable, Hashable {
        @LossyString var defaultPalette: String?
        @LossyObject var palettes: [String: Palette]?

        var defaultColors: Palette.Colors? {
            guard let palettes else { return nil }
            return (defaultPalette.flatMap { palettes[$0] } ?? palettes.values.first)?.colors
        }

        struct Palette: Decodable, Hashable {
            @LossyObject var colors: Colors?

            struct Colors: Decodable, Hashable {
                @LossyString var primaryColor: String?
                @LossyString var appBg: String?
                @LossyString var surface1: String?
                @LossyString var surface2: String?
                @LossyString var mutedTextColor: String?
            }
        }
    }

    @LossyBool var activeShare: Bool
    @LossyBool var showWeekly: Bool
    @LossyBool var watchProgressActive: Bool
    @LossyString var watchProgressTitle: String?

    @LossyString var rulesLink: String?
    @LossyString var privacyLink: String?
    @LossyString var telegram: String?
    @LossyString var instagram: String?

    // Profile menu switches
    @LossyBool var kelaketappShowMylist: Bool
    @LossyBool var profileShowTickets: Bool
    @LossyBool var profileShowRequestFilm: Bool
    @LossyArray var ticketDeps: [TicketDepartment]
    @LossyBool var appTicketNeedVip: Bool
    @LossyBool var appReqsNeedVip: Bool
    @LossyBool var kelaketappShowTrans: Bool
    @LossyBool var profileShowActiveSession: Bool
    /// Theme options; the routes return errors while these are off.
    @LossyBool var walletEnabled: Bool
    @LossyBool var referralEnabled: Bool

    /// Adds the blog tab.
    @LossyBool var activeBlog: Bool

    // Explore switches
    @LossyBool var kelaketappShowBoxoffice: Bool
    @LossyBool var kelaketappShowActorsArchive: Bool
    /// Shortcuts the admin adds under "custom menu items".
    @LossyArray var customMenuList: [MenuItem]

    struct MenuItem: Decodable, Hashable {
        @LossyString var title: String?
        /// "custom_filter" for taxonomy shortcuts; other types are app sections.
        @LossyString var type: String?
        @LossyString var name: String?
        @LossyString var taxonomy: String?
        @LossyInt var termId: Int?

        /// The archive filter for a `custom_filter` item, nil for anything else.
        var archiveFilter: ArchiveFilter? {
            guard type == "custom_filter", let termId else { return nil }
            switch taxonomy {
            case "genre": return ArchiveFilter(genre: termId)
            case "type_of_post": return ArchiveFilter(postType: termId)
            case "yearr": return ArchiveFilter(year: termId)
            case "country": return ArchiveFilter(country: termId)
            case "category": return ArchiveFilter(category: termId)
            case "actor": return ArchiveFilter(actor: termId)
            default: return nil
            }
        }
    }

    /// Used until the real config arrives, or when it cannot be fetched.
    static let fallback: AppConfig = {
        let json = """
        {"authMethod": "sms", "secondLoginMethod": true, "watchProgressActive": true,
         "kelaketappShowMylist": true, "profileShowTickets": true, "profileShowRequestFilm": true,
         "kelaketappShowTrans": true, "profileShowActiveSession": true,
         "kelaketappShowBoxoffice": true, "kelaketappShowActorsArchive": true}
        """
        // Every field is lossy, so this cannot fail.
        return try! JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    }()

    var usesOTP: Bool { authMethod == "sms" }
}
