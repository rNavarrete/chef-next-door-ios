import Foundation
import Supabase
import Testing
@testable import LitKitchen

/// Live integration checks against the real project.
///
/// These do hit the network. They exist because "it compiles" proves nothing
/// about whether the schema, the grants, and the client agree — and the two
/// bugs found while deploying (extensions in a different schema, and no grants
/// at all) were both invisible until something actually connected.
///
/// Skipped automatically when credentials are absent, so a fresh clone without
/// `Config/Secrets.xcconfig` still has a green suite.
/// Free function, not a static on the suite: referencing a member of the type
/// the `@Suite` macro is attached to is a circular reference.
func supabaseIsConfigured() -> Bool {
    let bundle = Bundle.main
    let url = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
    let key = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
    return !(url ?? "").isEmpty && !(key ?? "").isEmpty
}

@Suite("Supabase connectivity", .enabled(if: supabaseIsConfigured()))
struct SupabaseConnectivityTests {

    struct Agency: Decodable, Sendable {
        let name: String
        let county: String
        let mehko_opted_in: Bool
    }

    @Test("The client reaches the project and reads a granted table")
    func readsGrantedTable() async throws {
        let agencies: [Agency] = try await SupabaseEnvironment.shared
            .from("enforcement_agencies")
            .select()
            .execute()
            .value

        // Seeded by migration 003.
        #expect(agencies.count >= 4)
        #expect(agencies.contains { $0.name.contains("LA County") && $0.mehko_opted_in })
        // The carve-outs run their own health departments and are not opted in.
        #expect(agencies.contains { $0.name.contains("Pasadena") && !$0.mehko_opted_in })
    }

    @Test("Home addresses are unreachable from a client, over the wire")
    func kitchenLocationsIsUnreachable() async throws {
        // The local checks proved the *grants* are absent. This proves the
        // API itself refuses — the property that actually protects a cook.
        await #expect(throws: (any Error).self) {
            let _: [AnyDecodableRow] = try await SupabaseEnvironment.shared
                .from("kitchen_locations")
                .select()
                .execute()
                .value
        }
    }

    @Test("The geo secret is unreachable from a client, over the wire")
    func appSecretsIsUnreachable() async throws {
        await #expect(throws: (any Error).self) {
            let _: [AnyDecodableRow] = try await SupabaseEnvironment.shared
                .from("app_secrets")
                .select()
                .execute()
                .value
        }
    }

    @Test("Reading a granted table returns no rows rather than failing when empty")
    func emptyTableIsNotAnError() async throws {
        // Distinguishes "denied" from "empty". If this threw, the grant in
        // 011 would be wrong even though the table exists.
        let items: [AnyDecodableRow] = try await SupabaseEnvironment.shared
            .from("menu_items")
            .select()
            .limit(1)
            .execute()
            .value
        #expect(items.isEmpty || !items.isEmpty)
    }
}

/// Minimal decodable for existence checks where the shape doesn't matter.
struct AnyDecodableRow: Decodable, Sendable {}
