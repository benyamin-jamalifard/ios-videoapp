import SwiftUI

/// Filterable archive of all posts (`mobile/v2/archive`).
struct ArchiveView: View {
    let title: String
    /// Filters fixed by the caller (e.g. a genre or collection); the user can add more.
    let baseFilter: ArchiveFilter

    @State private var filter: ArchiveFilter
    @State private var showFilters = false
    @StateObject private var pager: Pager<Post>

    init(title: String, filter: ArchiveFilter = ArchiveFilter()) {
        self.title = title
        baseFilter = filter
        _filter = State(initialValue: filter)
        _pager = StateObject(wrappedValue: Pager<Post> { _ in ([], false) })
    }

    var body: some View {
        ScrollView {
            if pager.isLoaded && pager.items.isEmpty {
                Text(pager.error ?? L("موردی با این فیلترها پیدا نشد.", "Nothing matches these filters."))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 60)
            } else {
                PosterGrid(posts: pager.items) { Task { await pager.loadMore() } }
            }
            if pager.isLoading {
                ProgressView().padding()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showFilters = true } label: {
                    Image(systemName: filter == baseFilter
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            ArchiveFilterSheet(filter: $filter, locked: baseFilter)
        }
        // A new pager per filter set; the fetch closure captures the filter.
        .task(id: filter) {
            let current = filter
            pager.replaceFetch { page in
                let result = try await APIClient.shared.archive(current, page: page)
                let maxPages = result.paginationValues?.maxPages ?? page
                return (result.data, page < maxPages)
            }
            await pager.reload()
        }
        .refreshable { await pager.reload() }
    }
}

private struct ArchiveFilterSheet: View {
    @Binding var filter: ArchiveFilter
    /// Filters the screen was opened with; shown but not editable.
    let locked: ArchiveFilter

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ArchiveFilter()
    @State private var terms: SearchTerms?

    var body: some View {
        NavigationStack {
            Form {
                if let terms {
                    termPicker(L("نوع", "Type"), selection: $draft.postType, terms: terms.postType, disabled: locked.postType != nil)
                    termPicker(L("ژانر", "Genre"), selection: $draft.genre, terms: terms.genres, disabled: locked.genre != nil)
                    termPicker(L("سال", "Year"), selection: $draft.year, terms: terms.year, disabled: locked.year != nil)
                    termPicker(L("کشور", "Country"), selection: $draft.country, terms: terms.country, disabled: locked.country != nil)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
                Picker(L("مرتب‌سازی", "Sort by"), selection: $draft.sort) {
                    ForEach(ArchiveFilter.sortOptions, id: \.label) { option in
                        Text(option.label).tag(option.value)
                    }
                }
            }
            .navigationTitle(L("فیلترها", "Filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("حذف فیلترها", "Reset")) { draft = locked }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("اعمال", "Apply")) {
                        filter = draft
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { draft = filter }
        .task { terms = try? await APIClient.shared.searchTerms() }
    }

    private func termPicker(_ title: String, selection: Binding<Int?>, terms: [FilterTerm], disabled: Bool) -> some View {
        Picker(title, selection: selection) {
            Text(L("همه", "All")).tag(Int?.none)
            ForEach(terms) { term in
                Text(term.displayName).tag(term.termId)
            }
        }
        .disabled(disabled)
    }
}
