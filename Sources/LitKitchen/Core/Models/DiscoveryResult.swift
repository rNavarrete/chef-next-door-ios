import Foundation

/// One row from `cooking_now()` or `search_cooks()`.
///
/// Both RPCs return the same shape on purpose, so the feed, the map sheet, and
/// search results all render through one component.
public struct DiscoveryResult: Codable, Sendable, Identifiable, Hashable {
    public let cookID: UUID
    public let displayName: String
    public let avatarURL: String?
    public let permitStatus: PermitStatus
    public let permitNumber: String?
    public let agencyName: String
    public let neighborhood: String
    /// Distance from the **fuzzed** public point. Never from the real address —
    /// ordering by true distance would leak it without ever returning it.
    public let distanceM: Double
    /// The grid-snapped public point. This is the only position the client
    /// ever receives; the exact address lives in a table with no client grants
    /// and comes back only from `reveal_address` after a confirmed claim.
    public let publicLat: Double
    public let publicLon: Double
    public let sessionID: UUID?
    public let openedAt: Date?
    public let lastConfirmedAt: Date?
    public let freshness: FreshnessTier?
    public let itemCount: Int
    public let headlineItems: [String]?
    /// Photo of the cheapest available dish. Cook-submitted in production; the
    /// dev seed uses keyword placeholders purely to exercise layout.
    public let headlinePhoto: String?
    public let minPriceCents: Int?
    public let minPriceUnit: PriceUnit?
    public let minPriceMinQty: Int?

    public var id: UUID { cookID }

    enum CodingKeys: String, CodingKey {
        case cookID = "cook_id"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case permitStatus = "permit_status"
        case permitNumber = "permit_number"
        case agencyName = "agency_name"
        case neighborhood
        case distanceM = "distance_m"
        case publicLat = "public_lat"
        case publicLon = "public_lon"
        case sessionID = "session_id"
        case openedAt = "opened_at"
        case lastConfirmedAt = "last_confirmed_at"
        case freshness
        case itemCount = "item_count"
        case headlineItems = "headline_items"
        case headlinePhoto = "headline_photo"
        case minPriceCents = "min_price_cents"
        case minPriceUnit = "min_price_unit"
        case minPriceMinQty = "min_price_min_qty"
    }

    public var coordinate: Coordinate {
        Coordinate(latitude: publicLat, longitude: publicLon)
    }

    /// The radius of the privacy cell, in metres. Drawn on the map as a halo so
    /// the uncertainty is *visible* — a buyer reads an area, not a house.
    public static let fuzzRadiusM: Double = 200

    public var isCooking: Bool { sessionID != nil && freshness != nil && freshness != .out }
    public var isVerified: Bool { permitStatus == .verified }

    /// Cheapest item, as a buyer will read it. `nil` when the cook has nothing
    /// available — never rendered as a bare number or a zero.
    public var startingPrice: Price? {
        guard let cents = minPriceCents, let unit = minPriceUnit else { return nil }
        return try? Price(amountCents: cents, unit: unit, minQuantity: minPriceMinQty ?? 1)
    }

    /// Absolute clock time, always — `Cooking · since 9:40 am`. Elapsed
    /// durations never appear (`DESIGN_BRIEF.md` §7a, rule 1).
    ///
    /// The `unconfirmed` case read "Lit at 5:45 pm · unconfirmed since" for
    /// months — a dangling preposition on every decayed card in the feed. The
    /// "since" was meant to point back at the lit time, which the sentence had
    /// already given; dropping it says the same thing and finishes.
    public var availabilityLabel: String {
        guard let openedAt, let freshness else { return "Light's off" }
        let clock = ServingSession.clockFormatter.string(from: openedAt).lowercased()
        switch freshness {
        case .lit, .dimming: return "Cooking · since \(clock)"
        case .unconfirmed:   return "Lit at \(clock) · unconfirmed"
        case .out:           return "Light's off"
        }
    }

    /// Just the clock part, for the card's meta line.
    ///
    /// `availabilityLabel` is a whole sentence and belongs where a sentence
    /// fits. On a card the state is already carried by the lamp dot, so all the
    /// meta line needs is *when* — "since 11:51" beside the cook and the
    /// distance, rather than a caps banner repeating what the dot said.
    public var sinceLabel: String? {
        guard let openedAt, freshness != nil, freshness != .out else { return nil }
        let clock = ServingSession.clockFormatter.string(from: openedAt).lowercased()
        return "since \(clock)"
    }

    public var distanceLabel: String {
        let miles = distanceM / 1609.34
        return miles < 0.1 ? "nearby" : String(format: "%.1f mi", miles)
    }
}
