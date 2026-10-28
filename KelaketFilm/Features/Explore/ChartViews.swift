import SwiftUI

struct BoxOfficeView: View {
    @State private var boxOffice: BoxOffice?
    @State private var error: String?

    var body: some View {
        List {
            if let boxOffice {
                if let updated = boxOffice.lastUpdateHuman {
                    Text("آخرین به‌روزرسانی: \(updated)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .listRowBackground(Color.clear)
                }
                if boxOffice.data.isEmpty {
                    Text(boxOffice.message ?? "اطلاعاتی موجود نیست.")
                        .foregroundStyle(Theme.muted)
                        .listRowBackground(Color.clear)
                }
                ForEach(Array(boxOffice.data.enumerated()), id: \.offset) { _, item in
                    if let postId = item.postId, postId > 0 {
                        NavigationLink(value: FilmRoute(id: postId)) { row(item) }
                            .listRowBackground(Theme.surface)
                    } else {
                        row(item).listRowBackground(Theme.surface)
                    }
                }
            } else if let error {
                Text(error).foregroundStyle(.orange).listRowBackground(Color.clear)
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("باکس‌آفیس")
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ item: BoxOfficeItem) -> some View {
        HStack(spacing: 12) {
            Text("\(item.rank ?? 0)")
                .font(.title3.bold())
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
            RemoteImage(url: URL(string: item.poster ?? ""))
                .frame(width: 50, height: 75)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? "").font(.subheadline.bold())
                Group {
                    if let weekend = item.weekend { Text("فروش آخر هفته: \(weekend)") }
                    if let gross = item.gross { Text("فروش کل: \(gross)") }
                    if let weeks = item.weeks { Text("هفته‌های اکران: \(weeks)") }
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
            }
        }
    }

    private func load() async {
        do {
            boxOffice = try await APIClient.shared.boxOffice()
            error = nil
        } catch {
            if boxOffice == nil { self.error = error.localizedDescription }
        }
    }
}

struct WeeklyScheduleView: View {
    /// Keys of the theme's `series_tabbed` option, Saturday first.
    /// Not defined in the plugin; adjust if the theme uses different keys.
    static let days: [(key: String, label: String)] = [
        ("saturday", "شنبه"), ("sunday", "یکشنبه"), ("monday", "دوشنبه"),
        ("tuesday", "سه‌شنبه"), ("wednesday", "چهارشنبه"), ("thursday", "پنجشنبه"),
        ("friday", "جمعه"),
    ]

    @State private var day = WeeklyScheduleView.today
    @State private var series: [WeeklySeries]?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.days, id: \.key) { item in
                        Button(item.label) { day = item.key }
                            .buttonStyle(.bordered)
                            .tint(day == item.key ? Theme.accent : .gray)
                    }
                }
                .padding()
            }

            List {
                if let series {
                    if series.isEmpty {
                        Text("در این روز سریالی پخش نمی‌شود.")
                            .foregroundStyle(Theme.muted)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(series) { item in
                        NavigationLink(value: FilmRoute(id: item.id)) {
                            HStack(spacing: 12) {
                                RemoteImage(url: URL(string: item.poster ?? ""))
                                    .frame(width: 50, height: 75)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name ?? "").font(.subheadline.bold())
                                    if let update = item.update {
                                        Text(update.plainText).font(.caption).foregroundStyle(Theme.muted)
                                    }
                                }
                            }
                        }
                        .listRowBackground(Theme.surface)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("برنامه پخش")
        .task(id: day) {
            series = nil
            series = (try? await APIClient.shared.weeklySeries(day: day)) ?? []
        }
    }

    private static var today: String {
        // Calendar weekday: 1 = Sunday … 7 = Saturday.
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: Date())
        let keys = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        return keys[weekday - 1]
    }
}

struct Top250View: View {
    @State private var list = "movies"
    @StateObject private var pager = Pager<RankedTitle> { _ in ([], false) }

    var body: some View {
        List {
            Picker("نوع", selection: $list) {
                Text("فیلم").tag("movies")
                Text("سریال").tag("series")
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            ForEach(Array(pager.items.enumerated()), id: \.offset) { index, item in
                Group {
                    if let postId = item.postId {
                        NavigationLink(value: FilmRoute(id: postId)) { row(item, onSite: true) }
                    } else {
                        row(item, onSite: false)
                    }
                }
                .listRowBackground(Theme.surface)
                .onAppear {
                    if index == pager.items.count - 1 { Task { await pager.loadMore() } }
                }
            }
            if pager.isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if pager.isLoaded && pager.items.isEmpty {
                Text(pager.error ?? "اطلاعاتی موجود نیست.")
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("۲۵۰ برتر IMDb")
        .task(id: list) {
            let current = list
            pager.replaceFetch { page in
                let result = try await APIClient.shared.top250(list: current, page: page)
                return (result.data, page < (result.pages ?? page))
            }
            await pager.reload()
        }
    }

    private func row(_ item: RankedTitle, onSite: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(item.rank ?? 0)")
                .font(.headline)
                .foregroundStyle(Theme.accent)
                .frame(width: 36)
            RemoteImage(url: URL(string: item.poster ?? ""))
                .frame(width: 46, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name ?? "").font(.subheadline.bold())
                HStack(spacing: 8) {
                    if let rating = item.imdbRating {
                        Label(rating, systemImage: "star.fill").foregroundStyle(.yellow)
                    }
                    if !onSite {
                        Text("در سایت موجود نیست").foregroundStyle(Theme.muted)
                    }
                }
                .font(.caption)
            }
        }
        .opacity(onSite ? 1 : 0.6)
    }
}

struct CollectionsView: View {
    @StateObject private var pager = Pager<CollectionItem> { page in
        let result = try await APIClient.shared.collections(page: page)
        return (result.data, page < (result.pages ?? page))
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(pager.items.enumerated()), id: \.offset) { index, item in
                    NavigationLink {
                        ArchiveView(title: item.name ?? "", filter: ArchiveFilter(category: item.id))
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            RemoteImage(url: URL(string: item.poster ?? ""))
                            LinearGradient(colors: [.clear, .black.opacity(0.85)],
                                           startPoint: .center, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "").font(.subheadline.bold()).lineLimit(2)
                                if let count = item.count {
                                    Text("\(count) عنوان").font(.caption2).foregroundStyle(Theme.muted)
                                }
                            }
                            .padding(10)
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if index == pager.items.count - 1 { Task { await pager.loadMore() } }
                    }
                }
            }
            .padding()
            if pager.isLoading { ProgressView() }
            if pager.isLoaded && pager.items.isEmpty {
                Text(pager.error ?? "کالکشنی موجود نیست.").foregroundStyle(Theme.muted)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("کالکشن‌ها")
        .task { if !pager.isLoaded { await pager.reload() } }
    }
}
