import SwiftUI

/// Entry point for browsing: archive, charts, schedule, lists, actors and genres.
struct ExploreView: View {
    @EnvironmentObject private var appState: AppState
    @State private var genres: [Genre] = []

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(columns: columns, spacing: 12) {
                    tile("همه فیلم‌ها و سریال‌ها", icon: "square.grid.2x2") {
                        ArchiveView(title: "آرشیو")
                    }
                    tile("۲۵۰ برتر IMDb", icon: "trophy") { Top250View() }
                    tile("کالکشن‌ها", icon: "square.stack.3d.up") { CollectionsView() }
                    tile("لیست‌های کاربران", icon: "list.star") { PublicListsView() }
                    if appState.config.showWeekly {
                        tile("برنامه پخش هفتگی", icon: "calendar") { WeeklyScheduleView() }
                    }
                    if appState.config.kelaketappShowBoxoffice {
                        tile("باکس‌آفیس", icon: "chart.bar") { BoxOfficeView() }
                    }
                    if appState.config.kelaketappShowActorsArchive {
                        tile("بازیگران", icon: "person.2") { ActorsArchiveView() }
                    }
                }
                .padding(.horizontal)

                if !genres.isEmpty {
                    Text("ژانرها").font(.headline).padding(.horizontal)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(genres) { genre in
                            NavigationLink {
                                ArchiveView(title: genre.title ?? "", filter: ArchiveFilter(genre: genre.id))
                            } label: {
                                genreCard(genre)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("کاوش")
        .task {
            if genres.isEmpty, let result = try? await appState.api.genres() {
                genres = result.filter { ($0.count ?? 1) > 0 }
            }
        }
    }

    private func tile<Destination: View>(_ title: String, icon: String,
                                         @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .buttonStyle(.plain)
    }

    private func genreCard(_ genre: Genre) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let url = genre.image?.url {
                RemoteImage(url: url)
            } else {
                Theme.surfaceRaised
            }
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(genre.title ?? "").font(.subheadline.bold())
                if let count = genre.count {
                    Text("\(count) عنوان").font(.caption2).foregroundStyle(Theme.muted)
                }
            }
            .padding(10)
        }
        .frame(height: 80)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}
