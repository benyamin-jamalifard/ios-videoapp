import SwiftUI

struct ActiveSessionsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [ActiveSession]?
    @State private var error: String?
    @State private var confirmLogoutAll = false

    var body: some View {
        List {
            if let sessions {
                if sessions.isEmpty {
                    Text("نشست فعالی پیدا نشد.").foregroundStyle(Theme.muted).listRowBackground(Color.clear)
                }
                Section {
                    ForEach(sessions) { session in
                        row(session)
                            .listRowBackground(Theme.surface)
                            .swipeActions {
                                Button("خروج", role: .destructive) {
                                    Task { await logout(session) }
                                }
                            }
                    }
                } footer: {
                    if !sessions.isEmpty {
                        Text("برای خارج کردن یک دستگاه، روی آن به چپ بکشید.")
                    }
                }

                if sessions.count > 1 {
                    Section {
                        Button("خروج از همه دستگاه‌ها", role: .destructive) { confirmLogoutAll = true }
                            .listRowBackground(Theme.surface)
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
        .navigationTitle("دستگاه‌های فعال")
        .confirmationDialog("از همه دستگاه‌ها، از جمله همین گوشی، خارج می‌شوید.",
                            isPresented: $confirmLogoutAll, titleVisibility: .visible) {
            Button("خروج از همه", role: .destructive) { Task { await logoutAll() } }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ session: ActiveSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: session.app != nil || session.sourceLabel == "app" ? "iphone" : "desktopcomputer")
                .font(.title3)
                .foregroundStyle(Theme.accentText)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.title).font(.subheadline.bold())
                    if let version = session.appVersion { Text(version).font(.caption).foregroundStyle(Theme.muted) }
                }
                HStack {
                    if let ip = session.ip { Text(ip) }
                    if let seen = session.lastSeenHuman { Text(seen) }
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
            }
            Spacer()
            if session.isCurrent {
                Text("همین دستگاه")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.2), in: Capsule())
                    .foregroundStyle(Theme.accentText)
            }
        }
    }

    private func load() async {
        do {
            sessions = try await appState.api.activeSessions()
            error = nil
        } catch is CancellationError {
            // Superseded or the screen closed: not an error to show.
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func logout(_ session: ActiveSession) async {
        guard let sid = session.sid else { return }
        do {
            let response = try await appState.api.logoutSession(sid: sid, all: false)
            guard response.success else {
                error = response.text ?? "خروج انجام نشد."
                return
            }
            if session.isCurrent {
                appState.signOut()
                dismiss()
            } else {
                sessions?.removeAll { $0.sid == sid }
            }
        } catch is CancellationError {
            // Superseded or the screen closed: not an error to show.
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func logoutAll() async {
        do {
            let response = try await appState.api.logoutSession(sid: nil, all: true)
            guard response.success else {
                error = response.text ?? "خروج انجام نشد."
                return
            }
            // The server ended this session too.
            appState.signOut()
            dismiss()
        } catch is CancellationError {
            // Superseded or the screen closed: not an error to show.
        } catch {
            self.error = error.localizedDescription
        }
    }
}
