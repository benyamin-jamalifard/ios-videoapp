import AVKit
import SwiftUI

/// Full-screen player with its own controls: double-tap to seek, brightness
/// swipe, pinch to fill, speed, quality, subtitles, lock, PiP, AirPlay, Cast
/// and the next episode. Links never appear anywhere on screen.
struct PlayerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller: PlayerController
    @State private var seekFeedback: Double?
    @State private var scrubPreview: Double?
    @State private var brightnessStart: CGFloat?
    @State private var brightnessLevel: CGFloat?

    init(item: PlaybackItem) {
        _controller = StateObject(wrappedValue: PlayerController(item: item))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoSurface(controller: controller, fill: controller.fill)
                .ignoresSafeArea()
            gestureLayer
            subtitle

            if controller.isBuffering && controller.failure == nil {
                ProgressView().controlSize(.large).tint(.white).allowsHitTesting(false)
            }
            if let seekFeedback {
                seekBubble(seekFeedback)
            }
            if let brightnessLevel {
                levelIndicator(icon: "sun.max.fill", level: brightnessLevel)
            }

            if controller.controlsVisible {
                Group {
                    if controller.locked { lockedOverlay } else { controls }
                }
                .transition(.opacity)
            }
            if let countdown = controller.nextCountdown {
                upNextCard(countdown)
            }
            if let failure = controller.failure {
                failureView(failure)
            }
        }
        // Keep the scrubber and the skip buttons left-to-right in the RTL app.
        .environment(\.layoutDirection, .leftToRight)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .animation(.easeInOut(duration: 0.2), value: controller.controlsVisible)
        .onAppear {
            controller.start(api: appState.isSignedIn ? appState.api : nil)
            Orientation.request(.landscapeRight)
        }
        .onDisappear {
            controller.stop()
            Orientation.request(.portrait)
        }
        // Auto-hide the controls a few seconds after the last touch.
        .task(id: controller.interaction) {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            controller.hideControlsIfIdle()
        }
    }

    // MARK: Gestures

    private var gestureLayer: some View {
        HStack(spacing: 0) {
            tapZone(seconds: -10)
                .gesture(brightnessDrag)
            tapZone(seconds: 10)
        }
        .ignoresSafeArea()
        .simultaneousGesture(MagnificationGesture().onEnded { scale in
            guard !controller.locked else { return }
            controller.setFill(scale > 1)
        })
    }

    private func tapZone(seconds: Double) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard !controller.locked else { return }
                controller.skip(by: seconds)
                showSeekFeedback(seconds)
            }
            .onTapGesture { controller.toggleControls() }
    }

    private var brightnessDrag: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard !controller.locked,
                      abs(value.translation.height) > abs(value.translation.width),
                      let screen = Orientation.screen
                else { return }
                if brightnessStart == nil { brightnessStart = screen.brightness }
                let level = min(1, max(0, (brightnessStart ?? 0.5) - value.translation.height / 300))
                screen.brightness = level
                brightnessLevel = level
            }
            .onEnded { _ in
                brightnessStart = nil
                Task {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    brightnessLevel = nil
                }
            }
    }

    private func showSeekFeedback(_ seconds: Double) {
        seekFeedback = (seekFeedback ?? 0).sign == seconds.sign ? (seekFeedback ?? 0) + seconds : seconds
        let shown = seekFeedback
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            if seekFeedback == shown { seekFeedback = nil }
        }
    }

    // MARK: Overlays

    @ViewBuilder
    private var subtitle: some View {
        if let cue = controller.currentCue {
            VStack {
                Spacer()
                Text(cue.text)
                    .font(.system(size: controller.subtitleSize.points, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    .environment(\.layoutDirection, .rightToLeft)
                    .padding(.horizontal, 40)
                    .padding(.bottom, controller.controlsVisible && !controller.locked ? 120 : 26)
                    .animation(.easeInOut(duration: 0.2), value: controller.controlsVisible)
            }
            .allowsHitTesting(false)
        }
    }

    private func seekBubble(_ seconds: Double) -> some View {
        HStack {
            if seconds > 0 { Spacer() }
            Label("\(Int(abs(seconds))) ثانیه", systemImage: seconds > 0 ? "goforward" : "gobackward")
                .font(.headline)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(.horizontal, 60)
            if seconds < 0 { Spacer() }
        }
        .allowsHitTesting(false)
    }

    private func levelIndicator(icon: String, level: CGFloat) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
            ProgressView(value: level).tint(.white).frame(width: 110)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.black.opacity(0.6), in: Capsule())
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 40)
        .allowsHitTesting(false)
    }

    private var controls: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 180)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                centerButtons
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .foregroundStyle(.white)
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.bold())
                    .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.item.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let label = controller.item.episodeLabel { Text(label) }
                    if controller.item.isOffline { Label("آفلاین", systemImage: "arrow.down.circle.fill") }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
            }
            .environment(\.layoutDirection, .rightToLeft)
            Spacer()
            AirPlayButton().frame(width: 30, height: 30)
            if !controller.item.isOffline { CastButton() }
            settingsMenu
        }
    }

    private var centerButtons: some View {
        HStack(spacing: 56) {
            Button { controller.skip(by: -10); controller.poke() } label: {
                Image(systemName: "gobackward.10").font(.system(size: 30, weight: .medium))
            }
            Button { controller.togglePlay() } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 38, weight: .bold))
                    .frame(width: 78, height: 78)
                    .background(.white.opacity(0.16), in: Circle())
            }
            Button { controller.skip(by: 10); controller.poke() } label: {
                Image(systemName: "goforward.10").font(.system(size: 30, weight: .medium))
            }
        }
        .opacity(controller.isBuffering ? 0.5 : 1)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Text(timeText(scrubPreview ?? controller.currentTime))
                Scrubber(current: controller.currentTime,
                         duration: controller.duration,
                         buffered: controller.buffered,
                         onScrub: { value in
                             scrubPreview = value
                             controller.poke()
                         },
                         onSeek: { controller.seek(to: $0) })
                Text("-" + timeText(max(0, controller.duration - (scrubPreview ?? controller.currentTime))))
            }
            .font(.caption.monospacedDigit())

            HStack(spacing: 26) {
                barButton("lock.open.fill") { controller.locked = true }
                barButton(controller.fill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                    controller.setFill(!controller.fill)
                }
                barButton("rotate.right") { Orientation.toggle() }
                if controller.pipPossible {
                    barButton("pip.enter") { controller.togglePiP() }
                }
                if controller.hasSubtitles {
                    barButton(controller.subtitlesOn ? "captions.bubble.fill" : "captions.bubble") {
                        controller.subtitlesOn.toggle()
                        controller.poke()
                    }
                }
                Spacer()
                if controller.rate != 1 {
                    Text(rateLabel(controller.rate)).font(.caption.bold())
                }
                if !controller.item.upNext.isEmpty {
                    Button { controller.playNext() } label: {
                        Label("قسمت بعد", systemImage: "forward.end.fill")
                            .font(.footnote.bold())
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                }
            }
        }
    }

    private func barButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            controller.poke()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 34, height: 34)
        }
    }

    private var settingsMenu: some View {
        Menu {
            Menu {
                ForEach(PlayerController.rates, id: \.self) { rate in
                    Button { controller.setRate(rate) } label: {
                        checkLabel(rateLabel(rate), checked: controller.rate == rate)
                    }
                }
            } label: {
                Label("سرعت پخش · \(rateLabel(controller.rate))", systemImage: "speedometer")
            }

            if controller.item.sources.count > 1 {
                Menu {
                    ForEach(controller.item.sources, id: \.self) { source in
                        Button { controller.switchSource(source) } label: {
                            checkLabel(source.label, checked: source.url == controller.item.url)
                        }
                    }
                } label: {
                    Label("کیفیت · \(controller.currentQuality ?? "")", systemImage: "sparkles.tv")
                }
            }

            if controller.hasSubtitles {
                Menu {
                    Button { controller.subtitlesOn.toggle() } label: {
                        checkLabel("نمایش زیرنویس", checked: controller.subtitlesOn)
                    }
                    Divider()
                    ForEach(SubtitleSize.allCases, id: \.self) { size in
                        Button { controller.subtitleSize = size } label: {
                            checkLabel("اندازه \(size.label)", checked: controller.subtitleSize == size)
                        }
                    }
                } label: {
                    Label("زیرنویس", systemImage: "captions.bubble")
                }
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.title3)
                .frame(width: 40, height: 40)
        }
    }

    @ViewBuilder
    private func checkLabel(_ title: String, checked: Bool) -> some View {
        if checked {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private var lockedOverlay: some View {
        VStack(spacing: 10) {
            Button { controller.locked = false } label: {
                Image(systemName: "lock.fill")
                    .font(.title2)
                    .frame(width: 60, height: 60)
                    .background(.black.opacity(0.6), in: Circle())
            }
            Text("برای باز کردن قفل بزنید")
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.black.opacity(0.5), in: Capsule())
        }
        .foregroundStyle(.white)
    }

    private func upNextCard(_ countdown: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("قسمت بعد در \(countdown) ثانیه")
                .font(.subheadline.bold())
            HStack(spacing: 10) {
                Button { controller.playNext() } label: {
                    Label("پخش", systemImage: "play.fill")
                        .font(.footnote.bold())
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Theme.accent, in: Capsule())
                }
                Button { controller.cancelUpNext() } label: {
                    Text("لغو")
                        .font(.footnote.bold())
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.white.opacity(0.18), in: Capsule())
                }
            }
        }
        .foregroundStyle(.white)
        .padding()
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
        .environment(\.layoutDirection, .rightToLeft)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(30)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .rightToLeft)
            HStack(spacing: 12) {
                Button("تلاش دوباره") { controller.retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                Button("بستن") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
    }

    private func rateLabel(_ rate: Float) -> String {
        rate == 1 ? "عادی" : "\(rate.formatted())x"
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// Seek bar showing the played and buffered parts; drag to seek.
private struct Scrubber: View {
    let current: Double
    let duration: Double
    let buffered: Double
    /// The time under the finger while dragging, nil when released.
    let onScrub: (Double?) -> Void
    let onSeek: (Double) -> Void

    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let shown = dragValue ?? current
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(.white.opacity(0.42))
                    .frame(width: width * fraction(buffered))
                Capsule().fill(Theme.accentText)
                    .frame(width: width * fraction(shown))
            }
            .frame(height: dragValue == nil ? 4 : 7)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: dragValue == nil ? 14 : 20)
                    .offset(x: width * fraction(shown) - (dragValue == nil ? 7 : 10))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0, width > 0 else { return }
                        let time = min(max(value.location.x / width, 0), 1) * duration
                        dragValue = time
                        onScrub(time)
                    }
                    .onEnded { _ in
                        if let dragValue { onSeek(dragValue) }
                        dragValue = nil
                        onScrub(nil)
                    }
            )
        }
        .frame(height: 30)
        .animation(.easeOut(duration: 0.15), value: dragValue == nil)
    }

    private func fraction(_ time: Double) -> CGFloat {
        guard duration > 0, time.isFinite else { return 0 }
        return CGFloat(min(max(time / duration, 0), 1))
    }
}

enum SubtitleSize: String, CaseIterable {
    case small, medium, large

    var points: CGFloat {
        switch self {
        case .small: return 16
        case .medium: return 20
        case .large: return 27
        }
    }

    var label: String {
        switch self {
        case .small: return "کوچک"
        case .medium: return "متوسط"
        case .large: return "بزرگ"
        }
    }
}

@MainActor
final class PlayerController: ObservableObject {
    static let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    let player = AVPlayer()
    @Published private(set) var item: PlaybackItem
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = true
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var buffered: Double = 0
    @Published private(set) var rate: Float = 1
    @Published private(set) var currentCue: SubtitleCue?
    @Published private(set) var hasSubtitles = false
    @Published var subtitlesOn = true
    @Published var subtitleSize = SubtitleSize(rawValue: UserDefaults.standard.string(forKey: "kf.subtitleSize") ?? "") ?? .medium {
        didSet { UserDefaults.standard.set(subtitleSize.rawValue, forKey: "kf.subtitleSize") }
    }
    @Published private(set) var fill = false
    @Published var locked = false {
        didSet { poke() }
    }
    @Published private(set) var controlsVisible = true
    /// Bumped on every touch; restarts the auto-hide timer.
    @Published private(set) var interaction = 0
    @Published private(set) var pipPossible = false
    @Published private(set) var nextCountdown: Int?
    @Published private(set) var failure: String?

    private var api: APIClient?
    private var timeObserver: Any?
    private var observations: [NSKeyValueObservation] = []
    private var itemObservations: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    private var cues: [SubtitleCue] = []
    private var lastSavedPosition: Double = -1
    private var lastSaveCheck = Date()
    private var pip: AVPictureInPictureController?
    private var countdownTask: Task<Void, Never>?

    init(item: PlaybackItem) {
        self.item = item
    }

    var currentQuality: String? {
        item.sources.first { $0.url == item.url }?.label
    }

    /// - Parameter api: nil for guests, who have no progress to save.
    func start(api: APIClient?) {
        self.api = api
        player.allowsExternalPlayback = true
        observations.append(player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                self?.isPlaying = status != .paused
                self?.isBuffering = status == .waitingToPlayAtSpecifiedRate
            }
        })
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in self?.tick(time.seconds) }
        }
        load(item, at: item.startAt)
        loadSubtitles()
        registerCast()
    }

    func stop() {
        countdownTask?.cancel()
        CastManager.shared.setMedia(nil)
        saveProgress(reason: "close")
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        observations.removeAll()
        itemObservations.removeAll()
    }

    // MARK: Controls

    func togglePlay() {
        if isPlaying {
            player.pause()
        } else {
            if duration > 0 && currentTime >= duration - 1 { seek(to: 0) }
            player.play()
        }
        poke()
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func seek(to seconds: Double) {
        let target = max(0, duration > 0 ? min(seconds, duration - 1) : seconds)
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setRate(_ rate: Float) {
        self.rate = rate
        player.defaultRate = rate
        if isPlaying { player.rate = rate }
    }

    func setFill(_ fill: Bool) {
        self.fill = fill
    }

    func toggleControls() {
        if controlsVisible {
            controlsVisible = false
        } else {
            poke()
        }
    }

    /// Shows the controls and restarts the auto-hide timer.
    func poke() {
        controlsVisible = true
        interaction += 1
    }

    func hideControlsIfIdle() {
        if isPlaying || locked { controlsVisible = false }
    }

    /// Another quality of the same video, from the same position.
    func switchSource(_ source: PlaybackSource) {
        guard source.url != item.url else { return }
        let position = currentTime
        item.url = source.url
        load(item, at: position)
        registerCast()
    }

    func playNext() {
        guard let next = item.upNext.first else { return }
        cancelUpNext()
        saveProgress(reason: "close")
        var upcoming = next
        upcoming.upNext = Array(item.upNext.dropFirst())
        item = upcoming
        cues = []
        currentCue = nil
        hasSubtitles = false
        lastSavedPosition = -1
        load(upcoming, at: upcoming.startAt)
        loadSubtitles()
        registerCast()
        poke()
    }

    func cancelUpNext() {
        countdownTask?.cancel()
        countdownTask = nil
        nextCountdown = nil
    }

    func retry() {
        load(item, at: currentTime)
    }

    func togglePiP() {
        guard let pip else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }

    func attach(_ layer: AVPlayerLayer) {
        guard pip == nil, AVPictureInPictureController.isPictureInPictureSupported(),
              let pip = AVPictureInPictureController(playerLayer: layer)
        else { return }
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        self.pip = pip
        observations.append(pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] pip, _ in
            let possible = pip.isPictureInPicturePossible
            Task { @MainActor in self?.pipPossible = possible }
        })
    }

    // MARK: Playback

    private func load(_ item: PlaybackItem, at position: Double) {
        failure = nil
        isBuffering = true
        let playerItem = AVPlayerItem(url: item.url)
        itemObservations = [
            playerItem.observe(\.status, options: [.new]) { [weak self] playerItem, _ in
                let failed = playerItem.status == .failed
                Task { @MainActor in
                    guard failed else { return }
                    self?.failure = "پخش این ویدیو ممکن نیست. اتصال اینترنت را بررسی کنید و دوباره تلاش کنید."
                }
            },
        ]
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reachedEnd() }
        }

        player.replaceCurrentItem(with: playerItem)
        if position > 5 {
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = position
        }
        player.defaultRate = rate
        player.play()
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        currentTime = seconds
        if let current = player.currentItem {
            let total = current.duration.seconds
            if total.isFinite, total > 0, total != duration { duration = total }
            let now = player.currentTime()
            let range = current.loadedTimeRanges.map(\.timeRangeValue).first { $0.containsTime(now) }
            buffered = range.map { $0.end.seconds } ?? seconds
        }
        let cue = subtitlesOn ? Subtitles.cue(at: seconds, in: cues) : nil
        if cue != currentCue { currentCue = cue }
        if Date().timeIntervalSince(lastSaveCheck) >= 15 {
            lastSaveCheck = Date()
            saveProgress(reason: "interval")
        }
    }

    private func reachedEnd() {
        saveProgress(reason: "close")
        guard !item.upNext.isEmpty else {
            poke()
            return
        }
        nextCountdown = 8
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self, let value = self.nextCountdown else { return }
                self.nextCountdown = value - 1
            }
            guard !Task.isCancelled else { return }
            self?.playNext()
        }
    }

    private func loadSubtitles() {
        guard let url = item.subtitleURL else { return }
        let expected = item.id
        Task {
            let loaded = await Subtitles.load(from: url)
            guard item.id == expected else { return }
            cues = loaded
            hasSubtitles = !loaded.isEmpty
        }
    }

    /// Picking a Cast device moves playback to the TV from the current position.
    private func registerCast() {
        guard !item.isOffline else {
            CastManager.shared.setMedia(nil)
            return
        }
        CastManager.shared.setMedia(.init(item: item,
                                          position: { [weak player = self.player] in player?.currentTime().seconds ?? 0 },
                                          onCastStarted: { [weak self] in
                                              self?.saveProgress(reason: "close")
                                              self?.player.pause()
                                          }))
    }

    private func saveProgress(reason: String) {
        // Trailers (postId 0) have no progress.
        guard let api, item.postId > 0 else { return }
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

/// The video layer; also the source for Picture in Picture.
private struct VideoSurface: UIViewRepresentable {
    let controller: PlayerController
    let fill: Bool

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.player = controller.player
        controller.attach(view.playerLayer)
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }
}

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(Theme.accentText)
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

/// Rotates the interface for the player.
@MainActor
enum Orientation {
    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    static var screen: UIScreen? { scene?.screen }

    static func request(_ mask: UIInterfaceOrientationMask) {
        guard let scene else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }

    static func toggle() {
        request(scene?.interfaceOrientation.isLandscape == true ? .portrait : .landscapeRight)
    }
}
