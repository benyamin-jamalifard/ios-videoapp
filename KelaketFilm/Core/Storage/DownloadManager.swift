import Foundation

/// A video saved for offline viewing.
struct DownloadItem: Codable, Identifiable, Hashable {
    enum State: String, Codable {
        case downloading, paused, completed, failed
    }

    var id = UUID().uuidString
    let postId: Int
    let title: String
    var episodeLabel: String?
    var posterURL: URL?
    let remoteURL: URL
    var remoteSubtitleURL: URL?
    var quality: String?
    /// "film" or "series", for watch progress.
    var contentType = "film"
    var seasonNo = 0
    var episodeNo = 0
    var movieRowNo = 0
    var state = State.downloading
    var receivedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var fileName: String?
    var subtitleFileName: String?
    var createdAt = Date()

    var progress: Double {
        totalBytes > 0 ? min(1, Double(receivedBytes) / Double(totalBytes)) : 0
    }
}

/// Where downloads live: Application Support, out of the Files app and iCloud backup.
enum DownloadStore {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var url = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }()

    static var indexURL: URL { directory.appendingPathComponent("index.json") }

    static func file(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static func resumeDataURL(for id: String) -> URL { file("\(id).resume") }

    /// Video file name for a download: its id plus the remote extension.
    static func videoName(id: String, remote: URL?) -> String {
        let ext = remote?.pathExtension.lowercased() ?? ""
        return "\(id).\(ext.isEmpty || ext.count > 5 ? "mp4" : ext)"
    }
}

/// The in-app downloader. A background URLSession keeps going while the app is
/// suspended; paused downloads continue from where they stopped when the
/// server supports ranges.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var items: [DownloadItem] = []
    /// From `application(_:handleEventsForBackgroundURLSession:)`.
    var backgroundCompletionHandler: (() -> Void)?

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var lastProgressSave = Date.distantPast

    private lazy var session: URLSession = {
        let identifier = (Bundle.main.bundleIdentifier ?? "kelaketfilm") + ".downloads"
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.timeoutIntervalForRequest = 120
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    override private init() {
        super.init()
        if let data = try? Data(contentsOf: DownloadStore.indexURL),
           let saved = try? JSONDecoder().decode([DownloadItem].self, from: data) {
            items = saved
        }
    }

    /// Reconnects to downloads that ran while the app was closed. Call at launch.
    func activate() {
        session.getAllTasks { tasks in
            let running = tasks.compactMap { $0 as? URLSessionDownloadTask }
            Task { @MainActor in self.reconnect(running) }
        }
    }

    private func reconnect(_ running: [URLSessionDownloadTask]) {
        for task in running {
            guard let id = task.taskDescription, items.contains(where: { $0.id == id }) else {
                task.cancel()
                continue
            }
            tasks[id] = task
        }
        // A download marked running with no task was stopped by the system: let the user resume it.
        for index in items.indices where items[index].state == .downloading && tasks[items[index].id] == nil {
            items[index].state = .paused
        }
        save()
    }

    // MARK: Queries

    func item(for remoteURL: URL) -> DownloadItem? {
        items.first { $0.remoteURL == remoteURL }
    }

    func localURL(of item: DownloadItem) -> URL? {
        guard item.state == .completed, let name = item.fileName else { return nil }
        let url = DownloadStore.file(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Bytes used by finished downloads.
    var usedBytes: Int64 {
        items.reduce(0) { total, item in
            guard let url = localURL(of: item),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else { return total }
            return total + Int64(size)
        }
    }

    func playbackItem(for item: DownloadItem) -> PlaybackItem? {
        guard let url = localURL(of: item) else { return nil }
        let subtitle = item.subtitleFileName.map(DownloadStore.file)
        return PlaybackItem(url: url,
                            title: item.title,
                            postId: item.postId,
                            contentType: item.contentType,
                            seasonNo: item.seasonNo,
                            episodeNo: item.episodeNo,
                            movieRowNo: item.movieRowNo,
                            subtitleURL: subtitle.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil },
                            posterURL: item.posterURL,
                            isOffline: true)
    }

    // MARK: Actions

    func start(_ item: DownloadItem) {
        if let existing = self.item(for: item.remoteURL) {
            if existing.state == .paused || existing.state == .failed { resume(existing.id) }
            return
        }
        var item = item
        item.state = .downloading
        items.insert(item, at: 0)
        begin(item.id, resumeData: nil)
        if let subtitle = item.remoteSubtitleURL {
            Task { await downloadSubtitle(subtitle, for: item.id) }
        }
        save()
    }

    func pause(_ id: String) {
        guard let task = tasks[id] else { return }
        update(id) { $0.state = .paused }
        tasks[id] = nil
        task.cancel(byProducingResumeData: { data in
            if let data { try? data.write(to: DownloadStore.resumeDataURL(for: id)) }
        })
    }

    func resume(_ id: String) {
        guard let item = items.first(where: { $0.id == id }), item.state != .completed else { return }
        let resumeURL = DownloadStore.resumeDataURL(for: id)
        let data = try? Data(contentsOf: resumeURL)
        try? FileManager.default.removeItem(at: resumeURL)
        update(id) { $0.state = .downloading }
        begin(id, resumeData: data)
    }

    func delete(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        if let item = items.first(where: { $0.id == id }) {
            for name in [item.fileName, item.subtitleFileName, "\(id).resume"].compactMap({ $0 }) {
                try? FileManager.default.removeItem(at: DownloadStore.file(name))
            }
        }
        items.removeAll { $0.id == id }
        save()
    }

    private func begin(_ id: String, resumeData: Data?) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let task = resumeData.map { session.downloadTask(withResumeData: $0) }
            ?? session.downloadTask(with: item.remoteURL)
        task.taskDescription = id
        tasks[id] = task
        task.resume()
    }

    private func downloadSubtitle(_ url: URL, for id: String) async {
        guard let (temporary, response) = try? await URLSession.shared.download(from: url),
              ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400
        else { return }
        let ext = url.pathExtension.isEmpty ? "vtt" : url.pathExtension.lowercased()
        let name = "\(id).\(ext)"
        let destination = DownloadStore.file(name)
        try? FileManager.default.removeItem(at: destination)
        guard (try? FileManager.default.moveItem(at: temporary, to: destination)) != nil else { return }
        update(id) { $0.subtitleFileName = name }
        save()
    }

    // MARK: State

    private func update(_ id: String, _ change: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: DownloadStore.indexURL, options: .atomic)
    }

    fileprivate func progressChanged(_ id: String, received: Int64, total: Int64) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].state == .downloading
        else { return }
        items[index].receivedBytes = received
        if total > 0 { items[index].totalBytes = total }
        if Date().timeIntervalSince(lastProgressSave) > 5 {
            lastProgressSave = Date()
            save()
        }
    }

    fileprivate func finished(_ id: String, fileName: String?, error: String?) {
        tasks[id] = nil
        update(id) { item in
            if let fileName {
                item.fileName = fileName
                item.state = .completed
                item.receivedBytes = max(item.receivedBytes, item.totalBytes)
            } else if item.state == .downloading, error != nil {
                item.state = .failed
            }
        }
        save()
    }

    fileprivate func finishBackgroundEvents() {
        backgroundCompletionHandler?()
        backgroundCompletionHandler = nil
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        Task { @MainActor in
            self.progressChanged(id, received: totalBytesWritten, total: totalBytesExpectedToWrite)
        }
    }

    /// The temporary file is deleted when this returns, so it is moved right here.
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        guard status < 400 else {
            Task { @MainActor in self.finished(id, fileName: nil, error: "HTTP \(status)") }
            return
        }
        let name = DownloadStore.videoName(id: id, remote: downloadTask.originalRequest?.url)
        let destination = DownloadStore.file(name)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            Task { @MainActor in self.finished(id, fileName: name, error: nil) }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in self.finished(id, fileName: nil, error: message) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        // Keep what was downloaded so "retry" continues instead of starting over.
        if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            try? data.write(to: DownloadStore.resumeDataURL(for: id))
        }
        let cancelled = (error as NSError).code == NSURLErrorCancelled
        let message = error.localizedDescription
        Task { @MainActor in
            // Pausing and deleting cancel the task too; those already updated the item.
            if !cancelled { self.finished(id, fileName: nil, error: message) }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in self.finishBackgroundEvents() }
    }
}

extension Int64 {
    /// "1.2 GB", "350 MB".
    var byteText: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
