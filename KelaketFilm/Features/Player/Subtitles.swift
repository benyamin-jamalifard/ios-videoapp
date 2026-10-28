import Foundation

/// One timed line of a WebVTT or SRT file.
struct SubtitleCue: Equatable {
    let start: Double
    let end: Double
    let text: String
}

/// AVPlayer cannot attach an external subtitle file to a progressive MP4,
/// so the player loads the site's soft subtitles itself and draws the cues.
enum Subtitles {
    static func load(from url: URL) async -> [SubtitleCue] {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        return parse(decode(data))
    }

    /// Persian SRT files are often saved as Windows-1256 rather than UTF-8.
    static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        let cp1256 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.windowsArabic.rawValue)))
        return String(data: data, encoding: cp1256) ?? String(decoding: data, as: UTF8.self)
    }

    /// Parses both formats: blocks separated by blank lines, each with a
    /// `start --> end` line followed by the text.
    static func parse(_ text: String) -> [SubtitleCue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timingIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = seconds(parts[0]),
                  let end = seconds(parts[1].split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? "")
            else { continue }
            let body = lines[(timingIndex + 1)...]
                .map(stripTags)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                cues.append(SubtitleCue(start: start, end: end, text: body))
            }
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// The cue showing at `time`, if any.
    static func cue(at time: Double, in cues: [SubtitleCue]) -> SubtitleCue? {
        // Binary search for the last cue starting at or before `time`.
        var low = 0, high = cues.count - 1, found = -1
        while low <= high {
            let mid = (low + high) / 2
            if cues[mid].start <= time { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        guard found >= 0, cues[found].end >= time else { return nil }
        return cues[found]
    }

    /// "01:02:03.456", "02:03.456" or SRT's "01:02:03,456".
    private static func seconds(_ raw: String) -> Double? {
        let parts = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
            .split(separator: ":")
            .compactMap { Double($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        default: return nil
        }
    }

    private static func stripTags(_ line: String) -> String {
        line.replacingOccurrences(of: "<[^>]+>|\\{\\\\[^}]+\\}", with: "", options: .regularExpression)
    }
}
