import SwiftUI
#if canImport(GoogleCast)
import GoogleCast
#endif

/// Google Cast (Chromecast, Android TV). AirPlay needs no code: the system
/// player shows its own AirPlay button.
///
/// The SDK comes from CocoaPods (see Podfile); without it this compiles to
/// no-ops so the app still builds. All calls happen on the main thread: the
/// app delegate, the player, and the SDK's own callbacks.
final class CastManager: NSObject {
    static let shared = CastManager()

    /// The video on screen, cast as soon as a device is picked.
    struct Media {
        let item: PlaybackItem
        let position: () -> Double
        let onCastStarted: () -> Void
    }

    private var media: Media?

    static func configure() {
        #if canImport(GoogleCast)
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        options.suspendSessionsWhenBackgrounded = false
        GCKCastContext.setSharedInstanceWith(options)
        GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = true
        GCKCastContext.sharedInstance().sessionManager.add(shared)
        #endif
    }

    /// Registers the playing video; casts it right away if a session is already up.
    func setMedia(_ media: Media?) {
        self.media = media
        #if canImport(GoogleCast)
        if media != nil, GCKCastContext.sharedInstance().sessionManager.hasConnectedCastSession() {
            loadCurrentMedia()
        }
        #endif
    }

    #if canImport(GoogleCast)
    private func loadCurrentMedia() {
        guard let media,
              let client = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient
        else { return }
        let item = media.item

        let metadata = GCKMediaMetadata(metadataType: .movie)
        metadata.setString(item.title, forKey: kGCKMetadataKeyTitle)
        if let poster = item.posterURL {
            metadata.addImage(GCKImage(url: poster, width: 480, height: 720))
        }

        let builder = GCKMediaInformationBuilder(contentURL: item.url)
        builder.streamType = .buffered
        builder.contentType = item.url.pathExtension.lowercased() == "m3u8" ? "application/x-mpegURL" : "video/mp4"
        builder.metadata = metadata

        // The default receiver shows WebVTT tracks (the subtitle host must allow CORS).
        let options = GCKMediaLoadOptions()
        if let subtitle = item.subtitleURL, subtitle.pathExtension.lowercased() == "vtt" {
            builder.mediaTracks = [GCKMediaTrack(identifier: 1,
                                                 contentIdentifier: subtitle.absoluteString,
                                                 contentType: "text/vtt",
                                                 type: .text,
                                                 textSubtype: .subtitles,
                                                 name: "فارسی",
                                                 languageCode: "fa",
                                                 customData: nil)]
            options.activeTrackIDs = [1]
        }
        options.playPosition = media.position()
        options.autoplay = true

        client.loadMedia(builder.build(), with: options)
        media.onCastStarted()
        GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls()
    }
    #endif
}

#if canImport(GoogleCast)
extension CastManager: GCKSessionManagerListener {
    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
        loadCurrentMedia()
    }
}
#endif

/// The Cast device picker; hidden when the Cast SDK isn't in the build.
struct CastButton: View {
    var body: some View {
        #if canImport(GoogleCast)
        CastButtonRepresentable()
            .frame(width: 24, height: 24)
        #else
        EmptyView()
        #endif
    }
}

#if canImport(GoogleCast)
private struct CastButtonRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
        let button = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        button.tintColor = .white
        return button
    }

    func updateUIView(_ button: GCKUICastButton, context: Context) {}
}
#endif
