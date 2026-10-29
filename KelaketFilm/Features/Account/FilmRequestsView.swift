import SwiftUI

struct FilmRequestsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var requests: [FilmRequest]?
    @State private var name = ""
    @State private var category = 1
    @State private var isSending = false
    @State private var notice: String?

    private var needsSubscription: Bool {
        appState.config.appReqsNeedVip && !(appState.subscription?.hasActiveSub ?? false)
    }

    var body: some View {
        List {
            Section("درخواست جدید") {
                TextField("نام فیلم یا سریال", text: $name)
                Picker("نوع", selection: $category) {
                    Text("فیلم").tag(1)
                    Text("سریال").tag(2)
                }
                .pickerStyle(.segmented)
                Button(action: send) {
                    if isSending { ProgressView() } else { Text("ثبت درخواست") }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
            }
            .listRowBackground(Theme.surface)

            Section("درخواست‌های من") {
                if let requests {
                    if requests.isEmpty {
                        Text("درخواستی ثبت نکرده‌اید.").foregroundStyle(Theme.muted)
                    }
                    ForEach(Array(requests.enumerated()), id: \.offset) { _, request in
                        row(request)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("درخواست فیلم")
        .task { await load() }
        .refreshable { await load() }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil },
                                                  set: { if !$0 { notice = nil } })) {
            Button("باشه", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func row(_ request: FilmRequest) -> some View {
        let content = VStack(alignment: .leading, spacing: 4) {
            Text(request.name ?? "").font(.subheadline.bold())
            HStack {
                Text(request.type == 2 ? "سریال" : "فیلم")
                if let date = request.createdAt { Text(date) }
                Spacer()
                if request.postId ?? 0 > 0 {
                    Text("اضافه شد").foregroundStyle(.green)
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
        // Once the admin links the request to a post, it opens that post.
        if let postId = request.postId, postId > 0 {
            NavigationLink(value: FilmRoute(id: postId)) { content }
        } else {
            content
        }
    }

    private func load() async {
        requests = (try? await appState.api.filmRequests()) ?? requests ?? []
    }

    private func send() {
        guard !needsSubscription else {
            notice = "ثبت درخواست فقط برای کاربران دارای اشتراک فعال است."
            return
        }
        Task {
            isSending = true
            defer { isSending = false }
            do {
                let response = try await appState.api.sendFilmRequest(name: name, category: category)
                notice = response.text
                if response.success {
                    name = ""
                    await load()
                }
            } catch is CancellationError {
                // Superseded or the screen closed: not an error to show.
            } catch {
                // Limits (e.g. 24-hour quota) arrive as HTTP errors with a Persian message.
                notice = error.localizedDescription
            }
        }
    }
}
