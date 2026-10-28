import SwiftUI

/// Downloaded and downloading videos; finished ones play offline.
struct DownloadsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var downloads = DownloadManager.shared
    @State private var playback: PlaybackItem?
    @State private var pendingDelete: DownloadItem?

    var body: some View {
        Group {
            if downloads.items.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(Theme.accentText)
                    Text("هنوز چیزی دانلود نکرده‌اید")
                        .font(.headline)
                    Text("در صفحه هر فیلم یا قسمت، دکمه دانلود را بزنید تا بدون اینترنت هم تماشا کنید.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(downloads.items) { item in
                            row(item)
                                .listRowBackground(Theme.surface)
                                .swipeActions {
                                    Button(role: .destructive) { pendingDelete = item } label: {
                                        Label("حذف", systemImage: "trash")
                                    }
                                }
                        }
                    } footer: {
                        Text("فضای استفاده‌شده: \(downloads.usedBytes.byteText)")
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("دانلودها")
        .fullScreenCover(item: $playback) { item in
            PlayerView(item: item).environmentObject(appState)
        }
        .confirmationDialog("این دانلود حذف شود؟",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                if let item = pendingDelete { downloads.delete(item.id) }
                pendingDelete = nil
            }
            Button("انصراف", role: .cancel) { pendingDelete = nil }
        }
    }

    private func row(_ item: DownloadItem) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: item.posterURL)
                .frame(width: 58, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    if item.state == .completed {
                        Image(systemName: "play.fill")
                            .font(.title3)
                            .padding(10)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let label = item.episodeLabel { Text(label) }
                    if let quality = item.quality { Text(quality) }
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

                switch item.state {
                case .completed:
                    Label(item.totalBytes > 0 ? item.totalBytes.byteText : "آماده تماشا", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .failed:
                    Label("دانلود ناموفق بود", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                case .downloading, .paused:
                    ProgressView(value: item.progress)
                        .tint(Theme.accentText)
                    Text(progressText(item))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            Spacer(minLength: 0)
            actionButton(item)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if item.state == .completed { play(item) }
        }
    }

    @ViewBuilder
    private func actionButton(_ item: DownloadItem) -> some View {
        switch item.state {
        case .downloading:
            circleButton("pause.fill") { downloads.pause(item.id) }
        case .paused:
            circleButton("arrow.down") { downloads.resume(item.id) }
        case .failed:
            circleButton("arrow.clockwise") { downloads.resume(item.id) }
        case .completed:
            EmptyView()
        }
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.bold())
                .frame(width: 38, height: 38)
                .background(Theme.surfaceRaised, in: Circle())
                .foregroundStyle(Theme.accentText)
        }
        .buttonStyle(.plain)
    }

    private func progressText(_ item: DownloadItem) -> String {
        let percent = Int(item.progress * 100)
        let sizes = item.totalBytes > 0
            ? "\(item.receivedBytes.byteText) از \(item.totalBytes.byteText)"
            : item.receivedBytes.byteText
        return item.state == .paused ? "متوقف · \(percent)٪ · \(sizes)" : "\(percent)٪ · \(sizes)"
    }

    private func play(_ item: DownloadItem) {
        guard let playbackItem = downloads.playbackItem(for: item) else {
            downloads.delete(item.id)
            return
        }
        playback = playbackItem
    }
}
