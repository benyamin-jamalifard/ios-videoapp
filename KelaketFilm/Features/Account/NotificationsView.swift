import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var items: [AppNotification]?
    @State private var error: String?

    var body: some View {
        List {
            if let items {
                if items.isEmpty {
                    Text("اعلانی ندارید.")
                        .foregroundStyle(Theme.muted)
                        .listRowBackground(Color.clear)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Button { open(item, at: index) } label: { row(item) }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.surface)
                }
            } else if let error {
                Text(error).foregroundStyle(.orange).listRowBackground(Color.clear)
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("اعلان‌ها")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if appState.isSignedIn {
                    Button("خواندن همه") { Task { await markAllRead() } }
                        .font(.footnote)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ item: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(item.isRead ? Color.clear : Theme.accent)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                if let title = item.title {
                    Text(title).font(.subheadline.bold())
                }
                if let message = item.message {
                    Text(message).font(.footnote).foregroundStyle(.white.opacity(0.85))
                }
                if let date = item.createdAt {
                    Text(date).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func load() async {
        do {
            items = try await appState.api.notifications()
            error = nil
        } catch is CancellationError {
            // Superseded or the screen closed: not an error to show.
        } catch {
            if items == nil { self.error = error.localizedDescription }
        }
    }

    private func open(_ item: AppNotification, at index: Int) {
        if appState.isSignedIn, !item.isRead, let id = item.id {
            items?[index].isRead = true
            Task { try? await appState.api.markNotificationsRead(id: id) }
        }
        if let url = item.linkURL {
            AppRouter.shared.open(url)
        }
    }

    private func markAllRead() async {
        try? await appState.api.markNotificationsRead(id: nil)
        await load()
    }
}
