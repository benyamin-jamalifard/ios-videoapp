import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var network = NetworkStatus.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if appState.isConfigLoaded {
                TabView(selection: $router.tab) {
                    NavigationStack(path: $router.homePath) { HomeView().withFilmDestination() }
                        .tabItem { Label(L("خانه", "Home"), systemImage: "house.fill") }
                        .tag(AppTab.home)

                    // Same tabs, in the same order, as the Android app; the blog
                    // moved into the categories tab to make room for downloads.
                    NavigationStack { SearchView().withFilmDestination() }
                        .tabItem { Label(L("جستجو", "Search"), systemImage: "magnifyingglass") }
                        .tag(AppTab.search)

                    NavigationStack { ExploreView().withFilmDestination() }
                        .tabItem { Label(L("دسته بندی", "Browse"), systemImage: "square.grid.2x2.fill") }
                        .tag(AppTab.explore)

                    if !appState.isInternational {
                        NavigationStack { DownloadsView() }
                            .tabItem { Label("دانلودها", systemImage: "arrow.down.circle.fill") }
                            .tag(AppTab.downloads)
                    }

                    NavigationStack { ProfileView().withFilmDestination() }
                        .tabItem {
                            Label(L("پروفایل", "More"),
                                  systemImage: appState.isInternational ? "ellipsis.circle" : "person.crop.circle")
                        }
                        .tag(AppTab.profile)
                }
                .tint(Theme.accentText)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !network.serverReachable {
                        OfflineBanner()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut, value: network.serverReachable)
                // A video playing on the TV stays reachable from every tab.
                .overlay(alignment: .bottom) {
                    CastMiniBar().padding(.bottom, 52)
                }
            } else {
                SplashView()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .task {
            await appState.bootstrap()
            #if DEBUG
            // CI screenshots: `-kf.open kelaketfilm://app/tab/search` opens a screen
            // without the system's "Open in" prompt that `simctl openurl` raises.
            if let link = UserDefaults.standard.string(forKey: "kf.open"), let url = URL(string: link) {
                router.open(url)
            }
            #endif
        }
        // Tie the device to the account whenever either the FCM token or the user changes.
        .task(id: "\(router.pushToken ?? "")|\(appState.token ?? "")") {
            guard appState.isSignedIn, let pushToken = router.pushToken else { return }
            try? await appState.api.syncPushToken(pushToken)
        }
        .sheet(item: $router.webLink) { link in
            WebPageView(url: link.url, title: link.title)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                network.appBecameActive()
            case .background:
                network.appMovedToBackground()
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
    }
}

/// Shown while the site is out of reach and saved copies are on screen.
private struct OfflineBanner: View {
    @ObservedObject private var network = NetworkStatus.shared
    @ObservedObject private var downloads = DownloadManager.shared
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: network.hasConnection ? "icloud.slash" : "wifi.slash")
            Text(network.hasConnection
                 ? L("سرور در دسترس نیست؛ نسخه ذخیره‌شده نمایش داده می‌شود", "Can't reach the server; showing saved content")
                 : L("اینترنت قطع است؛ نسخه ذخیره‌شده نمایش داده می‌شود", "You're offline; showing saved content"))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 4)
            if !appState.isInternational, downloads.items.contains(where: { $0.state == .completed }) {
                Button(L("دانلودها", "Downloads")) { router.tab = .downloads }
                    .font(.caption.bold())
            }
            Button { network.refresh() } label: {
                Image(systemName: "arrow.clockwise").font(.caption.bold())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.85))
    }
}

private struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 160)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    func withFilmDestination() -> some View {
        navigationDestination(for: FilmRoute.self) { route in
            FilmDetailView(id: route.id)
        }
    }
}
