import SwiftUI
import UIKit

/// App colors. They follow the site's settings like the Android app does:
/// `app_main_color` for the accent and the default palette of `theme` for the
/// rest. The last colors are kept so the next launch starts in them.
enum Theme {
    private(set) static var background = Color(hex: "#141414")!
    private(set) static var surface = Color(hex: "#1c1c22")!
    private(set) static var surfaceRaised = Color(hex: "#23232b")!
    /// Fills: buttons, selected chips, progress bars (white text sits on it).
    private(set) static var accent = Color("AccentColor")
    /// The accent for text, icons and tint on the dark background. The site's
    /// blue is too dark to read there, so it is lightened to WCAG AA (4.5:1).
    private(set) static var accentText = readable(Color("AccentColor"), on: Color(hex: "#141414")!)
    private(set) static var muted = Color(hex: "#a4a4af")!
    /// Secondary text that must stay readable on `surface` (captions, metadata).
    static let secondaryText = Color.white.opacity(0.72)
    static let dubbed = Color(hex: "#6cc4ff")!
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
        accentText = readable(accent, on: background)
    }

    /// Mixes `color` with white until it reaches a 4.5:1 contrast on `background`.
    static func readable(_ color: Color, on background: Color) -> Color {
        // Asset-catalog colors are dynamic; resolve them for the app's dark mode.
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let base = UIColor(color).resolvedColor(with: dark)
        let backdrop = UIColor(background).resolvedColor(with: dark)
        var mix: CGFloat = 0
        var candidate = base
        while contrast(candidate, backdrop) < 4.5 && mix < 1 {
            mix += 0.05
            candidate = blend(base, with: .white, amount: mix)
        }
        return Color(candidate)
    }

    private static func blend(_ color: UIColor, with other: UIColor, amount: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount,
                       blue: b1 + (b2 - b1) * amount, alpha: 1)
    }

    private static func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func luminance(_ color: UIColor) -> CGFloat {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}

extension Bundle {
    /// The app's name as shown under its icon.
    var displayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
    }

    /// The name shown inside the app: the English one in the English app.
    var appName: String {
        guard Region.isInternational else { return displayName }
        let english = (object(forInfoDictionaryKey: "KFAppNameEn") as? String ?? "").trimmingCharacters(in: .whitespaces)
        return english.isEmpty || english.hasPrefix("$(") ? "Gite Movie" : english
    }

    /// The name shown inside the app: the English one in the English app.
    var appName: String {
        guard Region.isInternational else { return displayName }
        let english = (object(forInfoDictionaryKey: "KFAppNameEn") as? String ?? "").trimmingCharacters(in: .whitespaces)
        return english.isEmpty || english.hasPrefix("$(") ? "Gite Movie" : english
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
