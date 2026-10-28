import AVFoundation
import SwiftUI

@main
struct KelaketFilmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var router = AppRouter.shared

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(router)
                .environment(\.layoutDirection, appState.isInternational ? .leftToRight : .rightToLeft)
                .environment(\.locale, Locale(identifier: appState.isInternational ? "en_US" : "fa_IR"))
                .preferredColorScheme(.dark)
                .tint(Theme.accentText)
                .onOpenURL { router.open($0) }
        }
    }
}
