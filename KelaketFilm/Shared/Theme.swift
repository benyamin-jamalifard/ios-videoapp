import SwiftUI

enum Theme {
    static let background = Color(red: 0.05, green: 0.05, blue: 0.06)
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let surfaceRaised = Color(red: 0.16, green: 0.16, blue: 0.19)
    static let accent = Color("AccentColor")
    static let muted = Color.white.opacity(0.6)
    static let cornerRadius: CGFloat = 12
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
