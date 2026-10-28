import FirebaseAnalytics
import FirebaseCore

/// Firebase Analytics, reporting into the same Firebase project as the
/// Android app. Sessions, active users and devices are collected
/// automatically; these events add what people watch and search for.
/// Does nothing until GoogleService-Info.plist is in the app.
enum AppAnalytics {
    private static var isOn: Bool { FirebaseApp.app() != nil }

    static func viewedTitle(id: Int, name: String) {
        guard isOn else { return }
        Analytics.logEvent(AnalyticsEventViewItem, parameters: [
            AnalyticsParameterItemID: String(id),
            AnalyticsParameterItemName: name,
        ])
    }

    static func startedPlayback(id: Int, name: String, contentType: String) {
        guard isOn else { return }
        Analytics.logEvent("play_video", parameters: [
            AnalyticsParameterItemID: String(id),
            AnalyticsParameterItemName: name,
            AnalyticsParameterContentType: contentType,
        ])
    }

    static func searched(_ text: String) {
        guard isOn, !text.isEmpty else { return }
        Analytics.logEvent(AnalyticsEventSearch, parameters: [AnalyticsParameterSearchTerm: text])
    }

    static func signedIn(method: String) {
        guard isOn else { return }
        Analytics.logEvent(AnalyticsEventLogin, parameters: [AnalyticsParameterMethod: method])
    }
}
