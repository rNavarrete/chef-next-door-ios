import Foundation

/// Which permit path a dish falls under. Drives disclosure copy and
/// verification, not just categorisation (`PRD.md` §3).
public enum FoodCategoryType: String, Codable, Sendable, CaseIterable {
    /// Hot, cooked-to-order. MEHKO permit, same-day service only.
    case mehkoMeal = "mehko_meal"
    /// Shelf-stable. Cottage food registration, lighter path.
    case cottageFood = "cottage_food"

    /// Required on every advertising surface for MEHKO items. Rendered from
    /// the category and the cook's agency — never left to the cook to
    /// remember, and never omitted.
    public var requiresHomeKitchenDisclosure: Bool { self == .mehkoMeal }
}

public struct MenuItem: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: UUID
    public let cookID: UUID
    /// At least one of `nameEN` / `nameES` is non-nil — enforced by a CHECK
    /// constraint server-side. Titles in this market mix languages mid-string
    /// (`RESEARCH.md` Finding 4), so both are first-class, not
    /// original-plus-translation.
    public let nameEN: String?
    public let nameES: String?
    public let description: String?
    public let category: String
    public let categoryType: FoodCategoryType
    /// Mandatory, dish-level, always visible. A safety surface, not
    /// decoration — no tooltip, no accordion (`PRD.md` §7).
    public let allergens: [String]
    public let isAvailable: Bool
    public let price: Price
    /// The cook's own photos of the dish, up to four. The first is the
    /// headline — it drives the feed thumbnail, the map pin and the card.
    ///
    /// Write this, not ``photoURL``. Since migration 057 the server derives
    /// `photo_url` from `photos[1]` with a trigger, so setting the singular
    /// column is at best redundant and at worst immediately overwritten.
    public let photos: [String]

    /// The headline photo, as the server stores it. **Derived** — kept because
    /// `cooking_now`, `search_cooks` and `cooks_by_ids` all read it.
    public let photoURL: String?
    /// Cook-controlled position. The first item is the headline dish, whose
    /// name *and* photo carry the feed card. `0` means "unset" — the server
    /// appends new dishes to the end (`migrations/026`), so the client never
    /// has to know what else is on the menu to insert correctly.
    public let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case cookID = "cook_id"
        case nameEN = "name_en"
        case nameES = "name_es"
        case description
        case category
        case categoryType = "category_type"
        case allergens
        case isAvailable = "is_available"
        case amountCents = "amount_cents"
        case unit
        case minQuantity = "min_quantity"
        case photos
        case photoURL = "photo_url"
        case sortOrder = "sort_order"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        cookID = try c.decode(UUID.self, forKey: .cookID)
        nameEN = try c.decodeIfPresent(String.self, forKey: .nameEN)
        nameES = try c.decodeIfPresent(String.self, forKey: .nameES)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        category = try c.decode(String.self, forKey: .category)
        categoryType = try c.decode(FoodCategoryType.self, forKey: .categoryType)
        allergens = try c.decodeIfPresent([String].self, forKey: .allergens) ?? []
        isAvailable = try c.decode(Bool.self, forKey: .isAvailable)
        // Falls back to the singular column so a row written before 057 —
        // or by anything that still only knows about `photo_url` — still
        // renders its one photo instead of none.
        let decodedPhotos = try c.decodeIfPresent([String].self, forKey: .photos) ?? []
        let decodedHeadline = try c.decodeIfPresent(String.self, forKey: .photoURL)
        photos = decodedPhotos.isEmpty ? [decodedHeadline].compactMap { $0 } : decodedPhotos
        photoURL = decodedHeadline ?? decodedPhotos.first
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0

        // Price is validated on decode. A malformed row fails loudly here
        // rather than rendering as a bare or nonsensical amount downstream.
        price = try Price(
            amountCents: try c.decode(Int.self, forKey: .amountCents),
            unit: try c.decode(PriceUnit.self, forKey: .unit),
            minQuantity: try c.decodeIfPresent(Int.self, forKey: .minQuantity) ?? 1
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(cookID, forKey: .cookID)
        try c.encodeIfPresent(nameEN, forKey: .nameEN)
        try c.encodeIfPresent(nameES, forKey: .nameES)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(category, forKey: .category)
        try c.encode(categoryType, forKey: .categoryType)
        try c.encode(allergens, forKey: .allergens)
        try c.encode(isAvailable, forKey: .isAvailable)
        try c.encode(price.amountCents, forKey: .amountCents)
        try c.encode(price.unit, forKey: .unit)
        try c.encode(price.minQuantity, forKey: .minQuantity)
        // `photos` only. Encoding `photo_url` as well would race the 057
        // trigger, which recomputes it from `photos[1]` on every write.
        try c.encode(photos, forKey: .photos)
        try c.encode(sortOrder, forKey: .sortOrder)
    }

    /// Memberwise init for tests and previews.
    public init(
        id: UUID = UUID(),
        cookID: UUID,
        nameEN: String? = nil,
        nameES: String? = nil,
        description: String? = nil,
        category: String,
        categoryType: FoodCategoryType,
        allergens: [String] = [],
        isAvailable: Bool = true,
        price: Price,
        photos: [String] = [],
        photoURL: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.cookID = cookID
        self.nameEN = nameEN
        self.nameES = nameES
        self.description = description
        self.category = category
        self.categoryType = categoryType
        self.allergens = allergens
        self.isAvailable = isAvailable
        self.price = price
        // Same reconciliation as `init(from:)`, so a value built in code and
        // one decoded from the server can never disagree about which photo is
        // the headline.
        self.photos = photos.isEmpty ? [photoURL].compactMap { $0 } : photos
        self.photoURL = photoURL ?? photos.first
        self.sortOrder = sortOrder
    }

    /// Preferred display name for the given locale, falling back to whichever
    /// name exists. Never returns empty — the CHECK constraint guarantees one.
    public func displayName(preferring language: String = Locale.current.language.languageCode?.identifier ?? "en") -> String {
        let preferred = language.hasPrefix("es") ? nameES : nameEN
        return preferred ?? nameES ?? nameEN ?? category
    }
}
