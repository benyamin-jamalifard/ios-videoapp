import Foundation

// MARK: Blog

/// `GET mobile/v2/blog/list`
struct BlogPage: Decodable {
    @LossyArray var data: [BlogPost]
    @LossyObject var pagination: Pagination?

    struct Pagination: Decodable, Hashable {
        @LossyBool var hasMore: Bool
    }
}

/// A blog post; the list fills the summary fields, `blog/single` the rest.
struct BlogPost: Decodable, Hashable, Identifiable {
    let id: Int
    @LossyString var title: String?
    @LossyString var excerpt: String?
    @LossyString var datePersian: String?
    @LossyString var date: String?
    @LossyString var thumbnail: String?
    /// HTML, only on `blog/single`.
    @LossyString var content: String?
    @LossyArray var categories: [Term]
    @LossyArray var relatedPosts: [BlogPost]
    @LossyObject var author: Author?

    /// The list sends the author as a plain name; `blog/single` as an object.
    struct Author: Decodable, Hashable {
        let name: String?

        init(from decoder: Decoder) throws {
            struct Object: Decodable { @LossyString var name: String? }
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                name = string
            } else {
                name = (try? container.decode(Object.self))?.name
            }
        }
    }

    var displayDate: String? { datePersian ?? date }
}

struct BlogSingleResponse: Decodable {
    @LossyObject var data: BlogPost?
    @LossyString var message: String?
}

// MARK: Profile

/// `GET mobile/v2/avatar/options`
struct AvatarOptions: Decodable {
    @LossyArray var defaultAvatars: [DefaultAvatar]
    @LossyObject var currentAvatar: CurrentAvatar?

    struct DefaultAvatar: Decodable, Hashable, Identifiable {
        let id: Int
        @LossyString var url: String?
    }

    struct CurrentAvatar: Decodable, Hashable {
        @LossyString var url: String?
        @LossyInt var defaultAvatarId: Int?
    }
}

/// `POST mobile/v1/editUser` — code 200 on success, 330–332 on errors.
struct EditUserResponse: Decodable {
    @LossyString var code: String?
    @LossyString var message: String?
    @LossyString var avatar: String?
}

// MARK: Wallet & referral

/// `GET mobile/v2/wallet`
struct WalletPage: Decodable {
    @LossyString var balance: String?
    @LossyArray var items: [WalletEntry]
    @LossyObject var pagination: PagePagination?
}

/// A wallet or referral record. The theme's classes build these rows, so
/// several plausible column names are read.
struct WalletEntry: Decodable, Hashable {
    @LossyString var amount: String?
    @LossyString var type: String?
    @LossyString var description: String?
    @LossyString var note: String?
    @LossyString var reason: String?
    @LossyString var createdAt: String?
    @LossyString var referredUserName: String?

    var title: String? { description ?? note ?? reason ?? referredUserName }
    /// Debits are stored negative or typed as withdrawals.
    var isDebit: Bool {
        (amount?.hasPrefix("-") ?? false) || ["debit", "withdraw", "purchase", "decrease"].contains(type ?? "")
    }
}

struct PagePagination: Decodable, Hashable {
    @LossyInt var currentPage: Int?
    @LossyInt var totalPages: Int?
}

/// `GET mobile/v2/referral`
struct ReferralPage: Decodable {
    @LossyString var code: String?
    @LossyString var inviteLink: String?
    @LossyString var totalEarnings: String?
    @LossyInt var referredUsersCount: Int?
    @LossyString var commissionPercent: String?
    @LossyArray var items: [WalletEntry]
    @LossyObject var pagination: PagePagination?
}

/// A VIP payment from `vip/getTransactions` (theme's `Kelaket_VIP::get_payments`).
struct VipPayment: Decodable, Hashable {
    @LossyString var planName: String?
    @LossyString var plan: String?
    @LossyString var amount: String?
    @LossyString var price: String?
    @LossyString var status: String?
    @LossyString var gateway: String?
    @LossyString var createdAt: String?
    @LossyString var date: String?
    @LossyString var transactionHash: String?

    var title: String { planName ?? plan ?? "اشتراک" }
    var total: String? { amount ?? price }
    var when: String? { createdAt ?? date }
}

/// The payments come either as a bare array or wrapped in an object.
struct VipPaymentList: Decodable {
    let items: [VipPayment]

    init(from decoder: Decoder) throws {
        if let array = try? LossyArray<VipPayment>(from: decoder), !array.wrappedValue.isEmpty {
            items = array.wrappedValue
            return
        }
        struct Wrapped: Decodable {
            @LossyArray var data: [VipPayment]
            @LossyArray var items: [VipPayment]
            @LossyArray var payments: [VipPayment]
        }
        let wrapped = try? Wrapped(from: decoder)
        items = wrapped.map { $0.data + $0.items + $0.payments } ?? []
    }
}

// MARK: Active sessions

/// `GET mobile/v2/active-sessions`
struct ActiveSessions: Decodable {
    @LossyArray var sessions: [ActiveSession]
}

struct ActiveSession: Decodable, Hashable, Identifiable {
    @LossyString var sid: String?
    @LossyString var sourceLabel: String?
    @LossyString var clientName: String?
    @LossyString var browser: String?
    @LossyString var app: String?
    @LossyString var appVersion: String?
    @LossyString var ip: String?
    @LossyString var lastSeenHuman: String?
    @LossyBool var isCurrent: Bool

    var id: String { sid ?? UUID().uuidString }
    var title: String { clientName ?? app ?? browser ?? sourceLabel ?? "دستگاه" }
}
