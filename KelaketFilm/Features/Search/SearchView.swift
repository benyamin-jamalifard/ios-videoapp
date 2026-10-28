import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var results: [Post] = []
    @State private var isSearching = false
    @State private var error: String?

    private let columns = [GridItem(.adaptive(minimum: 105), spacing: 12)]

    var body: some View {
        ScrollView {
            if isSearching {
                ProgressView().padding(.top, 40)
            } else if let error {
                Text(error).foregroundStyle(Theme.muted).padding(.top, 40)
            } else if results.isEmpty && !query.isEmpty {
                Text("نتیجه‌ای پیدا نشد").foregroundStyle(Theme.muted).padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(results) { post in
                        NavigationLink(value: FilmRoute(id: post.id)) {
                            PosterCard(post: post, width: 105)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("جستجو")
        .searchable(text: $query, prompt: "نام فیلم یا سریال")
        // Debounced: the task restarts on every keystroke and only fires after a pause.
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespaces)
            guard text.count >= 2 else {
                results = []
                return
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            error = nil
            defer { isSearching = false }
            do {
                results = try await appState.api.search(text)
            } catch {
                // A newer keystroke cancelled this request; its own task takes over.
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}
