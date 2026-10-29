import SwiftUI
#if canImport(GoogleCast)
import GoogleCast
#endif

/// A TV found on the network.
struct CastDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let model: String?
}

/// Google Cast (Chromecast, Android TV) with the app's own device list and
/// remote. Only devices with a screen are listed: Google's own picker also
/// offers speakers, which can't show a film.
///
/// The SDK comes from CocoaPods (see Podfile); without it this compiles to
/// no-ops so the app still builds. Everything runs on the main thread.
@MainActor
final class CastManager: NSObject, ObservableObject {
    static let shared = CastManager()

    /// The video on screen, cast as soon as a device is picked.
    struct Media {
        let item: PlaybackItem
        let position: () -> Double
        let onCastStarted: () -> Void
    }

    enum PlayerState {
        case idle, loading, playing, paused, buffering
    }

    @Published private(set) var devices: [CastDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var connectingTo: String?
    @Published private(set) var connectedName: String?
    /// What the TV is playing, set once a video was sent to it.
    @Published private(set) var castingItem: PlaybackItem?
    @Published private(set) var playerState = PlayerState.idle
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var subtitlesOn = true
    @Published private(set) var volume: Float = 0.5
    @Published private(set) var lastError: String?

    var isAvailable: Bool {
        #if canImport(GoogleCast)
        return true
        #else
        return false
        #endif
    }

    var isConnected: Bool { connectedName != nil }

    private var media: Media?
    private var positionTimer: Timer?

    static func configure() {
        #if canImport(GoogleCast)
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        options.suspendSessionsWhenBackgrounded = false
        options.disableDiscoveryAutostart = true
        GCKCastContext.setSharedInstanceWith(options)
        GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = false
        let context = GCKCastContext.sharedInstance()
        context.sessionManager.add(shared)
        context.discoveryManager.add(shared)
        #endif
    }

    // MARK: Discovery

    func startScanning() {
        #if canImport(GoogleCast)
        let discovery = GCKCastContext.sharedInstance().discoveryManager
        discovery.passiveScan = false
        discovery.startDiscovery()
        isScanning = true
        refreshDevices()
        #endif
    }

    func stopScanning() {
        #if canImport(GoogleCast)
        GCKCastContext.sharedInstance().discoveryManager.stopDiscovery()
        #endif
        isScanning = false
    }

    #if canImport(GoogleCast)
    private var gckDevices: [GCKDevice] {
        let discovery = GCKCastContext.sharedInstance().discoveryManager
        return (0..<discovery.deviceCount).map { discovery.device(at: $0) }
            .filter { $0.hasCapabilities(.videoOut) }
    }

    private func refreshDevices() {
        devices = gckDevices.map { CastDevice(id: $0.deviceID, name: $0.friendlyName ?? "TV", model: $0.modelName) }
    }
    #endif

    // MARK: Session

    func connect(_ device: CastDevice) {
        #if canImport(GoogleCast)
        guard let target = gckDevices.first(where: { $0.deviceID == device.id }) else { return }
        lastError = nil
        connectingTo = device.name
        if !GCKCastContext.sharedInstance().sessionManager.startSession(with: target) {
            connectingTo = nil
            lastError = "اتصال به \(device.name) انجام نشد."
        }
        #endif
    }

    func disconnect() {
        #if canImport(GoogleCast)
        _ = GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
        #endif
    }

    /// Registers the playing video; casts it right away if a TV is already connected.
    func setMedia(_ media: Media?) {
        self.media = media
        if media != nil, isConnected { loadCurrentMedia() }
    }

    // MARK: Remote

    func togglePlay() {
        #if canImport(GoogleCast)
        guard let client else { return }
        _ = playerState == .playing ? client.pause() : client.play()
        #endif
    }

    func seek(to seconds: Double) {
        #if canImport(GoogleCast)
        guard let client else { return }
        let options = GCKMediaSeekOptions()
        options.interval = max(0, seconds)
        options.resumeState = .unchanged
        _ = client.seek(with: options)
        position = max(0, seconds)
        #endif
    }

    func skip(by seconds: Double) {
        seek(to: position + seconds)
    }

    func setSubtitles(_ on: Bool) {
        #if canImport(GoogleCast)
        guard let client else { return }
        _ = client.setActiveTrackIDs(on ? [1] : [])
        subtitlesOn = on
        #endif
    }

    func setVolume(_ value: Float) {
        #if canImport(GoogleCast)
        volume = value
        _ = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.setDeviceVolume(value)
        #endif
    }

    /// Stops the video on the TV but keeps the connection.
    func stopVideo() {
        #if canImport(GoogleCast)
        _ = client?.stop()
        #endif
        castingItem = nil
    }

    #if canImport(GoogleCast)
    private var client: GCKRemoteMediaClient? {
        GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient
    }

    private func loadCurrentMedia() {
        guard let media, let client else { return }
        let item = media.item

        let metadata = GCKMediaMetadata(metadataType: .movie)
        metadata.setString(item.title, forKey: kGCKMetadataKeyTitle)
        if let label = item.episodeLabel {
            metadata.setString(label, forKey: kGCKMetadataKeySubtitle)
        }
        if let poster = item.posterURL {
            metadata.addImage(GCKImage(url: poster, width: 480, height: 720))
        }

        let builder = GCKMediaInformationBuilder(contentURL: item.url)
        builder.streamType = .buffered
        builder.contentType = item.url.pathExtension.lowercased() == "m3u8" ? "application/x-mpegURL" : "video/mp4"
        builder.metadata = metadata

        // The default receiver shows WebVTT tracks (the subtitle host must allow CORS).
        let options = GCKMediaLoadOptions()
        if let subtitle = item.subtitleURL, subtitle.pathExtension.lowercased() == "vtt",
           let track = GCKMediaTrack(identifier: 1,
                                     contentIdentifier: subtitle.absoluteString,
                                     contentType: "text/vtt",
                                     type: .text,
                                     textSubtype: .subtitles,
                                     name: "فارسی",
                                     languageCode: "fa",
                                     customData: nil) {
            builder.mediaTracks = [track]
            options.activeTrackIDs = subtitlesOn ? [1] : []
        }
        options.playPosition = media.position()
        options.autoplay = true

        client.add(self)
        _ = client.loadMedia(builder.build(), with: options)
        castingItem = item
        position = options.playPosition
        playerState = .loading
        media.onCastStarted()
        startPositionTimer()
    }

    private func startPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in CastManager.shared.updatePosition() }
        }
    }

    private func updatePosition() {
        guard let client, let status = client.mediaStatus else { return }
        let current = client.approximateStreamPosition()
        if current.isFinite { position = current }
        if let total = status.mediaInformation?.streamDuration, total.isFinite, total > 0 { duration = total }
    }

    private func sessionEnded(error: Error?) {
        positionTimer?.invalidate()
        positionTimer = nil
        connectingTo = nil
        connectedName = nil
        castingItem = nil
        playerState = .idle
        if let error { lastError = error.localizedDescription }
    }
    #endif
}

#if canImport(GoogleCast)
extension CastManager: GCKSessionManagerListener {
    nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
        let name = session.device.friendlyName ?? "TV"
        let volume = session.currentDeviceVolume
        Task { @MainActor in
            self.connectingTo = nil
            self.connectedName = name
            self.volume = volume
            self.loadCurrentMedia()
        }
    }

    nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didResumeCastSession session: GCKCastSession) {
        let name = session.device.friendlyName ?? "TV"
        Task { @MainActor in
            self.connectedName = name
            self.client?.add(self)
            self.startPositionTimer()
        }
    }

    nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKCastSession, withError error: Error?) {
        Task { @MainActor in self.sessionEnded(error: error) }
    }

    nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didFailToStart session: GCKCastSession, withError error: Error) {
        Task { @MainActor in self.sessionEnded(error: error) }
    }
}

extension CastManager: GCKDiscoveryManagerListener {
    nonisolated func didUpdateDeviceList() {
        Task { @MainActor in self.refreshDevices() }
    }
}

extension CastManager: GCKRemoteMediaClientListener {
    nonisolated func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        let state: PlayerState
        switch mediaStatus?.playerState {
        case .playing: state = .playing
        case .paused: state = .paused
        case .buffering: state = .buffering
        case .loading: state = .loading
        default: state = .idle
        }
        let finished = mediaStatus?.playerState == .idle && mediaStatus?.idleReason == .finished
        Task { @MainActor in
            self.playerState = state
            if finished { self.castingItem = nil }
            self.updatePosition()
        }
    }
}
#endif

/// Opens the in-app TV list; shows a filled icon while connected.
struct CastButton: View {
    @ObservedObject private var cast = CastManager.shared
    @State private var showDevices = false

    var body: some View {
        if cast.isAvailable {
            Button { showDevices = true } label: {
                Image(systemName: cast.isConnected ? "tv.fill" : "tv")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(cast.isConnected ? Theme.accentText : .white)
                    .frame(width: 36, height: 36)
            }
            .sheet(isPresented: $showDevices) {
                CastDevicesSheet()
            }
        }
    }
}

/// TVs on the same Wi-Fi; picking one sends the current video to it.
struct CastDevicesSheet: View {
    @ObservedObject private var cast = CastManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let name = cast.connectedName {
                    Section {
                        Label("متصل به \(name)", systemImage: "tv.fill")
                            .foregroundStyle(Theme.accentText)
                        Button("قطع اتصال", role: .destructive) {
                            cast.disconnect()
                            dismiss()
                        }
                    }
                }

                Section {
                    ForEach(cast.devices) { device in
                        Button {
                            cast.connect(device)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tv")
                                    .font(.title3)
                                    .frame(width: 34)
                                    .foregroundStyle(Theme.accentText)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name).font(.body.weight(.medium))
                                    if let model = device.model {
                                        Text(model).font(.caption).foregroundStyle(Theme.secondaryText)
                                    }
                                }
                                Spacer()
                                if cast.connectingTo == device.name {
                                    ProgressView()
                                } else if cast.connectedName == device.name {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accentText)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if cast.devices.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("در حال جستجوی تلویزیون…")
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                } header: {
                    Text("تلویزیون‌ها")
                } footer: {
                    Text("گوشی و تلویزیون (Chromecast یا Android TV) باید به یک Wi-Fi وصل باشند. فقط دستگاه‌های دارای تصویر نمایش داده می‌شوند.")
                }

                if let error = cast.lastError {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("پخش روی تلویزیون")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("بستن") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.medium, .large])
        .onAppear { cast.startScanning() }
        .onDisappear { cast.stopScanning() }
        // Close once the TV has picked up the video.
        .onChange(of: cast.connectedName) { name in
            if name != nil { dismiss() }
        }
    }
}

/// The remote shown while a video plays on the TV.
struct CastRemoteView: View {
    @ObservedObject private var cast = CastManager.shared
    var onClose: (() -> Void)?

    @State private var scrub: Double?

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Label(cast.connectedName ?? "TV", systemImage: "tv.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.accentText)
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.headline)
                    }
                }
            }

            if let item = cast.castingItem {
                HStack(spacing: 14) {
                    RemoteImage(url: item.posterURL)
                        .frame(width: 64, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.headline).lineLimit(2)
                        if let label = item.episodeLabel {
                            Text(label).font(.subheadline).foregroundStyle(Theme.secondaryText)
                        }
                        Text(stateText).font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 0)
                }

                VStack(spacing: 4) {
                    Slider(value: Binding(get: { scrub ?? cast.position },
                                          set: { scrub = $0 }),
                           in: 0...max(cast.duration, 1),
                           onEditingChanged: { editing in
                        if !editing, let scrub {
                            cast.seek(to: scrub)
                            self.scrub = nil
                        }
                    })
                    .tint(Theme.accentText)
                    HStack {
                        Text(Self.time(scrub ?? cast.position))
                        Spacer()
                        Text(Self.time(cast.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                }
                .environment(\.layoutDirection, .leftToRight)

                HStack(spacing: 44) {
                    Button { cast.skip(by: -10) } label: {
                        Image(systemName: "gobackward.10").font(.title2)
                    }
                    Button { cast.togglePlay() } label: {
                        Image(systemName: cast.playerState == .playing ? "pause.fill" : "play.fill")
                            .font(.title)
                            .frame(width: 64, height: 64)
                            .background(Theme.accent, in: Circle())
                            .foregroundStyle(.white)
                    }
                    Button { cast.skip(by: 10) } label: {
                        Image(systemName: "goforward.10").font(.title2)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)

                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").foregroundStyle(Theme.secondaryText)
                    Slider(value: Binding(get: { Double(cast.volume) },
                                          set: { cast.setVolume(Float($0)) }),
                           in: 0...1)
                        .tint(Theme.accentText)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(Theme.secondaryText)
                }
                .environment(\.layoutDirection, .leftToRight)

                HStack {
                    if item.subtitleURL != nil {
                        Toggle("زیرنویس", isOn: Binding(get: { cast.subtitlesOn },
                                                         set: { cast.setSubtitles($0) }))
                            .tint(Theme.accent)
                            .fixedSize()
                    }
                    Spacer()
                    Button("توقف پخش") { cast.stopVideo() }
                        .buttonStyle(.bordered)
                    Button("قطع اتصال", role: .destructive) { cast.disconnect() }
                        .buttonStyle(.bordered)
                }
                .font(.footnote.bold())
            } else {
                Text("ویدیویی روی تلویزیون پخش نمی‌شود. یک فیلم یا قسمت را باز کنید تا روی تلویزیون پخش شود.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                Button("قطع اتصال", role: .destructive) { cast.disconnect() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var stateText: String {
        switch cast.playerState {
        case .playing: return "در حال پخش روی تلویزیون"
        case .paused: return "متوقف"
        case .buffering, .loading: return "در حال بارگذاری…"
        case .idle: return "آماده"
        }
    }

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// A slim bar over the tab bar while a video plays on the TV; opens the remote.
struct CastMiniBar: View {
    @ObservedObject private var cast = CastManager.shared
    @State private var showRemote = false

    var body: some View {
        if let item = cast.castingItem {
            Button { showRemote = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tv.fill").foregroundStyle(Theme.accentText)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.footnote.bold()).lineLimit(1)
                        Text(cast.connectedName ?? "").font(.caption2).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Button { cast.togglePlay() } label: {
                        Image(systemName: cast.playerState == .playing ? "pause.fill" : "play.fill")
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showRemote) {
                CastRemoteView(onClose: { showRemote = false })
                    .padding()
                    .presentationDetents([.medium])
            }
        }
    }
}
