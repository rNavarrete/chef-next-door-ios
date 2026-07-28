import Foundation
import Supabase

/// The account holder's own identity — the name and face a cook sees when this
/// person messages them or claims from them.
///
/// Distinct from ``CookRepository``, which is about a *kitchen*. A cook who
/// buys from another cook has one profile and one kitchen, and the two carry
/// different names on purpose: "Sofia" is a person, "Sofia's Panadería" is a
/// storefront.
public struct Profile: Equatable, Sendable {
    public let displayName: String
    /// A path inside the private `avatars` bucket, not a URL. The bucket is
    /// private (unlike `kitchen-photos`), so rendering one means minting a
    /// signed URL — see ``ProfileRepository/avatarURL(for:)``.
    public let avatarPath: String?
    public let createdAt: Date

    public init(displayName: String, avatarPath: String?, createdAt: Date) {
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.createdAt = createdAt
    }
}

/// Why a message could not be sent, when the reason is something the buyer can
/// fix rather than a failure to report.
///
/// The server raises distinct SQLSTATEs for these (`P0002`, `P0003`) precisely
/// so the app can open the right sheet instead of showing an error. Treating
/// them as errors is the bug this type exists to prevent.
public enum MessagingGate: Equatable, Sendable {
    /// Anonymous session. Needs a real account.
    case needsAccount
    /// Real account, no profile row yet. Needs a name.
    case needsProfile
}

@MainActor
public protocol ProfileRepository: AnyObject {
    func myProfile() async throws -> Profile?
    func saveProfile(name: String, avatarPath: String?) async throws
    /// Uploads image data and returns the storage path to hand to `saveProfile`.
    func uploadAvatar(_ data: Data) async throws -> String
    /// Signed URL for a private avatar. Nil when there is no avatar.
    func avatarURL(for path: String?) async throws -> URL?
}

@MainActor
public final class SupabaseProfileRepository: ProfileRepository {
    private let client: SupabaseClient
    private static let bucket = "avatars"

    public init(client: SupabaseClient = SupabaseEnvironment.shared) {
        self.client = client
    }

    public func myProfile() async throws -> Profile? {
        struct Row: Decodable {
            let display_name: String
            let avatar_path: String?
            let created_at: Date
        }
        let rows: [Row] = try await client.rpc("my_profile").execute().value
        return rows.first.map {
            Profile(displayName: $0.display_name, avatarPath: $0.avatar_path, createdAt: $0.created_at)
        }
    }

    public func saveProfile(name: String, avatarPath: String?) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProfileError.nameRequired }
        guard trimmed.count <= 50 else { throw ProfileError.nameTooLong }

        struct Params: Encodable {
            let p_name: String
            let p_avatar: String?
        }
        try await client
            .rpc("upsert_my_profile", params: Params(p_name: trimmed, p_avatar: avatarPath))
            .execute()
    }

    public func uploadAvatar(_ data: Data) async throws -> String {
        guard let uid = client.auth.currentUser?.id else { throw ProfileError.nameRequired }
        // Lowercased: storage policies compare against `auth.uid()::text`, which
        // Postgres renders lowercase, while Swift's `UUID.uuidString` is upper.
        // Uploads 403'd on exactly this once already.
        let path = "\(uid.uuidString.lowercased())/avatar.jpg"
        _ = try await client.storage
            .from(Self.bucket)
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        return path
    }

    public func avatarURL(for path: String?) async throws -> URL? {
        guard let path, !path.isEmpty else { return nil }
        // Signed, because the bucket is private — unlike `kitchen-photos`.
        // An hour outlives any reasonable time spent looking at an inbox.
        return try await client.storage.from(Self.bucket).createSignedURL(path: path, expiresIn: 3600)
    }
}

public enum ProfileError: LocalizedError, Equatable {
    case nameRequired
    case nameTooLong

    public var errorDescription: String? {
        switch self {
        case .nameRequired: "Add a name so cooks know who they're talking to."
        case .nameTooLong:  "That name is a bit long — 50 characters or fewer."
        }
    }
}
