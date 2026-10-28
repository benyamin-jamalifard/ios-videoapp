import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var home: HomeScreen?
    @Published private(set) var error: String?

    func load(api: APIClient) async {
        do {
            home = try await api.homeScreen()
            error = nil
        } catch {
            if home == nil { self.error = error.localizedDescription }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = HomeViewModel()

    var body: some View {
        Group {
            if let home = model.home {
                content(home)
            } else if let error = model.error {
                ErrorStateView(message: error) { Task { await model.load(api: appState.api) } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("کلاکت فیلم")
        .navigationBarTitleDisplayMode(.inline)
        // Reload when the session changes so "continue watching" follows the user.
        .task(id: appState.token) { await model.load(api: appState.api) }
    }

    private func content(_ home: HomeScreen) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if !home.featuredFilms.isEmpty {
                    FeaturedSlider(posts: home.featuredFilms)
                }

                let shortcuts = appState.config.customMenuList.filter { $0.archiveFilter != nil }
                if !shortcuts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, item in
                                let title = item.title ?? item.name ?? ""
                                NavigationLink {
                                    ArchiveView(title: title, filter: item.archiveFilter ?? ArchiveFilter())
                                } label: {
                                    Text(title)
                                        .font(.footnote.bold())
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(Theme.surface, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                if appState.config.watchProgressActive,
                   let progress = home.watchProgress, !progress.data.isEmpty {
                    ContinueWatchingRow(block: progress)
                }

                if let updated = home.updatedSeries, !updated.data.isEmpty {
                    PostRow(title: updated.title ?? "سریال‌های به‌روز شده", posts: updated.data)
                }

                ForEach(home.selectedCats) { category in
                    if !category.data.isEmpty {
                        PostRow(title: category.catName ?? "", posts: category.data)
                    }
                }
            }
            .padding(.vertical)
        }
        .refreshable { await model.load(api: appState.api) }
    }
}

private struct FeaturedSlider: View {
    let posts: [Post]
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                NavigationLink(value: FilmRoute(id: post.id)) {
                    ZStack(alignment: .bottomLeading) {
                        RemoteImage(url: post.wideImageURL)
                        LinearGradient(colors: [.clear, .black.opacity(0.85)],
                                       startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 4) {
                            if let badge = post.sliderBadge {
                                Text(badge)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Theme.accent, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                            Text(post.displayName)
                                .font(.title3.bold())
                                .lineLimit(1)
                            if let rating = post.imdbRating {
                                Label("IMDb \(rating)", systemImage: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .padding()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 220)
        .task(id: posts.count) {
            // Auto-advance every 5 seconds.
            while !Task.isCancelled && posts.count > 1 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                withAnimation { selection = (selection + 1) % posts.count }
            }
        }
    }
}

private struct ContinueWatchingRow: View {
    let block: WatchProgressBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(block.title ?? "ادامه تماشا")
                .font(.headline)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(block.data) { item in
                        NavigationLink(value: FilmRoute(id: item.id)) {
                            VStack(alignment: .leading, spacing: 6) {
                                RemoteImage(url: item.imageURL)
                                    .frame(width: 200, height: 112)
                                    .overlay(alignment: .bottom) {
                                        GeometryReader { geo in
                                            Rectangle()
                                                .fill(Theme.accent)
                                                .frame(width: geo.size.width * item.progress, height: 4)
                                        }
                                        .frame(height: 4)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                                Text(item.name ?? item.title ?? "")
                                    .font(.caption)
                                    .lineLimit(1)
                                if let label = item.episodeLabel ?? item.remainingLabel {
                                    Text(label)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            .frame(width: 200, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
