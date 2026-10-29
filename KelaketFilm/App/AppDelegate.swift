import FirebaseCore
import FirebaseMessaging
import UIKit
import UserNotifications

/// Push notifications through Firebase Cloud Messaging.
///
/// The plugin's fcm.php sends HTTP v1 messages with a plain `notification`
/// block, which FCM delivers to iOS over APNs — no server change needed, only
/// an APNs key uploaded in the Firebase console. Firebase stays off until a
/// `GoogleService-Info.plist` is added to KelaketFilm/Resources.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        CastManager.configure()
        Task { @MainActor in DownloadManager.shared.activate() }
        BackgroundRefresh.register()
        OfflineCache.prune()

        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            return true
        }
        FirebaseApp.configure()
        Messaging.messaging().delegate = self

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        return true
    }

    /// iOS relaunched the app to deliver finished background downloads.
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            DownloadManager.shared.backgroundCompletionHandler = completionHandler
            DownloadManager.shared.activate()
        }
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // MARK: MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        for topic in Self.topics {
            messaging.subscribe(toTopic: topic)
        }
        Task { @MainActor in AppRouter.shared.pushToken = fcmToken }
    }

    /// Topics used for broadcasts from the plugin's "send notification" panel (KF_PUSH_TOPICS).
    private static var topics: [String] {
        (Bundle.main.object(forInfoDictionaryKey: "KFPushTopics") as? String ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // fcm.php puts the deep link (e.g. kelaketfilm://app/film/12392) in data.url.
        if let link = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: link) {
            Task { @MainActor in AppRouter.shared.open(url) }
        }
        completionHandler()
    }
}
