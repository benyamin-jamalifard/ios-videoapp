import AVKit
import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller: PlayerController

    init(item: PlaybackItem) {
        _controller = StateObject(wrappedValue: PlayerController(item: item))
    }

    var body: some View {
        PlayerControllerRepresentable(player: controller.player)
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                if let cue = controller.currentCue {
                    Text(cue.text)
                        .font(.system(size: 19, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                        .environment(\.layoutDirection, .rightToLeft)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 70)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(12)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .padding()
            }
            // Keep the scrubber left-to-right regardless of the app's RTL layout.
            .environment(\.layoutDirection, .leftToRight)
            .background(Color.black.ignoresSafeArea())
            .onAppear { controller.start(api: appState.isSignedIn ? appState.api : nil) }
            .onDisappear { controller.stop() }
    }
}

@MainActor
final class PlayerController: ObservableObject {
    let player: AVPlayer
    @Published private(set) var currentCue: SubtitleCue?
    private let item: PlaybackItem
    private var api: APIClient?
    private var timeObserver: Any?
    private var subtitleObserver: Any?
    private var cues: [SubtitleCue] = []
    private var lastSavedPosition: Double = -1

    init(item: PlaybackItem) {
        self.item = item
        player = AVPlayer(url: item.url)
    }

    /// - Parameter api: nil for guests, who have no progress to save.
    func start(api: APIClient?) {
        self.api = api
        if item.startAt > 5 {
            player.seek(to: CMTime(seconds: item.startAt, preferredTimescale: 600))
        }
        player.play()

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 15, preferredTimescale: 1),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.saveProgress(reason: "interval") }
        }

        if let subtitleURL = item.subtitleURL {
            Task { await loadSubtitles(from: subtitleURL) }
        }
    }

    func stop() {
        saveProgress(reason: "close")
        player.pause()
        for observer in [timeObserver, subtitleObserver].compactMap({ $0 }) {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        subtitleObserver = nil
    }

    private func loadSubtitles(from url: URL) async {
        cues = await Subtitles.load(from: url)
        guard !cues.isEmpty, subtitleObserver == nil else { return }
        subtitleObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let cue = Subtitles.cue(at: time.seconds, in: self.cues)
                if cue != self.currentCue { self.currentCue = cue }
            }
        }
    }

    private func saveProgress(reason: String) {
        guard let api else { return }
        let position = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        guard position.isFinite, duration.isFinite, position > 0, duration > 0 else { return }
        // The server throttles too, but skip calls when playback has not moved.
        guard reason != "interval" || abs(position - lastSavedPosition) >= 10 else { return }
        lastSavedPosition = position

        let progress = WatchProgressSave(postId: item.postId,
                                         contentType: item.contentType,
                                         seasonNo: item.seasonNo,
                                         episodeNo: item.episodeNo,
                                         movieRowNo: item.movieRowNo,
                                         positionSeconds: Int(position),
                                         durationSeconds: Int(duration),
                                         reason: reason)
        Task { try? await api.saveWatchProgress(progress) }
    }
}

private struct PlayerControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}
