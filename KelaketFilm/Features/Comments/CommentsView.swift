import SwiftUI

struct CommentRow: View {
    let comment: Comment
    var onReply: ((Comment) -> Void)?
    var onRate: ((Comment, String) -> Void)?

    @State private var revealSpoiler = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RemoteImage(url: URL(string: comment.avatar ?? ""))
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(comment.commentAuthor ?? "کاربر").font(.subheadline.bold())
                    if let date = comment.commentDate {
                        Text(date).font(.caption2).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
            }

            if comment.isSpoiler && !revealSpoiler {
                Button {
                    revealSpoiler = true
                } label: {
                    Label("این نظر حاوی اسپویل است؛ برای دیدن بزنید", systemImage: "eye.slash")
                        .font(.footnote)
                }
            } else {
                Text(comment.commentContent?.plainText ?? "")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if onReply != nil || onRate != nil {
                HStack(spacing: 16) {
                    if let onRate {
                        Button { onRate(comment, "like") } label: {
                            Label("\(comment.likeCount ?? 0)", systemImage: "hand.thumbsup")
                        }
                        Button { onRate(comment, "dislike") } label: {
                            Label("\(comment.dislikeCount ?? 0)", systemImage: "hand.thumbsdown")
                        }
                    }
                    if let onReply {
                        Button("پاسخ") { onReply(comment) }
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .buttonStyle(.plain)
            }

            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(comment.replies) { reply in
                        CommentRow(comment: reply, onRate: onRate)
                    }
                }
                .padding(.leading, 20)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Theme.surfaceRaised).frame(width: 2)
                }
            }
        }
    }
}

/// All comments of a post, paged, with replying and rating.
struct CommentsView: View {
    let postId: Int

    @EnvironmentObject private var appState: AppState
    @State private var comments: [Comment] = []
    @State private var page = 0
    @State private var totalPages = 1
    @State private var isLoading = false
    @State private var showComposer = false
    @State private var replyTo: Comment?
    @State private var showLogin = false
    @State private var notice: String?

    var body: some View {
        List {
            ForEach(comments) { comment in
                CommentRow(comment: comment,
                           onReply: { target in compose(replyingTo: target) },
                           onRate: { target, action in Task { await rate(target, action) } })
                    .listRowBackground(Theme.surface)
                    .onAppear {
                        if comment.id == comments.last?.id { Task { await loadNextPage() } }
                    }
            }
            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if comments.isEmpty {
                Text("هنوز نظری ثبت نشده است.")
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("نظرات")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { compose(replyingTo: nil) } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .task { if comments.isEmpty { await loadNextPage() } }
        .refreshable { await reload() }
        .sheet(isPresented: $showComposer) {
            CommentComposer(postId: postId, replyTo: replyTo) { message in
                notice = message
                Task { await reload() }
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $showLogin) { LoginView().environmentObject(appState) }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil },
                                                  set: { if !$0 { notice = nil } })) {
            Button("باشه", role: .cancel) {}
        }
    }

    private func compose(replyingTo comment: Comment?) {
        guard appState.isSignedIn else {
            showLogin = true
            return
        }
        replyTo = comment
        showComposer = true
    }

    private func reload() async {
        page = 0
        totalPages = 1
        comments = []
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard !isLoading, page < totalPages else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await appState.api.comments(postId: postId, page: page + 1)
            page += 1
            totalPages = result.totalPages ?? page
            comments += result.comments
        } catch {
            notice = error.localizedDescription
        }
    }

    private func rate(_ comment: Comment, _ action: String) async {
        guard appState.isSignedIn else {
            showLogin = true
            return
        }
        guard let id = comment.commentID else { return }
        do {
            let response = try await appState.api.rateComment(id: id, action: action)
            if response.error {
                notice = response.text
            } else {
                await reload()
            }
        } catch {
            notice = error.localizedDescription
        }
    }
}

struct CommentComposer: View {
    let postId: Int
    let replyTo: Comment?
    let onSent: (String) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSpoiler = false
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let replyTo {
                    Section("پاسخ به \(replyTo.commentAuthor ?? "کاربر")") {
                        Text(replyTo.commentContent?.plainText ?? "")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(3)
                    }
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                    Toggle("این نظر اسپویل دارد", isOn: $isSpoiler)
                }
                if let error {
                    Text(error).foregroundStyle(.orange).font(.footnote)
                }
            }
            .navigationTitle(replyTo == nil ? "نظر جدید" : "پاسخ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("انصراف") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("ارسال", action: send)
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func send() {
        guard let userId = appState.userId else {
            error = "برای ارسال نظر دوباره وارد حساب شوید."
            return
        }
        Task {
            isSending = true
            defer { isSending = false }
            do {
                let response = try await appState.api.sendComment(postId: postId,
                                                                  userId: userId,
                                                                  content: text,
                                                                  parentId: replyTo?.commentID.flatMap(Int.init),
                                                                  isSpoiler: isSpoiler)
                if response.error {
                    error = response.text ?? "ارسال نظر ناموفق بود."
                } else {
                    // "hold" means it waits for moderation; the message says so.
                    onSent(response.text ?? "نظر شما ثبت شد.")
                    dismiss()
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
