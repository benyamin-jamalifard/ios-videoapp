import CryptoKit
import Foundation

/// Keeps the last good copy of every API response and image on disk, so the
/// app still shows its lists, film pages and posters when the server can't be
/// reached (an internet shutdown, a filtered address, no signal).
enum OfflineCache {
    private static let root: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Offline", isDirectory: true)
    }()

    static let responses = Store(directory: root.appendingPathComponent("api", isDirectory: true),
                                 maxBytes: 60_000_000)
    static let images = Store(directory: root.appendingPathComponent("images", isDirectory: true),
                              maxBytes: 350_000_000)

    /// Stable file name for a cache key.
    static func fileName(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Trims both stores to their size limits, oldest first. Run at launch.
    static func prune() {
        DispatchQueue.global(qos: .utility).async {
            responses.prune()
            images.prune()
        }
    }

    struct Store: @unchecked Sendable {
        let directory: URL
        let maxBytes: Int

        init(directory: URL, maxBytes: Int) {
            self.directory = directory
            self.maxBytes = maxBytes
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        func url(for key: String) -> URL {
            directory.appendingPathComponent(OfflineCache.fileName(for: key))
        }

        func read(_ key: String) -> Data? {
            try? Data(contentsOf: url(for: key))
        }

        /// When the copy was saved, for "last updated" notes.
        func date(of key: String) -> Date? {
            (try? url(for: key).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }

        func write(_ data: Data, for key: String) {
            try? data.write(to: url(for: key), options: .atomic)
        }

        func prune() {
            let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys)
            else { return }
            let entries = files.compactMap { file -> (URL, Date, Int)? in
                guard let values = try? file.resourceValues(forKeys: Set(keys)) else { return nil }
                return (file, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
            }
            var total = entries.reduce(0) { $0 + $1.2 }
            for entry in entries.sorted(by: { $0.1 < $1.1 }) where total > maxBytes {
                try? FileManager.default.removeItem(at: entry.0)
                total -= entry.2
            }
        }
    }
}
