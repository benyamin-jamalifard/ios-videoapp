import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var filter = SearchFilter()
    @State private var showFilters = false
    @State private var results: [Post] = []
    /// What `results` were loaded for; differs from the input while a search runs.
    @State private var resultsKey: SearchKey?
    @State private var isLoading = false
    @State private var error: String?
    @State private var page = 1
    @State private var pageSize = 0
    @State private var hasMore = false
    @AppStorage("kf.recentSearches") private var recentStorage = ""

    private struct SearchKey: Equatable {
        let text: String
        let filter: SearchFilter
    }

    private var key: SearchKey {
        SearchKey(text: query.trimmingCharacters(in: .whitespaces), filter: filter)
    }

    /// A search needs two letters, or at least one filter.
    private var canSearch: Bool { key.text.count >= 2 || !filter.isEmpty }

    private var recent: [String] {
        recentStorage.split(separator: "\n").map(String.init)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                filterBar
                    .padding(.horizontal)
                    .padding(.top, 6)

                if !canSearch {
                    idleState
                } else if let error, results.isEmpty {
                    message(error, icon: "wifi.exclamationmark")
                } else if results.isEmpty && resultsKey == key && !isLoading {
                    message(L("نتیجه‌ای پیدا نشد", "No results"), icon: "magnifyingglass")
                } else {
                    PosterGrid(posts: results) { Task { await loadMore() } }
                        // Old results fade while new ones load, instead of the grid disappearing.
                        .opacity(isLoading && resultsKey != key ? 0.45 : 1)
                    if isLoading && !results.isEmpty && resultsKey == key {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if isLoading && (results.isEmpty || resultsKey != key) {
                ProgressView()
                    .padding(10)
                    .background(Theme.surfaceRaised, in: Circle())
                    .padding(.top, 60)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("جستجو", "Search"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: L("نام فیلم، سریال یا انیمه", "Movie or series title"))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onSubmit(of: .search) {
            let text = key.text
            AppAnalytics.searched(text)
            remember(text)
        }
        .sheet(isPresented: $showFilters) {
            SearchFilterSheet(filter: $filter).environmentObject(appState)
        }
        // Debounced: the task restarts on every keystroke and only fires after a pause.
        .task(id: key) {
            guard canSearch else {
                results = []
                resultsKey = nil
                error = nil
                return
            }
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await search(key)
        }
    }

    // MARK: Pieces

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { showFilters = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                        Text(L("فیلترها", "Filters"))
                        if filter.count > 0 {
                            Text("\(filter.count)")
                                .font(.caption2.bold())
                                .frame(minWidth: 18, minHeight: 18)
                                .background(.white, in: Circle())
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .font(.footnote.bold())
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(filter.isEmpty ? Theme.surfaceRaised : Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                toggleChip(L("دوبله فارسی", "Persian dub"), icon: "mic.fill", isOn: $filter.dubbed)
                toggleChip(L("زیرنویس", "Subtitled"), icon: "captions.bubble.fill", isOn: $filter.subtitled)
                if !appState.isInternational {
                    toggleChip("پخش آنلاین", icon: "play.circle.fill", isOn: $filter.streamable)
                }
                if !filter.isEmpty {
                    Button { filter = SearchFilter() } label: {
                        Label(L("پاک کردن", "Clear"), systemImage: "xmark")
                            .font(.footnote.bold())
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func toggleChip(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Label(title, systemImage: icon)
                .font(.footnote.bold())
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(isOn.wrappedValue ? Theme.accent : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(isOn.wrappedValue ? .clear : Theme.surfaceRaised))
                .foregroundStyle(isOn.wrappedValue ? .white : Theme.secondaryText)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var idleState: some View {
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    SectionTitle(text: L("جستجوهای اخیر", "Recent searches"))
                    Spacer()
                    Button(L("پاک کردن", "Clear")) { recentStorage = "" }
                        .font(.footnote.bold())
                }
                .padding(.bottom, 6)
                ForEach(recent, id: \.self) { item in
                    Button { query = item } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(Theme.secondaryText)
                            Text(item)
                            Spacer()
                            Image(systemName: "arrow.up.backward")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Theme.surfaceRaised)
                }
            }
            .padding()
        } else {
            message(L("نام فیلم یا سریال را بنویسید، یا با فیلترها جستجو کنید.",
                      "Type a title, or search with filters."),
                    icon: "sparkle.magnifyingglass")
        }
    }

    private func message(_ text: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.accentText)
            Text(text)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 70)
    }

    // MARK: Loading

    private func search(_ key: SearchKey) async {
        isLoading = true
        defer { if self.key == key { isLoading = false } }
        do {
            let posts = try await appState.api.search(key.text, filter: key.filter, page: 1)
            // A newer keystroke or filter took over while this one ran.
            guard !Task.isCancelled, self.key == key else { return }
            results = posts
            resultsKey = key
            page = 1
            pageSize = posts.count
            hasMore = !posts.isEmpty
            error = nil
        } catch {
            guard !Task.isCancelled, self.key == key else { return }
            results = []
            resultsKey = key
            self.error = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoading, resultsKey == key else { return }
        let key = self.key
        isLoading = true
        defer { isLoading = false }
        guard let posts = try? await appState.api.search(key.text, filter: key.filter, page: page + 1),
              self.key == key
        else { return }
        page += 1
        results += posts.filter { post in !results.contains { $0.id == post.id } }
        // A short page is the last one.
        hasMore = !posts.isEmpty && posts.count >= pageSize
    }

    private func remember(_ text: String) {
        guard text.count >= 2 else { return }
        let updated = [text] + recent.filter { $0 != text }
        recentStorage = updated.prefix(8).joined(separator: "\n")
    }
}

/// Advanced search filters: type, genre, year range, country and versions.
private struct SearchFilterSheet: View {
    @Binding var filter: SearchFilter

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SearchFilter()
    @State private var terms: SearchTerms?

    private var years: [Int] {
        (terms?.year ?? []).compactMap { Int(($0.termSlug ?? $0.termName ?? "").latinDigits) }
            .sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let terms {
                    Section {
                        slugPicker(L("نوع", "Type"), selection: $draft.postType, terms: terms.postType)
                        slugPicker(L("ژانر", "Genre"), selection: $draft.genre, terms: terms.genres)
                        slugPicker(L("کشور", "Country"), selection: $draft.country, terms: terms.country)
                    }
                    if !years.isEmpty {
                        Section(L("سال انتشار", "Release year")) {
                            yearPicker(L("از", "From"), selection: $draft.fromYear)
                            yearPicker(L("تا", "To"), selection: $draft.toYear)
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
                Section {
                    Toggle(L("دوبله فارسی", "Persian dub"), isOn: $draft.dubbed)
                    Toggle(L("زیرنویس فارسی", "Persian subtitles"), isOn: $draft.subtitled)
                    if !appState.isInternational {
                        Toggle("قابل پخش آنلاین", isOn: $draft.streamable)
                    }
                }
                .tint(Theme.accent)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L("فیلترهای جستجو", "Search filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("حذف همه", "Reset")) { draft = SearchFilter() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("اعمال", "Apply")) {
                        // The plugin needs both ends of the range: fill the missing one.
                        if draft.fromYear != nil, draft.toYear == nil { draft.toYear = years.first }
                        if draft.toYear != nil, draft.fromYear == nil { draft.fromYear = years.last }
                        filter = draft
                        dismiss()
                    }
                    .bold()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { draft = filter }
        .task { terms = try? await appState.api.searchTerms() }
    }

    private func slugPicker(_ title: String, selection: Binding<String?>, terms: [FilterTerm]) -> some View {
        Picker(title, selection: selection) {
            Text(L("همه", "All")).tag(String?.none)
            ForEach(terms.filter { $0.termSlug != nil }) { term in
                Text(term.termName ?? term.termSlug ?? "").tag(term.termSlug)
            }
        }
    }

    private func yearPicker(_ title: String, selection: Binding<Int?>) -> some View {
        Picker(title, selection: selection) {
            Text(L("همه", "Any")).tag(Int?.none)
            ForEach(years, id: \.self) { year in
                Text(String(year)).tag(Int?.some(year))
            }
        }
    }
}
