import UIKit

/// App-wide state: remote config and the signed-in session.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var config: AppConfig = .fallback
    @Published private(set) var isConfigLoaded = false
    @Published private(set) var token: String?
    @Published private(set) var user: StoredUser?
    @Published private(set) var subscription: UserInfo?
    /// Outside Iran: an English, browse-only catalogue (see `Region`).
    @Published private(set) var isInternational = Region.isInternational

    let api: APIClient

    private static let tokenKey = "jwt"
    private static let userKey = "kf.user"

    init(api: APIClient = .shared) {
        self.api = api
        Self.matchUIKitDirection(isInternational)
        Theme.restore()
        token = Keychain.string(for: Self.tokenKey)
        api.userToken = token
        if let data = UserDefaults.standard.data(forKey: Self.userKey) {
            user = try? JSONDecoder().decode(StoredUser.self, from: data)
        }
    }

    var isSignedIn: Bool { token != nil }

    /// WordPress user id, needed by the routes that take `user_id`/`author` (votes, comments).
    var userId: Int? { user?.id ?? subscription?.id }

    func bootstrap() async {
        // The window exists by now (it did not when init ran).
        Self.matchUIKitDirection(isInternational)
        // After the first launch the app opens at once on the saved settings;
        // the site, its address and the country are checked behind the UI, so
        // a slow site or blocked foreign services (shutdowns) never hold the splash.
        if let saved = api.savedConfig() {
            Theme.apply(saved)
            config = saved
            isConfigLoaded = true
        }
        async let region = Region.refresh()
        if let host = await api.fetchPublishedHost(), host != api.currentHost {
            api.useHost(host)
        }
        var config = try? await api.config()
        // The published or cached address is down: fall back to the built-in one.
        if config == nil, let fallback = api.defaultHost, fallback != api.currentHost {
            api.useHost(fallback)
            config = try? await api.config()
        }
        if let config {
            Theme.apply(config)
            self.config = config
        }
        let international = await region
        if international != isInternational {
            Self.matchUIKitDirection(international)
            isInternational = international
        }
        isConfigLoaded = true
        // The international catalogue hides everything an account is for.
        if !isInternational { await refreshSubscription() }
    }

    /// The app is localized in Persian only, so UIKit lays out right to left.
    /// In the English app SwiftUI is left to right, and a List or Form on an
    /// RTL UIKit view would draw its rows mirrored; UIKit has to match.
    /// The window's trait as well, for what UIKit draws from it (the back arrow).
    private static func matchUIKitDirection(_ international: Bool) {
        UIView.appearance().semanticContentAttribute = international ? .forceLeftToRight : .unspecified
        guard #available(iOS 17, *) else { return }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        for window in windows {
            if international {
                window.traitOverrides.layoutDirection = .leftToRight
            } else {
                window.traitOverrides.remove(UITraitLayoutDirection.self)
            }
        }
    }

    /// Stores the JWT from a successful OTP or password login.
    func signIn(with response: AuthResponse) {
        guard let token = response.token else { return }
        AppAnalytics.signedIn(method: config.usesOTP ? "otp" : "password")
        self.token = token
        api.userToken = token
        Keychain.set(token, for: Self.tokenKey)

        let user = StoredUser(id: response.id,
                              displayName: response.userDisplayName,
                              email: response.userEmail,
                              mobile: response.mobile,
                              avatar: response.avatar)
        self.user = user
        UserDefaults.standard.set(try? JSONEncoder().encode(user), forKey: Self.userKey)

        Task { await refreshSubscription() }
    }

    /// Applies a profile edit to the cached user.
    func updateUser(displayName: String?, email: String?, avatar: String?) {
        var user = self.user ?? StoredUser()
        if let displayName, !displayName.isEmpty { user.displayName = displayName }
        if let email, !email.isEmpty { user.email = email }
        if let avatar, !avatar.isEmpty { user.avatar = avatar }
        self.user = user
        UserDefaults.standard.set(try? JSONEncoder().encode(user), forKey: Self.userKey)
    }

    func signOut() {
        token = nil
        user = nil
        subscription = nil
        api.userToken = nil
        Keychain.set(nil, for: Self.tokenKey)
        UserDefaults.standard.removeObject(forKey: Self.userKey)
    }

    func refreshSubscription() async {
        guard isSignedIn else { return }
        guard let info = try? await api.userInfo() else { return }
        if info.success {
            subscription = info
        } else {
            // The token expired (30 days) or was revoked by a password change.
            signOut()
        }
    }
}
