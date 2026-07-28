import Foundation
import Supabase

/// Deliberately **not** `@MainActor`. Discovery is read-only network I/O with
/// no shared mutable state, so pinning it to the main actor buys nothing and
/// costs real concurrency — `async let` cannot run two calls in parallel when
/// the receiver can't cross an isolation boundary. Search issues the results
/// query and the synonym expansion together, so that matters.
public protocol DiscoveryRepository: AnyObject, Sendable {
    func cookingNow(near: Coordinate, radiusM: Int, includeClosed: Bool) async throws -> [DiscoveryResult]
    func search(_ query: String, near: Coordinate, radiusM: Int) async throws -> [DiscoveryResult]
    /// The synonym terms a query expanded to, so the UI can show buyers *why*
    /// a result matched: "también: tamales · tamalito · pork tamale".
    func expansion(for query: String) async throws -> [String]
    /// A cook's full menu, in their own order. Sold-out items are included —
    /// the detail screen shows them dimmed rather than hiding them, because
    /// "they had it and it went" is useful information.
    func menu(for cookID: UUID) async throws -> [MenuItem]
    /// The cook's own row — their story, their serving note, their handle.
    ///
    /// `DiscoveryResult` is a *discovery* row: it carries what the feed needs
    /// to rank and render a card, and deliberately not the cook's whole
    /// profile. The detail screen needs the rest, and until now simply did
    /// without — which is why its "What they said" was a hardcoded sentence
    /// and `cooks.bio` had no way to reach a screen.
    func cook(_ cookID: UUID) async throws -> Cook?
}

public final class SupabaseDiscoveryRepository: DiscoveryRepository {
    private let client: SupabaseClient

    public init(client: SupabaseClient = SupabaseEnvironment.shared) {
        self.client = client
    }

    public func cookingNow(
        near coordinate: Coordinate,
        radiusM: Int = 8000,
        includeClosed: Bool = false
    ) async throws -> [DiscoveryResult] {
        try await client
            .rpc("cooking_now", params: NearbyParams(
                lat: coordinate.latitude, lon: coordinate.longitude,
                radius_m: radiusM, include_closed: includeClosed
            ))
            .execute()
            .value
    }

    public func search(
        _ query: String,
        near coordinate: Coordinate,
        radiusM: Int = 8000
    ) async throws -> [DiscoveryResult] {
        try await client
            .rpc("search_cooks", params: SearchParams(
                q: query, lat: coordinate.latitude, lon: coordinate.longitude,
                radius_m: radiusM, include_closed: true
            ))
            .execute()
            .value
    }

    public func expansion(for query: String) async throws -> [String] {
        try await client
            .rpc("expand_query", params: ExpandParams(q: query))
            .execute()
            .value
    }

    public func menu(for cookID: UUID) async throws -> [MenuItem] {
        try await client
            .from("menu_items")
            .select()
            .eq("cook_id", value: cookID)
            .order("sort_order")
            .execute()
            .value
    }

    public func cook(_ cookID: UUID) async throws -> Cook? {
        // Columns enumerated on purpose. `select()` sends `*`, and Postgres
        // rejects the **entire statement** if any selected column is one the
        // role cannot read — it does not quietly drop them. Migration 055
        // withheld `contact_value`, `contact_method` and `phone_verified`, so
        // `*` here returns 403 and the caller sees "no cook" rather than a
        // permissions error. This list must stay in step with 055's grant.
        let rows: [Cook] = try await client
            .from("cooks")
            .select("""
                id, display_name, bio, cover_url, avatar_path, instagram, permit_status, \
                permit_number, permit_agency_id, permit_expires, serving_status, \
                serving_note
                """)
            .eq("id", value: cookID)
            .limit(1)
            .execute()
            .value
        return rows.first
    }
}

private struct NearbyParams: Encodable, Sendable {
    let lat: Double, lon: Double, radius_m: Int, include_closed: Bool
}
private struct SearchParams: Encodable, Sendable {
    let q: String, lat: Double, lon: Double, radius_m: Int, include_closed: Bool
}
private struct ExpandParams: Encodable, Sendable {
    let q: String
}

/// Development double, seeded with the same dishes as the SQL fixtures so the
/// UI can be built and previewed without a network.
public final class InMemoryDiscoveryRepository: DiscoveryRepository {
    private let rows: [DiscoveryResult]
    public init(rows: [DiscoveryResult] = DiscoveryResult.samples) { self.rows = rows }

    public func cook(_ cookID: UUID) async throws -> Cook? { nil }

    public func cookingNow(near: Coordinate, radiusM: Int, includeClosed: Bool) async throws -> [DiscoveryResult] {
        rows.filter { includeClosed || $0.isCooking }
            .sorted { ($0.freshness?.rankOrder ?? 3, $0.distanceM) < ($1.freshness?.rankOrder ?? 3, $1.distanceM) }
    }

    public func search(_ query: String, near: Coordinate, radiusM: Int) async throws -> [DiscoveryResult] {
        let q = query.lowercased()
        return rows.filter { row in
            row.displayName.lowercased().contains(q)
                || (row.headlineItems ?? []).contains { $0.lowercased().contains(q) }
        }
    }

    public func expansion(for query: String) async throws -> [String] { [] }
    public func menu(for cookID: UUID) async throws -> [MenuItem] { MenuItem.samples }
}
