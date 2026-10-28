import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: AppRouter

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
            } else {
                SplashView()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .task { await appState.bootstrap() }
        // Tie the device to the account whenever either the FCM token or the user changes.
        .task(id: "\(router.pushToken ?? "")|\(appState.token ?? "")") {
            guard appState.isSignedIn, let pushToken = router.pushToken else { return }
            try? await appState.api.syncPushToken(pushToken)
        }
        .sheet(item: $router.webLink) { link in
            WebPageView(url: link.url, title: link.title)
        }
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
