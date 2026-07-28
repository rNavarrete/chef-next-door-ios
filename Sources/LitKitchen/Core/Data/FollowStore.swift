import Foundation
import Supabase

public struct Follow: Codable, Sendable, Hashable {
    public let cookID: UUID
    public var notify: Bool

    public init(cookID: UUID, notify: Bool = true) {
        self.cookID = cookID
        self.notify = notify
    }

    enum CodingKeys: String, CodingKey {
        case cookID = "cook_id"
        case notify
    }
}

public protocol FollowStore: AnyObject, Sendable {
    func follows() async throws -> [Follow]
    func setFollowing(_ following: Bool, cookID: UUID) async throws
    func setNotify(_ notify: Bool, cookID: UUID) async throws
    func rows(for follows: [Follow], near: Coordinate) async throws -> [DiscoveryResult]
}

/// Device-local follows, used until Sign in with Apple lands.
///
/// Deliberately persisted rather than in-memory: follows are the one piece of
/// buyer state that must survive a relaunch, and a list that empties every
/// launch would make the Saved tab untestable and the push loop unverifiable.
///
/// **Migration note:** when auth arrives, whatever is here should be uploaded
/// once and then this store retired. Do not leave two sources of truth.
/// `@unchecked Sendable` because `UserDefaults` isn't formally Sendable, but is
/// documented as thread-safe — which is also why there's no lock here. An
/// `NSLock` would additionally be unusable: `lock()` is unavailable from async
/// contexts, and adding one would have bought nothing over the synchronisation
/// `UserDefaults` already does.
public final class LocalFollowStore: FollowStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "follows.v1"
    private let client: SupabaseClient?

    public init(defaults: UserDefaults = .standard, client: SupabaseClient? = nil) {
        self.defaults = defaults
        self.client = client
    }

    public func follows() async throws -> [Follow] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Follow].self, from: data)) ?? []
    }

    public func setFollowing(_ following: Bool, cookID: UUID) async throws {
        var current = try await follows()
        if following {
            guard !current.contains(where: { $0.cookID == cookID }) else { return }
            current.append(Follow(cookID: cookID))
        } else {
            current.removeAll { $0.cookID == cookID }
        }
        try persist(current)
    }

    public func setNotify(_ notify: Bool, cookID: UUID) async throws {
        var current = try await follows()
        guard let idx = current.firstIndex(where: { $0.cookID == cookID }) else { return }
        current[idx].notify = notify
        try persist(current)
    }

    public func rows(for follows: [Follow], near coordinate: Coordinate) async throws -> [DiscoveryResult] {
        guard !follows.isEmpty, let client else { return [] }
        return try await client
            .rpc("cooks_by_ids", params: ByIDsParams(
                ids: follows.map(\.cookID),
                lat: coordinate.latitude,
                lon: coordinate.longitude
            ))
            .execute()
            .value
    }

    private func persist(_ follows: [Follow]) throws {
        defaults.set(try JSONEncoder().encode(follows), forKey: key)
    }
}

private struct ByIDsParams: Encodable, Sendable {
    let ids: [UUID]
    let lat: Double
    let lon: Double
}
