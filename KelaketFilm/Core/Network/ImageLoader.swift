import UIKit

/// Loads posters and backdrops through a memory cache and the offline disk
/// cache. Image addresses never change content, so a saved copy is used
/// without asking the server again; that also keeps them on screen offline.
actor ImageLoader {
    static let shared = ImageLoader()

    private static let memory: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 120_000_000
        return cache
    }()

    private var running: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration)
    }()

    /// Already decoded, for drawing without a placeholder flash.
    nonisolated static func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = Self.cachedImage(for: url) { return cached }
        if let task = running[url] { return await task.value }

        let session = self.session
        let task = Task<UIImage?, Never>.detached(priority: .userInitiated) {
            let key = url.absoluteString
            if let data = OfflineCache.images.read(key), let image = Self.decode(data) {
                return image
            }
            guard let (data, response) = try? await session.data(from: url),
                  ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400,
                  let image = Self.decode(data)
            else { return nil }
            OfflineCache.images.write(data, for: key)
            return image
        }
        running[url] = task
        let image = await task.value
        running[url] = nil
        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            Self.memory.setObject(image, forKey: url as NSURL, cost: cost)
        }
        return image
    }

    /// Fetches into the disk cache without decoding for the screen (background refresh).
    func prefetch(_ urls: [URL]) async {
        for url in urls where OfflineCache.images.read(url.absoluteString) == nil {
            if let (data, response) = try? await session.data(from: url),
               ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400 {
                OfflineCache.images.write(data, for: url.absoluteString)
            }
        }
    }

    /// Decodes off the main thread so scrolling stays smooth.
    private nonisolated static func decode(_ data: Data) -> UIImage? {
        UIImage(data: data)?.preparingForDisplay()
    }
}
