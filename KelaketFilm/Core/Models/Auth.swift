import Foundation

/// Response of the OTP endpoint (`mobile/v1/auth`) and of password login
/// (`mobile/v2/loginByUsernameEmailPhone`). On success both carry the JWT plus
/// the subscription fields added by the plugin's `mod_jwt_token` filter.
///
/// OTP codes: 201 sent, -1 rate limited, 300 bad number, 301 wrong code,
/// 302 expired, 200 logged in. Password login uses `success` and string codes.
struct AuthResponse: Decodable {
    @LossyString var code: String?
    @LossyString var message: String?
    @LossyBool var success: Bool
    @LossyBool var sent: Bool

    @LossyString var token: String?
    @LossyInt var id: Int?
    @LossyString var userEmail: String?
    @LossyString var userDisplayName: String?
    @LossyString var mobile: String?
    @LossyString var avatar: String?
}

/// `GET mobile/v2/userInfo` — subscription state for the signed-in user.
struct UserInfo: Decodable {
    @LossyBool var success: Bool
    @LossyString var msg: String?
    @LossyInt var id: Int?
    @LossyBool var hasActiveSub: Bool
    @LossyBool var isExpired: Bool
    @LossyString var subStateFa: String?
    @LossyString var expirationDate: String?
    @LossyInt var subDaysRemain: Int?
}

/// `POST mobile/v1/users/register`
struct RegisterResponse: Decodable {
    @LossyString var code: String?
    @LossyString var message: String?
}

/// Stored after login so the profile can render without a round trip.
struct StoredUser: Codable {
    var id: Int?
    var displayName: String?
    var email: String?
    var mobile: String?
    var avatar: String?
}
