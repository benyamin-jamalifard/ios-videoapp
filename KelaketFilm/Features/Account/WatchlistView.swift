import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject private var appState: AppState
    @State private var posts: [Post]?
    @State private var error: String?

    private let columns = [GridItem(.adaptive(minimum: 105), spacing: 12)]

    var body: some View {
        Group {
            if let posts {
                if posts.isEmpty {
                    Text("لیست تماشای شما خالی است.")
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(posts) { post in
                                NavigationLink(value: FilmRoute(id: post.id)) {
                                    PosterCard(post: post, width: 105)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .refreshable { await load() }
                }
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("لیست تماشا")
        // Also runs when coming back from a film page, where the item may have been removed.
        .task { await load() }
    }

    private func load() async {
        do {
            posts = try await appState.api.watchlist()
            error = nil
        } catch is CancellationError {
            // Superseded or the screen closed: not an error to show.
        } catch {
            if posts == nil { self.error = error.localizedDescription }
        }
    }
}
