import SwiftUI

/// App colors. They follow the site's settings like the Android app does:
/// `app_main_color` for the accent and the default palette of `theme` for the
/// rest. The last colors are kept so the next launch starts in them.
enum Theme {
    private(set) static var background = Color(hex: "#141414")!
    private(set) static var surface = Color(hex: "#1c1c22")!
    private(set) static var surfaceRaised = Color(hex: "#23232b")!
    private(set) static var accent = Color("AccentColor")
    private(set) static var muted = Color(hex: "#a4a4af")!
    static let cornerRadius: CGFloat = 16

    private static let storageKey = "kf.themeColors"

    /// Call once at launch, before any view reads a color.
    static func restore() {
        guard let saved = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] else { return }
        set(saved)
    }

    static func apply(_ config: AppConfig) {
        var colors: [String: String] = [:]
        if let palette = config.theme?.defaultColors {
            colors["background"] = palette.appBg
            colors["surface"] = palette.surface1
            colors["surfaceRaised"] = palette.surface2
            colors["muted"] = palette.mutedTextColor
            colors["accent"] = palette.primaryColor
        }
        if let main = config.appMainColor { colors["accent"] = main }
        set(colors)
        UserDefaults.standard.set(colors, forKey: storageKey)
    }

    private static func set(_ colors: [String: String]) {
        if let color = Color(hex: colors["background"]) { background = color }
        if let color = Color(hex: colors["surface"]) { surface = color }
        if let color = Color(hex: colors["surfaceRaised"]) { surfaceRaised = color }
        if let color = Color(hex: colors["muted"]) { muted = color }
        if let color = Color(hex: colors["accent"]) { accent = color }
    }
}

extension Bundle {
    /// The app's name as shown under its icon.
    var displayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
    }
}

extension Color {
    /// Parses "#rrggbb" / "rrggbb" as sent by the plugin's color options.
    init?(hex: String?) {
        guard var hex = hex?.trimmingCharacters(in: .whitespaces), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

extension String {
    /// Persian/Arabic digits to ASCII, so "۰۹۱۲…" works as a phone number or OTP.
    var latinDigits: String {
        let digits: [Character: Character] = [
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
            "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
        ]
        return String(map { digits[$0] ?? $0 })
    }

    /// Strips HTML tags and entities that ACF text fields sometimes carry.
    var plainText: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
