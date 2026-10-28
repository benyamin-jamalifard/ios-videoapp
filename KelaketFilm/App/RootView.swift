import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: AppRouter
    @Environment(\.openURL) private var openURL
    @State private var showAdminMessage = false

    var body: some View {
        Group {
            if appState.isConfigLoaded {
                TabView(selection: $router.tab) {
                    NavigationStack(path: $router.homePath) { HomeView().withFilmDestination() }
                        .tabItem { Label("خانه", systemImage: "house.fill") }
                        .tag(AppTab.home)

                    NavigationStack { ExploreView().withFilmDestination() }
                        .tabItem { Label("کاوش", systemImage: "square.grid.2x2.fill") }
                        .tag(AppTab.explore)

                    NavigationStack { SearchView().withFilmDestination() }
                        .tabItem { Label("جستجو", systemImage: "magnifyingglass") }
                        .tag(AppTab.search)

                    if appState.config.activeBlog {
                        NavigationStack { BlogListView() }
                            .tabItem { Label("وبلاگ", systemImage: "newspaper") }
                            .tag(AppTab.blog)
                    }

                    NavigationStack { ProfileView().withFilmDestination() }
                        .tabItem { Label("پروفایل", systemImage: "person.crop.circle") }
                        .tag(AppTab.profile)
                }
                .onAppear {
                    showAdminMessage = appState.config.adminMessage != nil
                }
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
        .onChange(of: router.externalURL) { url in
            guard let url else { return }
            openURL(url)
            router.externalURL = nil
        }
        .alert(appState.config.adminMessageTitle ?? "پیام",
               isPresented: $showAdminMessage) {
            Button("باشه", role: .cancel) {}
        } message: {
            Text(appState.config.adminMessage?.plainText ?? "")
        }
    }
}

private struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
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
