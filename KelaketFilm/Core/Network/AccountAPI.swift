import Foundation

// Blog, profile, wallet, referral and session routes (phase 4).
extension APIClient {
    func blogPosts(page: Int) async throws -> BlogPage {
        try await send(Endpoint(path: "mobile/v2/blog/list",
                                query: ["page": String(page), "per_page": "10"]))
    }

    func blogPost(id: Int) async throws -> BlogPost {
        let response = try await send(Endpoint(path: "mobile/v2/blog/single", query: ["id": String(id)]),
                                      as: BlogSingleResponse.self)
        guard let post = response.data else {
            throw APIError.badStatus(404, response.message ?? "مطلب پیدا نشد.")
        }
        return post
    }

    // MARK: Profile

    func avatarOptions() async throws -> AvatarOptions {
        try await send(Endpoint(path: "mobile/v2/avatar/options"))
    }

    /// Empty strings / nil leave a field unchanged. A new password revokes
    /// every token issued before it (`kelaket_jwt_valid_after`).
    func editProfile(userId: Int, name: String, email: String, password: String?,
                     defaultAvatarId: Int?) async throws -> EditUserResponse {
        var body: [String: String] = [
            "id": String(userId),
            "token": userToken ?? "",
            "name": name,
            "newEmail": email,
        ]
        if let password, !password.isEmpty { body["password"] = password }
        if let defaultAvatarId { body["default_avatar_id"] = String(defaultAvatarId) }
        return try await send(Endpoint(path: "mobile/v1/editUser", method: .post, body: body))
    }

    /// Emails a WordPress password-reset link.
    func requestPasswordReset(email: String) async throws -> ActionResponse {
        try await send(Endpoint(path: "mobile/v2/resetpass", method: .post,
                                body: ["email": email] as [String: String]))
    }

    // MARK: Money

    func wallet(page: Int) async throws -> WalletPage {
        try await send(Endpoint(path: "mobile/v2/wallet", query: ["page": String(page)]))
    }

    func referral(page: Int) async throws -> ReferralPage {
        try await send(Endpoint(path: "mobile/v2/referral", query: ["page": String(page)]))
    }

    func vipTransactions(page: Int) async throws -> [VipPayment] {
        try await send(Endpoint(path: "mobile/v2/vip/getTransactions", query: ["page": String(page)]),
                       as: VipPaymentList.self).items
    }

    // MARK: Active sessions

    func activeSessions() async throws -> [ActiveSession] {
        try await send(Endpoint(path: "mobile/v2/active-sessions", headers: sessionHeaders),
                       as: ActiveSessions.self).sessions
    }

    /// Signs out one session by `sid`, or every session (this one included) when `all`.
    func logoutSession(sid: String?, all: Bool) async throws -> ActionResponse {
        var body: [String: String] = ["all": all ? "1" : "0"]
        if let sid { body["sid"] = sid }
        return try await send(Endpoint(path: "mobile/v2/active-sessions/logout", method: .post,
                                       body: body, headers: sessionHeaders))
    }

    /// The theme's session module reads the token itself; send it in every
    /// place it may look. Only used here, so other routes never see a Bearer header.
    private var sessionHeaders: [String: String] {
        guard let userToken else { return [:] }
        return ["Authorization": "Bearer \(userToken)"]
    }
}
