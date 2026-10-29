import Foundation

/// Typed wrappers for the plugin routes the app uses.
/// Route definitions live in kelaketfilm-app/includes/api.php.
extension APIClient {
    func config() async throws -> AppConfig {
        // Short: the splash waits for it, and the saved copy covers a slow site.
        try await send(Endpoint(path: "mobile/v2/config", timeout: 12))
    }

    func homeScreen() async throws -> HomeScreen {
        try await send(Endpoint(path: "mobile/v2/home_screen"))
    }

    func film(id: Int) async throws -> FilmDetail {
        try await send(Endpoint(path: "mobile/v2/film/\(id)"))
    }

    func search(_ text: String, filter: SearchFilter = SearchFilter(), page: Int = 1) async throws -> [Post] {
        var query = filter.query
        query["s"] = text
        query["page"] = String(page)
        let result: LossyArray<Post> = try await send(Endpoint(path: "mobile/v1/search", query: query))
        return result.wrappedValue
    }

    // MARK: Auth

    /// Step 1 of OTP login: ask the server to text a code to `phone` (11 digits, 09…).
    func requestOTP(phone: String) async throws -> AuthResponse {
        try await send(Endpoint(path: "mobile/v1/auth", method: .post,
                                body: ["phone": phone] as [String: String]))
    }

    /// Step 2 of OTP login: exchange the code for a JWT. Unknown numbers are registered.
    func verifyOTP(phone: String, code: String) async throws -> AuthResponse {
        try await send(Endpoint(path: "mobile/v1/auth", method: .post,
                                body: ["phone": phone, "user_otp": code] as [String: String]))
    }

    /// `username` may be a username, an email or a phone number.
    func login(username: String, password: String) async throws -> AuthResponse {
        try await send(Endpoint(path: "mobile/v2/loginByUsernameEmailPhone", method: .post,
                                body: ["username": username, "password": password] as [String: String]))
    }

    func register(username: String, email: String, password: String, referralCode: String?) async throws -> RegisterResponse {
        var body: [String: String] = ["username": username, "email": email, "password": password]
        if let referralCode, !referralCode.isEmpty {
            body["ref_code"] = referralCode
        }
        return try await send(Endpoint(path: "mobile/v1/users/register", method: .post, body: body))
    }

    func userInfo() async throws -> UserInfo {
        try await send(Endpoint(path: "mobile/v2/userInfo"))
    }

    // MARK: Watch progress

    func saveWatchProgress(_ progress: WatchProgressSave) async throws {
        _ = try await send(Endpoint(path: "mobile/v2/watch_progress/save", method: .post,
                                    body: progress), as: IgnoredResponse.self)
    }
}

// MARK: - Personal features (phase 2)

extension APIClient {
    func watchlist() async throws -> [Post] {
        let result: LossyArray<Post> = try await send(Endpoint(path: "mobile/v2/get_watchlist"))
        return result.wrappedValue
    }

    /// Adds the post, or removes it when already in the list.
    func toggleWatchlist(postId: Int) async throws -> ActionResponse {
        try await send(Endpoint(path: "mobile/v2/add_watchlist", method: .post,
                                body: ["post_id": postId] as [String: Int]))
    }

    /// Toggles "notify me about new episodes" for a post.
    func togglePostNotification(postId: Int) async throws -> ActionResponse {
        try await send(Endpoint(path: "mobile/v2/set_post_notification", method: .post,
                                body: ["post_id": postId] as [String: Int]))
    }

    /// `action` is "like" or "dislike". The plugin identifies the voter by `user_id`.
    func vote(postId: Int, userId: Int, action: String) async throws -> ActionResponse {
        try await send(Endpoint(path: "mobile/v2/setVote", method: .post,
                                body: ["post_id": String(postId), "user_id": String(userId),
                                       "user_action": action] as [String: String]))
    }

    func comments(postId: Int, page: Int, limit: Int = 10) async throws -> CommentPage {
        try await send(Endpoint(path: "mobile/v2/get_comments",
                                query: ["post_id": String(postId), "page": String(page),
                                        "limit": String(limit)]))
    }

    /// The plugin takes the author as a plain user id (`author`).
    func sendComment(postId: Int, userId: Int, content: String, parentId: Int?, isSpoiler: Bool) async throws -> ActionResponse {
        try await send(Endpoint(path: "mobile/v2/send_comment", method: .post,
                                body: CommentBody(post: postId, author: userId, content: content,
                                                  parentId: parentId ?? 0, isSpoiler: isSpoiler)))
    }

    /// `action` is "like" or "dislike".
    func rateComment(id: String, action: String) async throws -> ActionResponse {
        try await send(Endpoint(path: "mobile/v2/comments_like_dislike", method: .post,
                                body: ["comment_id": id, "action": action] as [String: String]))
    }

    // MARK: Tickets

    func tickets() async throws -> [Ticket] {
        let result: LossyArray<Ticket> = try await send(Endpoint(path: "mobile/v2/tickets"))
        return result.wrappedValue
    }

    func ticketMessages(ticketId: Int) async throws -> [TicketMessage] {
        let result: LossyArray<TicketMessage> = try await send(Endpoint(path: "mobile/v2/tickets_msg/\(ticketId)"))
        return result.wrappedValue
    }

    func createTicket(title: String, department: String, message: String) async throws -> ActionResponse {
        try await send(Endpoint(path: "mobile/v2/send_ticket", method: .post,
                                body: ["title": title, "dep": department, "message": message] as [String: String]))
    }

    func replyToTicket(ticketId: Int, message: String) async throws -> ActionResponse {
        try await send(Endpoint(path: "mobile/v2/send_ticket_message", method: .post,
                                body: ["ticket_id": String(ticketId), "message": message] as [String: String]))
    }

    // MARK: Film requests

    func filmRequests() async throws -> [FilmRequest] {
        let result: LossyArray<FilmRequest> = try await send(Endpoint(path: "mobile/v2/requests"))
        return result.wrappedValue
    }

    /// `category`: 1 film, 2 series.
    func sendFilmRequest(name: String, category: Int) async throws -> ActionResponse {
        try await send(Endpoint(path: "mobile/v1/sendRequest", method: .post,
                                body: ["name": name, "category": String(category)] as [String: String]))
    }

    // MARK: Notifications

    func notifications() async throws -> [AppNotification] {
        try await send(Endpoint(path: "mobile/v2/get_notifications"), as: NotificationList.self).notifs
    }

    /// Pass an id to mark one notification, or nil to mark them all as read.
    func markNotificationsRead(id: Int?) async throws {
        _ = try await send(Endpoint(path: "mobile/v2/set_notification_status", method: .post,
                                    body: ["uuid": id.map(String.init) ?? "read_all"] as [String: String]),
                           as: IgnoredResponse.self)
    }

    func syncPushToken(_ token: String) async throws {
        _ = try await send(Endpoint(path: "mobile/v2/sync_fcm_token", method: .post,
                                    body: ["fcm_token": token] as [String: String]),
                           as: IgnoredResponse.self)
    }
}

private struct CommentBody: Encodable {
    let post: Int
    let author: Int
    let content: String
    let parentId: Int
    let isSpoiler: Bool
}

/// For calls whose response body the app does not need.
struct IgnoredResponse: Decodable {
    init(from decoder: Decoder) throws {}
}
