import Foundation

public enum ContactMethod: String, Codable, Sendable, CaseIterable {
    case sms, whatsapp, instagram
}

public enum PermitStatus: String, Codable, Sendable {
    case none, pending, verified, rejected, expired
}

public enum ServingStatus: String, Codable, Sendable {
    case closed, serving
    case soldOut = "sold_out"
}

/// A cook, as a buyer sees them.
///
/// `contactValue` is absent by design — the cook's phone/handle is not exposed
/// before a confirmed claim, same principle as the kitchen's exact point.
/// Handoff goes through a server-side call that opens the channel.
public struct Cook: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: UUID
    public let displayName: String
    public let bio: String?
    /// The kitchen's cover photo, shown as the profile hero. Nil falls back to
    /// the headline dish — see migration 060.
    public let coverURL: String?
    public let avatarPath: String?
    public let instagram: String?
    /// **Not readable by clients.** Migration 055 withheld this column from
    /// the `anon`/`authenticated` grant, so it never arrives over the wire and
    /// this is always `false` in the app. Kept because the model mirrors the
    /// table; a synthesised non-optional decode of it made every `Cook` fetch
    /// fail with `keyNotFound`.
    public var phoneVerified: Bool = false

    /// Public **by law**, unlike the address, which never is. The platform
    /// must expose a dedicated permit-number field per cook (`PRD.md` §8).
    public let permitStatus: PermitStatus
    public let permitNumber: String?
    public let permitAgencyID: UUID?
    public let permitExpires: Date?

    public let servingStatus: ServingStatus
    public let servingNote: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case bio
        case coverURL = "cover_url"
        case avatarPath = "avatar_path"
        case instagram
        case permitStatus = "permit_status"
        case permitNumber = "permit_number"
        case permitAgencyID = "permit_agency_id"
        case permitExpires = "permit_expires"
        case servingStatus = "serving_status"
        case servingNote = "serving_note"
    }

    public var isVerified: Bool { permitStatus == .verified }
}
