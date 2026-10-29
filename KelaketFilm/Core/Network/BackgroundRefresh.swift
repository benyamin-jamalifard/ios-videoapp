import BackgroundTasks
import Foundation

/// iOS wakes the app now and then to fetch the home lists and their posters,
/// so the app opens on fresh content, and a recent copy is on the phone if
/// the site goes out of reach (internet shutdowns).
enum BackgroundRefresh {
    static var identifier: String { (Bundle.main.bundleIdentifier ?? "kelaketfilm") + ".refresh" }

    /// Call from `didFinishLaunching`, before launch ends.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()
            let work = Task {
                let home = try? await APIClient.shared.homeScreen()
                _ = try? await APIClient.shared.config()
                if let home {
                    let posts = home.featuredFilms + home.selectedCats.flatMap(\.data) + (home.updatedSeries?.data ?? [])
                    let urls = posts.compactMap(\.posterURL)
                    await ImageLoader.shared.prefetch(Array(urls.prefix(80)))
                }
                task.setTaskCompleted(success: home != nil)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// Asks for the next run in about an hour; iOS picks the actual time.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
