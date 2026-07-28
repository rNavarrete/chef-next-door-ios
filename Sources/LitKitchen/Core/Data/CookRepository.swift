import Foundation

/// Everything the cook-side surfaces need from storage.
///
/// Protocol-backed so M1 could be built before the Supabase project existed.
/// The in-memory double that served that purpose is gone — `RootView` stopped
/// using it once the cook side moved to `SupabaseCookRepository`, and it sat
/// unreferenced afterwards along with the value-type helpers written only for
/// it. `openKitchen`/`closeKitchen` map directly onto the SQL procedures of
/// the same name, and nothing here writes
/// `serving_status` as a bare field, because sessions are opened and closed
/// atomically server-side (`supabase/migrations/005`).
@MainActor
public protocol CookRepository: AnyObject {
    func currentSession() async throws -> ServingSession?
    /// Whether this kitchen has ever served, open or closed.
    ///
    /// Distinct from `currentSession() != nil`, which is only ever true while
    /// a session is open — a cook who closed up last night is not a new cook,
    /// and telling them "your kitchen is ready, add what you make" over an
    /// established menu reads as though the app has forgotten them.
    func hasEverServed() async throws -> Bool
    @discardableResult func openKitchen(note: String?) async throws -> ServingSession
    func closeKitchen(reason: String) async throws
    /// Bumps `last_confirmed_at` — only for activity that asserts current
    /// service. See ``CookActivity``.
    func confirmServing(_ activity: CookActivity) async throws

    func menuItems() async throws -> [MenuItem]
    func save(_ item: MenuItem) async throws
    func setAvailability(_ isAvailable: Bool, for itemID: UUID) async throws
    /// Makes this dish the one the feed card shows.
    func setHeadline(_ itemID: UUID) async throws
    /// Removes a dish for good. Distinct from `setAvailability(false,…)`, which
    /// is "not today" — a cook who has stopped making something entirely
    /// otherwise carries it on their menu forever.
    func delete(_ itemID: UUID) async throws
}
