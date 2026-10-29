import SwiftUI

/// The "دسته بندی" tab, laid out like the Android app: post-type chips over a
/// grid of genre cards, plus the sections the Android side menu links to.
struct ExploreView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var network = NetworkStatus.shared
    @State private var genres: [Genre] = []
    @State private var postTypes: [FilterTerm] = []
    @State private var selectedType: Int?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !postTypes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip(L("همه", "All"), selected: selectedType == nil) { selectedType = nil }
                            ForEach(postTypes) { type in
                                chip(type.displayName, selected: selectedType == type.termId) {
                                    selectedType = type.termId
                                }
                            }
                        }
                        .padding(6)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
                        .padding(.horizontal)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        shortcut(L("آرشیو", "All titles"), icon: "square.grid.2x2") {
                            ArchiveView(title: L("آرشیو", "All titles"), filter: ArchiveFilter(postType: selectedType))
                        }
                        if appState.config.kelaketappShowActorsArchive {
                            shortcut(L("آرشیو بازیگران", "Actors"), icon: "person.2") { ActorsArchiveView() }
                        }
                        if appState.config.showWeekly {
                            shortcut(L("جدول پخش سریال‌ها", "TV schedule"), icon: "calendar.badge.clock") { WeeklyScheduleView() }
                        }
                        if appState.config.kelaketappShowBoxoffice {
                            shortcut(L("باکس آفیس", "Box office"), icon: "chart.line.uptrend.xyaxis") { BoxOfficeView() }
                        }
                        shortcut(L("۲۵۰ برتر IMDb", "IMDb Top 250"), icon: "trophy") { Top250View() }
                        shortcut(L("کالکشن‌ها", "Collections"), icon: "square.stack.3d.up") { CollectionsView() }
                        if !appState.isInternational {
                            shortcut("لیست‌های کاربران", icon: "list.star") { PublicListsView() }
                            if appState.config.activeBlog {
                                shortcut("وبلاگ", icon: "newspaper") { BlogListView() }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(genres) { genre in
                        NavigationLink {
                            ArchiveView(title: genre.displayName,
                                        filter: ArchiveFilter(postType: selectedType, genre: genre.id))
                        } label: {
                            genreCard(genre)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("genre")
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("دسته بندی", "Browse"))
        .navigationBarTitleDisplayMode(.inline)
        // Retried when the site comes back, in case the first load failed.
        .task(id: network.refreshToken) {
            if genres.isEmpty, let result = try? await appState.api.genres() {
                genres = result.filter { ($0.count ?? 1) > 0 }
            }
            if postTypes.isEmpty, let terms = try? await appState.api.searchTerms() {
                postTypes = terms.postType
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.bold())
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(selected ? Theme.accent : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(selected ? .white : Theme.secondaryText)
        }
        .buttonStyle(.plain)
    }

    private func shortcut<Destination: View>(_ title: String, icon: String,
                                             @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 30, height: 30)
                    .background(Theme.accent.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))
                Text(title).font(.footnote.bold())
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .buttonStyle(.plain)
    }

    private func genreCard(_ genre: Genre) -> some View {
        ZStack(alignment: .bottom) {
            if let url = genre.image?.url {
                RemoteImage(url: url)
            } else {
                Theme.surfaceRaised
            }
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text(genre.displayName).font(.subheadline.bold())
                Capsule().fill(Theme.accent).frame(width: 30, height: 3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}
