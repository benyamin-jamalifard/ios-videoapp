import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var home: HomeScreen?
    @Published private(set) var error: String?

    func load(api: APIClient) async {
        do {
            home = try await api.homeScreen()
            error = nil
        } catch is CancellationError {
            // Superseded or the screen closed: not an error to show.
        } catch {
            if home == nil { self.error = error.localizedDescription }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model = HomeViewModel()
    @ObservedObject private var network = NetworkStatus.shared
    @ObservedObject private var downloads = DownloadManager.shared

    var body: some View {
        Group {
            if let home = model.home {
                content(home)
            } else if let error = model.error {
                VStack(spacing: 0) {
                    ErrorStateView(message: error) { Task { await model.load(api: appState.api) } }
                    // Nothing saved yet and no connection: the downloads still play.
                    if !appState.isInternational, downloads.items.contains(where: { $0.state == .completed }) {
                        Button { router.tab = .downloads } label: {
                            Label("تماشای فیلم‌های دانلودشده", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 40)
                        .padding(.bottom, 60)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image("Logo").resizable().scaledToFit().frame(height: 30)
                    Text(Bundle.main.displayName).font(.headline)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !appState.isInternational {
                    NavigationLink { NotificationsView() } label: {
                        Image(systemName: "bell")
                    }
                }
            }
        }
        // Reload when the session changes so "continue watching" follows the user.
        // Also reloads when the site comes back after an outage, after time
        // away, and every few minutes, so the lists stay current.
        .task(id: "\(appState.token ?? "")|\(network.refreshToken)") { await model.load(api: appState.api) }
    }

    private func content(_ home: HomeScreen) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if !home.featuredFilms.isEmpty {
                    FeaturedSlider(posts: home.featuredFilms)
                }

                if appState.config.showWeekly {
                    NavigationLink { WeeklyScheduleView() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.title3)
                                .foregroundStyle(Theme.accentText)
                            Text(L("برنامه پخش هفتگی سریال‌ها", "Weekly TV schedule")).font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                        .padding(.horizontal)
                    }
                    .buttonStyle(.plain)
                }

                if !appState.isInternational, let message = appState.config.adminMessage {
                    AdminMessageCard(title: appState.config.adminMessageTitle, message: message)
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

                if appState.config.watchProgressActive, !appState.isInternational,
                   let progress = home.watchProgress, !progress.data.isEmpty {
                    ContinueWatchingRow(block: progress)
                }

                if let updated = home.updatedSeries, !updated.data.isEmpty {
                    PostRow(title: appState.isInternational ? "Recently Updated Series" : updated.title ?? "سریال‌های به‌روز شده",
                            posts: updated.data)
                }

                ForEach(home.selectedCats) { category in
                    if !category.data.isEmpty {
                        PostRow(title: Localizer.title(category.catName), posts: category.data,
                                seeAll: category.archiveFilter)
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

    /// The "modern" slider of the Android app: the poster in the middle over a
    /// blurred copy of itself, with the title and rating/year under it.
    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                NavigationLink { FilmDetailView(id: post.id) } label: {
                    VStack(spacing: 12) {
                        RemoteImage(url: post.posterURL)
                            .frame(width: 190, height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay(alignment: .topLeading) { PosterBadges(post: post).padding(8) }
                            .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
                        Text(post.displayName)
                            .font(.title3.bold())
                            .lineLimit(1)
                            .padding(.horizontal, 24)
                        HStack(spacing: 10) {
                            if let rating = post.imdbRating {
                                Text(rating).foregroundStyle(.yellow)
                            }
                            if post.imdbRating != nil && post.released != nil {
                                Text("|").foregroundStyle(Theme.muted)
                            }
                            if let year = post.released { Text(year) }
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 400)
        .background {
            // Blurred backdrop of the current poster, fading into the page.
            if posts.indices.contains(selection) {
                RemoteImage(url: posts[selection].wideImageURL ?? posts[selection].posterURL)
                    .blur(radius: 30)
                    .overlay(LinearGradient(colors: [.black.opacity(0.2), Theme.background],
                                            startPoint: .top, endPoint: .bottom))
                    .clipped()
                    .animation(.easeInOut, value: selection)
            }
        }
        .task(id: posts.count) {
            // Auto-advance every 5 seconds.
            while !Task.isCancelled && posts.count > 1 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                withAnimation { selection = (selection + 1) % posts.count }
            }
        }
    }
}

/// The admin's notice, shown as a card like the Android app (not a pop-up).
private struct AdminMessageCard: View {
    let title: String?
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "megaphone.fill").foregroundStyle(Theme.accentText)
                if let title { Text(title).font(.subheadline.bold()) }
            }
            Text(Self.markdown(message.plainText))
                .font(.footnote)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(alignment: .trailing) {
            // Accent strip on the leading (right, in RTL) edge.
            RoundedRectangle(cornerRadius: 2).fill(Theme.accent).frame(width: 3).padding(.vertical, 12)
        }
        .padding(.horizontal)
    }

    /// Admins write **bold** in the message; render it instead of showing asterisks.
    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct ContinueWatchingRow: View {
    let block: WatchProgressBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: block.title ?? "ادامه تماشا")
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(block.data) { item in
                        NavigationLink { FilmDetailView(id: item.id) } label: {
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
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                if let label = item.episodeLabel ?? item.remainingLabel {
                                    Text(label)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
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
