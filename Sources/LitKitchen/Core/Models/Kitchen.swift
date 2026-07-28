import CoreLocation
import Foundation

public struct Coordinate: Codable, Sendable, Equatable, Hashable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// A kitchen, as any client is ever allowed to see one.
///
/// **There is deliberately no `exactPoint` on this type, and there must never
/// be one.** Exact coordinates live in `kitchen_locations`, a table no client
/// role holds any grant on; the only path to them is the `reveal_address` RPC,
/// which decodes into ``RevealedAddress`` and only after the *cook* confirms a
/// specific claim (`IMPLEMENTATION_PLAN.md` §2.004, §2.009).
///
/// Omitting the field here is the last line of defense: even if a policy is
/// later written wrong, a UI mistake cannot leak a coordinate that was never
/// decoded into the model.
public struct Kitchen: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: UUID
    public let cookID: UUID
    /// Grid-snapped, non-invertible. ~500m cell. Safe to plot.
    public let publicPoint: Coordinate
    public let neighborhood: String
    public let city: String
    public let agencyID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case cookID = "cook_id"
        case publicPoint = "public_point"
        case neighborhood
        case city
        case agencyID = "agency_id"
    }
}

/// The result of a successful `reveal_address` call.
///
/// Constructed only from that RPC. Every instance corresponds to a row in
/// `address_disclosures` — if one of these exists, the disclosure was logged.
/// Treat as sensitive: do not persist to disk, do not include in analytics,
/// do not put in a log line.
public struct RevealedAddress: Codable, Sendable, Equatable {
    public let street: String
    public let city: String
    public let postalCode: String
    /// Plain doubles, not a `geography`. PostgREST serialises geography as a
    /// WKB hex string, which silently failed to decode into a coordinate — and
    /// failed at the worst moment, with the buyer waiting on the address.
    public let latitude: Double
    public let longitude: Double

    enum CodingKeys: String, CodingKey {
        case street
        case city
        case postalCode = "postal_code"
        case latitude
        case longitude
    }

    public var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    public var singleLine: String { "\(street), \(city) \(postalCode)" }
}
