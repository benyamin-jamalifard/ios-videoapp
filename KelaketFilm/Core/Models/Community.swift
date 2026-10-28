import Foundation

/// The plugin answers actions in three shapes: `{success|error, msg|message}`,
/// `wp_send_json_success/error` (`{success, data: {msg}}`) and WP_Error.
/// This reads any of the first two.
struct ActionResponse: Decodable {
    @LossyBool var success: Bool
    @LossyBool var error: Bool
    @LossyString var msg: String?
    @LossyString var message: String?
    @LossyObject var data: Payload?
    /// `set_post_notification`
    @LossyBool var isAdded: Bool
    /// `send_comment`: "approved", "hold" or "failed"
    @LossyString var status: String?
    @LossyObject var comment: Comment?

    struct Payload: Decodable, Hashable {
        @LossyString var msg: String?
    }

    var text: String? { msg ?? message ?? data?.msg }
}

struct Comment: Decodable, Hashable, Identifiable {
    @LossyString var commentID: String?
    @LossyString var commentAuthor: String?
    @LossyString var commentDate: String?
    @LossyString var commentContent: String?
    @LossyString var avatar: String?
    @LossyBool var isSpoiler: Bool
    @LossyInt var likeCount: Int?
    @LossyInt var dislikeCount: Int?
    @LossyArray var replies: [Comment]

    var id: String { commentID ?? "\(commentAuthor ?? "")-\(commentDate ?? "")" }
}

/// `GET mobile/v2/get_comments`
struct CommentPage: Decodable {
    @LossyInt var currentPage: Int?
    @LossyInt var totalPages: Int?
    @LossyInt var totalComments: Int?
    @LossyArray var comments: [Comment]
}

struct Ticket: Decodable, Hashable, Identifiable {
    let id: Int
    @LossyString var subject: String?
    @LossyInt var status: Int?
    @LossyString var department: String?
    @LossyString var createdAt: String?

    /// The plugin sets status 1 whenever the user writes; other values are set from the admin panel.
    var statusLabel: String? {
        switch status {
        case 1: return "در انتظار پاسخ"
        case 2: return "پاسخ داده شده"
        default: return nil
        }
    }
}

struct TicketMessage: Decodable, Hashable, Identifiable {
    let id: Int
    @LossyString var msg: String?
    @LossyInt var userId: Int?
    @LossyString var createdAt: String?
}

/// A row of the user's film requests (`kelaket_reqs`).
struct FilmRequest: Decodable, Hashable, Identifiable {
    @LossyInt var id: Int?
    @LossyString var name: String?
    /// 1 film, 2 series
    @LossyInt var type: Int?
    @LossyString var status: String?
    @LossyString var createdAt: String?
    @LossyInt var postId: Int?
}

/// `GET mobile/v2/get_notifications` — rows of the theme's `kelaket_notifs` table.
/// Column names vary between theme versions, so several are tried. `n.*` comes
/// straight from `$wpdb`, so every column, the id included, arrives as a string.
struct AppNotification: Decodable, Hashable, Identifiable {
    @LossyInt var id: Int?
    @LossyString var title: String?
    @LossyString var content: String?
    @LossyString var text: String?
    @LossyString var body: String?
    @LossyString var link: String?
    @LossyString var url: String?
    @LossyInt var postId: Int?
    @LossyString var createdAt: String?
    @LossyBool var isRead: Bool

    var message: String? { (content ?? text ?? body)?.plainText }
    var linkURL: URL? { (link ?? url).flatMap(URL.init(string:)) }
}

struct NotificationList: Decodable {
    @LossyArray var notifs: [AppNotification]
}

/// One entry of the theme's `ticket_dep` option; either a plain string or a
/// repeater row whose first text field is the name.
struct TicketDepartment: Decodable, Hashable {
    let name: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            name = string
        } else if let row = try? container.decode([String: LossyString].self),
                  let first = row.sorted(by: { $0.key < $1.key }).compactMap(\.value.wrappedValue).first {
            name = first
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "No department name")
        }
    }
}
