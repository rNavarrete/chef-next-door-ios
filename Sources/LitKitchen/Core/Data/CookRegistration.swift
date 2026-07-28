import CoreLocation
import Foundation
import Supabase

/// Everything needed to bring a kitchen into existence.
///
/// Kept as one value rather than eleven arguments because the whole thing is
/// submitted in a single `register_cook` call — there is no valid partial
/// registration, and modelling it as one payload makes that hard to forget.
public struct CookRegistration: Sendable {
    public var displayName: String = ""
    public var contactMethod: ContactMethod = .sms
    public var contactValue: String = ""

    public var street: String = ""
    public var city: String = ""
    public var postalCode: String = ""
    public var neighborhood: String = ""

    /// Optional. A cook may be setting up before their permit comes through,
    /// and blocking that would mean the only people who can build a menu are
    /// the ones who least need the lead time.
    public var permitKind: PermitKind?
    public var permitNumber: String = ""
    /// Chosen explicitly rather than inferred from an empty field. "I'm still
    /// applying" and "I skipped this question" are different states, and only
    /// one of them means the cook expects a badge later.
    public var permitStage: PermitStage = .unset

    public init() {}

    /// Enough to submit. Deliberately does **not** require a permit — the
    /// server decides what a missing permit means for `permit_status`.
    public var isComplete: Bool {
        !displayName.trimmed.isEmpty
            && !contactValue.trimmed.isEmpty
            && !street.trimmed.isEmpty
            && !city.trimmed.isEmpty
            && !postalCode.trimmed.isEmpty
    }
}

public extension ContactMethod {
    var label: String {
        switch self {
        case .sms: "Text"
        case .whatsapp: "WhatsApp"
        case .instagram: "Instagram"
        }
    }

    var placeholder: String {
        switch self {
        case .sms, .whatsapp: "(626) 555-0142"
        case .instagram: "@yourkitchen"
        }
    }
}

/// The permits this market actually runs on. Names are the cook's words, not
/// the statute's — a MEHKO permit holder does not call it "AB 626".
public enum PermitKind: String, CaseIterable, Sendable {
    case mehko = "mehko"
    case cfoClassA = "cfo_class_a"
    case cfoClassB = "cfo_class_b"
    case foodHandler = "food_handler"

    public var label: String {
        switch self {
        case .mehko: "MEHKO — home restaurant"
        case .cfoClassA: "Cottage food, Class A"
        case .cfoClassB: "Cottage food, Class B"
        case .foodHandler: "Food handler card only"
        }
    }

    /// Whether this permit covers hot meals. Cottage food does not, and a cook
    /// choosing it should find that out here rather than from an inspector.
    public var allowsMeals: Bool { self == .mehko }
}

/// Where a cook is with their permit, in their own terms.
///
/// None of these gate listing. A cook mid-application can build a menu and turn
/// their light on — the badge is the thing that waits, not the account.
public enum PermitStage: String, CaseIterable, Sendable {
    case unset
    /// Has a number to check right now.
    case have
    /// Applied, waiting on the county. The common case for anyone new.
    case applying
    /// Baked goods under cottage food, or simply not answering today.
    case later

    public var label: String {
        switch self {
        case .unset: ""
        case .have: "I have my permit number"
        case .applying: "I've applied — still waiting"
        case .later: "I'll sort this out later"
        }
    }
}

/// The result of checking a permit number against the county register.
///
/// Named for what each case *actually establishes*. `verified` means a permit
/// with that number exists at this city and ZIP and nobody else here has
/// claimed it — not that this person holds it (`migrations/030`).
public enum PermitCheck: String, Decodable, Sendable {
    case verified
    /// Not on the county list. Could be fraud; could equally be a permit
    /// issued last week that hasn't been published yet.
    case notFound = "not_found"
    /// Real permit, but registered to a different part of the county.
    case wrongArea = "wrong_area"
    case alreadyClaimed = "already_claimed"
    /// This city runs its own health department and isn't in the county
    /// register at all — we cannot check, which is not the same as a failure.
    case agencyNotCovered = "agency_not_covered"

    public var isVerified: Bool { self == .verified }
}

public struct PermitCheckResult: Decodable, Sendable {
    public let outcome: PermitCheck
    /// The name the county has on file. Shown back to the cook as a
    /// "is this you?" signal — a mistyped digit that happens to hit another
    /// real permit is otherwise invisible.
    public let registeredName: String?
    public let agencyName: String?

    enum CodingKeys: String, CodingKey {
        case outcome
        case registeredName = "registered_name"
        case agencyName = "agency_name"
    }
}

/// What a city's enforcement agency allows. Read before the cook commits to
/// anything, because in LA County MEHKO is opt-in *per agency* — three cities
/// run their own health departments and have not opted in.
public struct AgencyRules: Decodable, Sendable {
    public let id: UUID
    public let name: String
    public let mehkoOptedIn: Bool
    public let cottageFoodOK: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case mehkoOptedIn = "mehko_opted_in"
        case cottageFoodOK = "cottage_food_ok"
    }
}

public enum RegistrationError: LocalizedError {
    case geocodingFailed
    case alreadyRegistered
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .geocodingFailed:
            "We couldn't find that address. Check the street and ZIP."
        case .alreadyRegistered:
            "This account already has a kitchen."
        case .server(let message):
            message
        }
    }
}

/// Creates a cook, their kitchen, and its location.
///
/// Every write here goes through one RPC. That isn't tidiness: `cooks` has no
/// INSERT grant, `kitchen_locations` has no grants at all, and the fuzzing
/// function is revoked from `authenticated` — so a client-side version of this
/// would have required loosening all three (`migrations/023`).
@MainActor
public final class CookRegistrationService {
    private let client: SupabaseClient
    private let geocoder = CLGeocoder()

    public init(client: SupabaseClient = SupabaseEnvironment.shared) {
        self.client = client
    }

    /// What applies where this cook lives. Cheap and non-committal — called as
    /// soon as there's a city to ask about.
    public func rules(forCity city: String) async -> AgencyRules? {
        struct Params: Encodable { let p_city: String }
        let rows: [AgencyRules]? = try? await client
            .rpc("agency_for_address", params: Params(p_city: city))
            .execute()
            .value
        return rows?.first
    }

    /// Street address → coordinates, on the device.
    ///
    /// The cook's own address, geocoded by their own phone, and the exact point
    /// goes straight into `kitchen_locations` where no client can read it back.
    /// Sending the address to a geocoding service we run would put it in a
    /// second place we'd then have to defend.
    public func coordinate(for registration: CookRegistration) async throws -> CLLocationCoordinate2D {
        let address = [
            registration.street.trimmed,
            registration.city.trimmed,
            "CA",
            registration.postalCode.trimmed,
        ].joined(separator: ", ")

        let placemarks = try? await geocoder.geocodeAddressString(address)
        guard let coordinate = placemarks?.first?.location?.coordinate else {
            throw RegistrationError.geocodingFailed
        }
        return coordinate
    }

    /// Checks a permit number against the mirrored county register.
    ///
    /// Runs after registration, because it reads the kitchen's city and ZIP to
    /// corroborate — there's nothing to compare against until the kitchen
    /// exists.
    public func checkPermit(_ number: String) async -> PermitCheckResult? {
        struct Params: Encodable { let p_number: String }
        let rows: [PermitCheckResult]? = try? await client
            .rpc("verify_permit", params: Params(p_number: number))
            .execute()
            .value
        return rows?.first
    }

    @discardableResult
    public func register(
        _ registration: CookRegistration,
        at coordinate: CLLocationCoordinate2D
    ) async throws -> UUID {
        struct Params: Encodable {
            let p_display_name: String
            let p_contact_method: String
            let p_contact_value: String
            let p_street: String
            let p_city: String
            let p_postal_code: String
            let p_latitude: Double
            let p_longitude: Double
            let p_neighborhood: String?
            let p_permit_kind: String?
            let p_permit_number: String?
        }

        do {
            let kitchenID: UUID = try await client
                .rpc("register_cook", params: Params(
                    p_display_name: registration.displayName.trimmed,
                    p_contact_method: registration.contactMethod.rawValue,
                    p_contact_value: registration.contactValue.trimmed,
                    p_street: registration.street.trimmed,
                    p_city: registration.city.trimmed,
                    p_postal_code: registration.postalCode.trimmed,
                    p_latitude: coordinate.latitude,
                    p_longitude: coordinate.longitude,
                    p_neighborhood: registration.neighborhood.trimmed.nilIfEmpty,
                    p_permit_kind: registration.permitKind?.rawValue,
                    p_permit_number: registration.permitNumber.trimmed.nilIfEmpty
                ))
                .execute()
                .value
            return kitchenID
        } catch {
            let text = String(describing: error)
            if text.contains("already registered") { throw RegistrationError.alreadyRegistered }
            throw RegistrationError.server(
                "Couldn't set up your kitchen. \(text.contains("address") ? "Check the address." : "Try again in a moment.")"
            )
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
