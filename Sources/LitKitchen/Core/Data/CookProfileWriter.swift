import Foundation
import Supabase

/// Writes the parts of a cook's own row that they control.
///
/// Separate from `CookRepository`, which is about *service* — opening a
/// kitchen, the menu, availability. This is about identity, and the two have
/// different lifetimes: a cook edits their story once and their menu daily.
///
/// A plain table UPDATE rather than an RPC, because migration 032 already made
/// this safe at the grant level: `authenticated` holds UPDATE on exactly the
/// columns a cook owns, and RLS restricts it to their own row. `permit_status`
/// and friends are unreachable from here no matter what this code sends.
public struct CookProfileWriter: Sendable {
    private let client: SupabaseClient

    public init(client: SupabaseClient = SupabaseEnvironment.shared) {
        self.client = client
    }

    private struct StoryPatch: Encodable, Sendable {
        let bio: String?
    }

    /// Sets — or clears, with an empty string — the kitchen's cover photo.
    ///
    /// Through the RPC rather than a table PATCH, mirroring `set_cook_avatar`:
    /// the column grant would allow a direct write, but keeping every
    /// cook-photo write on one path is worth more than the round trip saved.
    public func setCover(_ url: String?) async throws {
        struct Params: Encodable, Sendable { let p_url: String }
        try await client
            .rpc("set_kitchen_cover", params: Params(p_url: url ?? ""))
            .execute()
    }

    /// Sets — or clears, with nil — the cook's story.
    public func setStory(_ story: String?, for cookID: UUID) async throws {
        try await client
            .from("cooks")
            .update(StoryPatch(bio: story))
            .eq("id", value: cookID)
            .execute()
    }
}
