import Foundation
import Supabase

/// The real cook-side repository.
///
/// The only `CookRepository`. M1's UI needed no changes to
/// swap over. Note what this deliberately does **not** do: it never writes
/// `serving_status`, `opened_at`, or `last_confirmed_at` as bare fields.
/// Opening, closing, and confirming all go through the SQL procedures
/// (`supabase/migrations/005`, `007`), because those enforce rules the client
/// cannot be trusted with — one open session per cook, and *which* activity
/// counts as proof a kitchen is still cooking.
@MainActor
public final class SupabaseCookRepository: CookRepository {
    private let client: SupabaseClient
    private let cookID: UUID
    /// Resolved on first use rather than passed in. A cook has exactly one
    /// kitchen today, and making the caller supply its id invited passing the
    /// wrong one — which `open_kitchen` would then reject with a confusing
    /// "not authorized".
    private var cachedKitchenID: UUID?

    public init(client: SupabaseClient = SupabaseEnvironment.shared, cookID: UUID) {
        self.client = client
        self.cookID = cookID
    }

    private func kitchenID() async throws -> UUID {
        if let cachedKitchenID { return cachedKitchenID }
        struct Row: Decodable { let id: UUID }
        let rows: [Row] = try await client
            .from("kitchens")
            .select("id")
            .eq("cook_id", value: cookID)
            .limit(1)
            .execute()
            .value
        guard let id = rows.first?.id else { throw RepositoryError.noKitchen }
        cachedKitchenID = id
        return id
    }

    // MARK: - Sessions

    public func currentSession() async throws -> ServingSession? {
        let rows: [ServingSession] = try await client
            .from("serving_sessions")
            .select()
            .eq("cook_id", value: cookID)
            .is("closed_at", value: nil)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    public func hasEverServed() async throws -> Bool {
        struct Row: Decodable { let id: UUID }
        let rows: [Row] = try await client
            .from("serving_sessions")
            .select("id")
            .eq("cook_id", value: cookID)
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    @discardableResult
    public func openKitchen(note: String?) async throws -> ServingSession {
        // open_kitchen() is idempotent server-side, so a double-tap on the
        // burner confirms the existing session instead of forking state.
        try await client
            .rpc("open_kitchen", params: OpenKitchenParams(p_kitchen: try await kitchenID(), p_note: note))
            .execute()

        guard let session = try await currentSession() else {
            throw RepositoryError.sessionNotFoundAfterOpen
        }
        return session
    }

    public func closeKitchen(reason: String) async throws {
        try await client
            .rpc("close_kitchen", params: CloseKitchenParams(p_reason: reason))
            .execute()
    }

    public func confirmServing(_ activity: CookActivity) async throws {
        // The client decides *whether* an action counts, using the same rule
        // as the server (`CookActivity.confirmsCurrentService`). The server
        // still enforces it independently for the paths it owns — this is a
        // round-trip saving, not the security boundary.
        guard activity.confirmsCurrentService else { return }
        try await client
            .rpc("confirm_session", params: ConfirmSessionParams(p_cook: cookID))
            .execute()
    }

    // MARK: - Menu

    public func menuItems() async throws -> [MenuItem] {
        try await client
            .from("menu_items")
            .select()
            .eq("cook_id", value: cookID)
            // Same order the discovery RPC uses to pick the headline dish, so
            // the top of the cook's own list is the dish buyers see first.
            // Ordering by category meant the cook could not tell which one
            // that was.
            .order("sort_order")
            .order("created_at")
            .execute()
            .value
    }

    public func save(_ item: MenuItem) async throws {
        try await client
            .from("menu_items")
            .upsert(item)
            .execute()
    }

    /// Promotes a dish to the top of the menu. Server-side renumber, because
    /// "first" is a property of the whole list, not of one row.
    public func setHeadline(_ itemID: UUID) async throws {
        struct Params: Encodable { let p_item: UUID }
        try await client.rpc("set_menu_headline", params: Params(p_item: itemID)).execute()
    }

    public func setAvailability(_ isAvailable: Bool, for itemID: UUID) async throws {
        // The menu_availability_confirms trigger bumps last_confirmed_at, so
        // no separate confirm call — flipping an item is only ever a statement
        // about today's cooking.
        try await client
            .from("menu_items")
            .update(["is_available": isAvailable])
            .eq("id", value: itemID)
            .execute()
    }

    /// Deletes a dish.
    ///
    /// No RPC and no ownership filter here on purpose: `menu_owner_write` is an
    /// ALL policy on `cook_id = auth.uid()`, so RLS already scopes this to the
    /// caller's own menu and a stray id simply deletes nothing. Adding an
    /// `.eq("cook_id", …)` would read as the security boundary while being
    /// merely a hint — the policy is the boundary.
    ///
    /// Order history is unaffected: order lines store the dish's name and price
    /// as they were at the time (044), so nothing here can rewrite what someone
    /// already ordered.
    public func delete(_ itemID: UUID) async throws {
        try await client
            .from("menu_items")
            .delete()
            .eq("id", value: itemID)
            .execute()
    }

    public enum RepositoryError: Error, CustomStringConvertible {
        case sessionNotFoundAfterOpen
        case noKitchen

        public var description: String {
            switch self {
            case .sessionNotFoundAfterOpen:
                "open_kitchen() succeeded but no open session came back. Usually means the kitchen belongs to a different cook — open_kitchen checks auth.uid() against kitchens.cook_id."
            case .noKitchen:
                "This cook has no kitchen yet. Onboarding has to create one before the burner can be turned on."
            }
        }
    }
}

// MARK: - RPC parameter types
// Named to match the SQL argument names exactly; PostgREST matches by name.

private struct OpenKitchenParams: Encodable, Sendable {
    let p_kitchen: UUID
    let p_note: String?
}

private struct CloseKitchenParams: Encodable, Sendable {
    let p_reason: String
}

private struct ConfirmSessionParams: Encodable, Sendable {
    let p_cook: UUID
}
