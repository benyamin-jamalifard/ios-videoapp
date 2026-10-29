import Foundation
import Network

/// Whether the site answers, and when lists should reload.
///
/// In an Iranian internet shutdown the phone still has a connection (the
/// national network), so the device's own status says little. What matters
/// is whether the site answered the last request: when it didn't, the app
/// shows its saved copies, checks again every 30 seconds, and reloads
/// everything as soon as the site is back.
@MainActor
final class NetworkStatus: ObservableObject {
    static let shared = NetworkStatus()

    /// False while requests are being answered from the offline copies.
    @Published private(set) var serverReachable = true
    /// False when the phone has no connection at all.
    @Published private(set) var hasConnection = true
    /// Bumped whenever on-screen lists should reload: the site came back,
    /// the app returned after a while, or every 10 minutes in use.
    @Published private(set) var refreshToken = 0

    private let monitor = NWPathMonitor()
    private var probeTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?
    private var backgroundedAt: Date?
    private var lastRefresh = Date()

    private init() {
        monitor.pathUpdateHandler = { path in
            let connected = path.status == .satisfied
            Task { @MainActor in NetworkStatus.shared.connectionChanged(connected) }
        }
        monitor.start(queue: DispatchQueue(label: "kf.network-monitor"))
        startPeriodicRefresh()
    }

    /// Called by `APIClient` after each request.
    func report(reachable: Bool) {
        guard reachable != serverReachable else { return }
        serverReachable = reachable
        if reachable {
            probeTask?.cancel()
            probeTask = nil
            refresh()
        } else {
            startProbing()
        }
    }

    /// Reload now (pull to refresh, the retry button).
    func refresh() {
        lastRefresh = Date()
        refreshToken += 1
    }

    func appMovedToBackground() {
        backgroundedAt = Date()
        periodicTask?.cancel()
    }

    func appBecameActive() {
        if let backgroundedAt, Date().timeIntervalSince(backgroundedAt) > 120 { refresh() }
        backgroundedAt = nil
        startPeriodicRefresh()
    }

    private func connectionChanged(_ connected: Bool) {
        let regained = connected && !hasConnection
        hasConnection = connected
        if regained {
            // Give the network a moment, then try the site again.
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if await APIClient.shared.ping() { report(reachable: true) }
                refresh()
            }
        }
    }

    private func startProbing() {
        guard probeTask == nil else { return }
        probeTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                if await APIClient.shared.ping() {
                    probeTask = nil
                    report(reachable: true)
                    return
                }
            }
        }
    }

    private func startPeriodicRefresh() {
        periodicTask?.cancel()
        periodicTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                if serverReachable, Date().timeIntervalSince(lastRefresh) >= 600 { refresh() }
            }
        }
    }
}
