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
    /// Dish names resolved English-first (`name_en ?? name_es`). Read through
    /// `localizedHeadlineItems`, never directly — see that property.
    public let headlineItems: [String]?
    /// The same list resolved Spanish-first (`name_es ?? name_en`). Same order,
    /// same length.
    public let headlineItemsES: [String]?
    /// Photo of the cheapest available dish. Cook-submitted in production; the
    /// dev seed uses keyword placeholders purely to exercise layout.
    public let headlinePhoto: String?
    public let minPriceCents: Int?
    public let minPriceUnit: PriceUnit?
    public let minPriceMinQty: Int?
    /// Average of this cook's reviews, or nil if nobody has reviewed them.
    ///
    /// Nil rather than 0. Zero is a rating; "nobody has said anything yet" is
    /// not, and every cook starts in the second state. Rendering a new cook as
    /// 0.0 stars would be the app inventing an opinion nobody held.
    public let rating: Double?
    /// How many reviews that average is built from. Travels with `rating`
    /// because the average alone is not usable — one five-star review would
    /// otherwise outrank forty averaging 4.8.
    public let ratingCount: Int?

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
        case headlineItemsES = "headline_items_es"
        case headlinePhoto = "headline_photo"
        case minPriceCents = "min_price_cents"
        case minPriceUnit = "min_price_unit"
        case minPriceMinQty = "min_price_min_qty"
        case rating
        case ratingCount = "rating_count"
    }

    public var coordinate: Coordinate {
        Coordinate(latitude: publicLat, longitude: publicLon)
    }

    /// The radius of the privacy cell, in metres. Drawn on the map as a halo so
    /// the uncertainty is *visible* — a buyer reads an area, not a house.
    public static let fuzzRadiusM: Double = 200

    /// The dish names in the reader's language. **Every surface must use this**
    /// rather than `headlineItems`.
    ///
    /// The server sends both resolutions because it cannot know the reader's
    /// locale (061). Before that it sent one list built with
    /// `coalesce(name_es, name_en)` — Spanish for everybody — while the dish
    /// page used `MenuItem.displayName`, which picks by locale. The same dish
    /// therefore carried two different names one tap apart: "Stuffed poblano"
    /// on the feed card, "Chile relleno" on its own page.
    ///
    /// The fallback chain covers a client that outlives its server: if the
    /// preferred array is missing, either other list still names the dish.
    public var localizedHeadlineItems: [String]? {
        let wantsSpanish = Locale.current.language.languageCode?.identifier.hasPrefix("es") ?? false
        let preferred = wantsSpanish ? headlineItemsES : headlineItems
        return preferred ?? headlineItems ?? headlineItemsES
    }

    public var isCooking: Bool { sessionID != nil && freshness != nil && freshness != .out }
    public var isVerified: Bool { permitStatus == .verified }

    /// Enough reviews for the average to mean something.
    ///
    /// Three is a low bar and deliberately so — it is the difference between
    /// "one person liked this" and "a few people agree", which is the smallest
    /// honest claim a rating can make. Below it the number is shown but never
    /// filtered or ranked on.
    public static let minimumReviewsToRank = 3

    public var hasMeaningfulRating: Bool {
        (ratingCount ?? 0) >= Self.minimumReviewsToRank && rating != nil
    }

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
        guard let openedAt, let freshness else { return "Closed" }
        let clock = ServingSession.clockFormatter.string(from: openedAt).lowercased()
        switch freshness {
        case .lit, .dimming: return "Cooking · since \(clock)"
        case .unconfirmed:   return "Open since \(clock) · not confirmed recently"
        case .out:           return "Closed"
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
        Self.label(forMetres: distanceM)
    }

    /// Distance from a point other than the one the server measured from.
    ///
    /// The map re-queries around wherever it has been dragged, so `distanceM`
    /// arrives measured from the *map's* centre. Rendering that unchanged makes
    /// "0.8 mi" mean "from the middle of your screen", which is a quiet lie the
    /// moment somebody pans to another city — every pin in San Diego would read
    /// as walking distance. Measured from the browsing origin instead, so the
    /// number always answers "how far is this from me".
    public func distanceLabel(from origin: Coordinate) -> String {
        let earthRadius = 6_371_000.0
        let dLat = (publicLat - origin.latitude) * .pi / 180
        let dLon = (publicLon - origin.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(origin.latitude * .pi / 180) * cos(publicLat * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        return Self.label(forMetres: earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a)))
    }

    private static func label(forMetres metres: Double) -> String {
        let miles = metres / 1609.34
        return miles < 0.1 ? "nearby" : String(format: "%.1f mi", miles)
    }
}
