import Foundation
import Supabase

/// A buyer's review of a completed claim.
public struct Review: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    /// Null for every review written since claims were retired
    /// (`migrations/043`) — those are left from a conversation instead, and the
    /// column only still holds a value on rows older than that.
    ///
    /// It was declared non-optional, so decoding a modern review threw, the
    /// `try?` in `CookDetailView.loadTrust` swallowed it, and the list came back
    /// empty. The average did not: it comes from the `cook_rating` RPC, which
    /// aggregates in SQL and never decodes a row. So a kitchen advertised "5.0 ·
    /// 1 review" above a section with nothing in it, and the review a buyer had
    /// taken the trouble to write was unreachable. Reported by a tester.
    ///
    /// Nothing reads this field. It is kept only because the column exists.
    public let claimID: UUID?
    public let cookID: UUID
    public let rating: Int
    public let body: String?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, rating, body
        case claimID = "claim_id"
        case cookID = "cook_id"
        case createdAt = "created_at"
    }
}

/// Count and average for a cook. Presented together, always — an average with
/// no count is the oldest trick in marketplace ratings, and "5.0" from one
/// review is not the same claim as "4.6" from ninety.
public struct CookRating: Decodable, Sendable {
    public let reviewCount: Int
    public let average: Double?

    enum CodingKeys: String, CodingKey {
        case reviewCount = "review_count"
        case average
    }

    public var isMeaningful: Bool { reviewCount > 0 }
}

/// Why someone is reporting a kitchen.
///
/// `foodSafety` and `hygiene` are the agency's business, not ours — the app
/// hands back the enforcement agency for that kitchen rather than implying we
/// will investigate (`PRD.md` §8).
public enum ComplaintKind: String, CaseIterable, Sendable {
    case foodSafety = "food_safety"
    case hygiene
    case listing
    case other

    public var label: String {
        switch self {
        case .foodSafety: "Made me or someone ill"
        case .hygiene: "Unsafe handling or conditions"
        case .listing: "Listing is wrong or misleading"
        case .other: "Something else"
        }
    }

    /// Whether this is a matter for the health department.
    public var isForAgency: Bool { self == .foodSafety || self == .hygiene }
}

public struct ReportOutcome: Decodable, Sendable {
    public let agencyName: String?
    public let isFoodSafety: Bool

    enum CodingKeys: String, CodingKey {
        case agencyName = "agency_name"
        case isFoodSafety = "is_food_safety"
    }
}

/// How current the mirrored county register is.
///
/// Surfaced to buyers rather than kept as an internal metric. The badge
/// explainer used to promise "we re-check daily", which is a claim about our
/// infrastructure; a date is a fact. If the scheduled refresh stops, the date
/// goes stale on screen and someone notices — which is the only monitoring
/// that doesn't depend on us watching.
public struct RegistryFreshness: Decodable, Sendable {
    public let syncedAt: Date?
    public let ageHours: Double?
    public let isFresh: Bool?

    enum CodingKeys: String, CodingKey {
        case syncedAt = "synced_at"
        case ageHours = "age_hours"
        case isFresh = "is_fresh"
    }
}

public struct BlockedKitchen: Sendable, Identifiable, Hashable {
    public let cookID: UUID
    public let displayName: String
    public let avatarURL: String?
    public var id: UUID { cookID }
}

/// Reviews, reports, and blocks.
///
/// Separate from `ClaimRepository` because these are about a cook, not about a
/// claim — a buyer blocks a kitchen they never claimed from, and reads reviews
/// before claiming anything at all.
@MainActor
public final class TrustRepository {
    private let client: SupabaseClient

    public init(client: SupabaseClient = SupabaseEnvironment.shared) {
        self.client = client
    }

    // MARK: - Reviews

    public func reviews(forCook cookID: UUID, limit: Int = 20) async throws -> [Review] {
        try await client
            .from("reviews")
            .select()
            .eq("cook_id", value: cookID)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    public func rating(forCook cookID: UUID) async throws -> CookRating {
        struct Params: Encodable { let p_cook: UUID }
        let rows: [CookRating] = try await client
            .rpc("cook_rating", params: Params(p_cook: cookID))
            .execute()
            .value
        return rows.first ?? CookRating(reviewCount: 0, average: nil)
    }

    /// Marks the handoff done. Either party may; the server records which
    /// (`migrations/027`).
    public func completeClaim(_ claimID: UUID) async throws {
        struct Params: Encodable { let p_claim: UUID }
        try await client.rpc("complete_claim", params: Params(p_claim: claimID)).execute()
    }

    /// Keyed on the conversation, not a claim: claiming was retired in
    /// `migrations/043` and the review policy now gates on a *pickup* recorded
    /// in the thread. `cookID` is sent but pinned server-side to the
    /// conversation's actual cook, so a genuine review cannot be aimed at a
    /// competitor.
    public func leaveReview(
        conversationID: UUID, cookID: UUID, rating: Int, body: String?
    ) async throws {
        struct Row: Encodable {
            let conversation_id: UUID
            let cook_id: UUID
            let rating: Int
            let body: String?
        }
        try await client
            .from("reviews")
            .insert(Row(
                conversation_id: conversationID, cook_id: cookID,
                rating: max(1, min(5, rating)),
                body: body?.trimmed.nilIfEmpty
            ))
            .execute()
    }

    public func registryFreshness() async -> RegistryFreshness? {
        let rows: [RegistryFreshness]? = try? await client
            .rpc("permit_registry_freshness")
            .execute()
            .value
        return rows?.first
    }

    // MARK: - Report

    @discardableResult
    public func report(
        cookID: UUID, kind: ComplaintKind, body: String?, claimID: UUID? = nil
    ) async throws -> ReportOutcome {
        struct Params: Encodable {
            let p_cook: UUID
            let p_kind: String
            let p_body: String?
            let p_claim: UUID?
        }
        let rows: [ReportOutcome] = try await client
            .rpc("report_cook", params: Params(
                p_cook: cookID, p_kind: kind.rawValue,
                p_body: body?.trimmed.nilIfEmpty, p_claim: claimID
            ))
            .execute()
            .value
        return rows.first ?? ReportOutcome(agencyName: nil, isFoodSafety: kind.isForAgency)
    }

    // MARK: - Block

    public func isBlocked(cookID: UUID) async -> Bool {
        struct Row: Decodable { let cook_id: UUID }
        let rows: [Row]? = try? await client
            .from("blocked_cooks")
            .select("cook_id")
            .eq("cook_id", value: cookID)
            .limit(1)
            .execute()
            .value
        return rows?.isEmpty == false
    }

    /// The kitchens this buyer has blocked.
    ///
    /// Reads `cooks` directly rather than the discovery RPC — `cooking_now`
    /// filters blocked cooks out, which is the whole point of it, so asking it
    /// for them would always return nothing. Name and id is all an unblock list
    /// needs.
    public func blockedKitchens() async throws -> [BlockedKitchen] {
        struct Row: Decodable {
            struct Cook: Decodable { let display_name: String; let avatar_url: String? }
            let cook_id: UUID
            let cooks: Cook?
        }
        let rows: [Row] = try await client
            .from("blocked_cooks")
            .select("cook_id, cooks(display_name, avatar_url)")
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map {
            BlockedKitchen(
                cookID: $0.cook_id,
                displayName: $0.cooks?.display_name ?? "This kitchen",
                avatarURL: $0.cooks?.avatar_url
            )
        }
    }

    public func block(cookID: UUID) async throws {
        struct Row: Encodable { let blocker_id: UUID; let cook_id: UUID }
        let userID = try await client.auth.session.user.id
        try await client
            .from("blocked_cooks")
            .insert(Row(blocker_id: userID, cook_id: cookID))
            .execute()
    }

    public func unblock(cookID: UUID) async throws {
        try await client
            .from("blocked_cooks")
            .delete()
            .eq("cook_id", value: cookID)
            .execute()
    }
}
