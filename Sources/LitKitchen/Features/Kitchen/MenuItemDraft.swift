import Foundation
import Observation

/// The in-progress state of the menu builder.
///
/// Its job is to make an ambiguous price **unsaveable**. `MenuItem` already
/// refuses to hold one, but a form needs somewhere to keep half-typed input,
/// and that's exactly where the constraint usually leaks back in. So the draft
/// carries raw text and can only produce a `MenuItem` when it is complete.
@Observable
@MainActor
public final class MenuItemDraft {
    public var nameEN: String = ""
    public var nameES: String = ""
    public var description: String = ""
    public var category: String = ""
    public var categoryType: FoodCategoryType = .mehkoMeal

    /// Raw text, because "3." and "" are states a user passes through.
    public var amountText: String = ""
    public var unit: PriceUnit = .each
    public var minQuantityText: String = "1"

    public var allergens: Set<String> = []

    /// Public URLs of already-uploaded photos, in display order. Optional —
    /// a cook without a good photo to hand should still be able to list the
    /// dish, and an empty menu helps nobody.
    ///
    /// The first is the headline: it carries the feed card, the map pin and
    /// the search result. Reordering here changes which one that is, which is
    /// the only way a cook can choose it.
    public var photos: [String] = []

    /// How many a cook may attach. Matches the `menu_items_photos_max` CHECK
    /// in migration 057 — the client should refuse before the server has to.
    public static let maxPhotos = 4

    public var canAddPhoto: Bool { photos.count < Self.maxPhotos }

    public static let commonAllergens = ["Pork", "Corn", "Dairy", "Gluten", "Nuts", "Egg", "Soy", "Shellfish"]

    public init() {}

    /// Loads an existing dish for editing.
    ///
    /// Keeping the id is the whole point — `save` upserts, so an edit updates
    /// the row instead of adding a second dish with the same name. Without an
    /// edit path a cook could never attach a photo to a dish they had already
    /// created, which is most dishes.
    public init(editing item: MenuItem) {
        editingID = item.id
        existingSortOrder = item.sortOrder
        nameEN = item.nameEN ?? ""
        nameES = item.nameES ?? ""
        description = item.description ?? ""
        category = item.category
        categoryType = item.categoryType
        amountText = String(format: "%.2f", Double(item.price.amountCents) / 100)
        unit = item.price.unit
        minQuantityText = String(item.price.minQuantity)
        allergens = Set(item.allergens)
        photos = item.photos
        wasAvailable = item.isAvailable
        // An existing dish with no allergens was already saved through this
        // same check, so re-confirming would be busywork.
        allergensAcknowledged = item.allergens.isEmpty
    }

    /// Non-nil when editing. Drives both the upsert id and the screen title.
    public private(set) var editingID: UUID?
    private var existingSortOrder: Int = 0
    private var wasAvailable: Bool = true
    public var isEditing: Bool { editingID != nil }

    // MARK: - Validation

    public var amountCents: Int? {
        let cleaned = amountText
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = Double(cleaned), value > 0 else { return nil }
        return Int((value * 100).rounded())
    }

    public var minQuantity: Int {
        max(Int(minQuantityText.trimmingCharacters(in: .whitespaces)) ?? 1, 1)
    }

    public var price: Price? {
        guard let cents = amountCents else { return nil }
        return try? Price(amountCents: cents, unit: unit, minQuantity: minQuantity)
    }

    /// What the buyer will see, shown live under the price fields.
    ///
    /// The single most valuable thing on this screen: it closes the loop
    /// between what a cook types and what a stranger reads, which is precisely
    /// where the incumbent marketplaces fail (`RESEARCH.md` Finding 2).
    public var buyerPreview: String {
        price?.displayWithMinimum ?? "—"
    }

    public var hasName: Bool {
        !nameEN.trimmingCharacters(in: .whitespaces).isEmpty
            || !nameES.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Allergens are a safety surface, so "none" must be a deliberate choice
    /// rather than an empty field someone skipped past.
    public var allergensAcknowledged: Bool = false

    public var validationProblems: [String] {
        var problems: [String] = []
        if !hasName { problems.append("Add a name — English, Spanish, or both.") }
        if amountCents == nil { problems.append("Add a price.") }
        if allergens.isEmpty && !allergensAcknowledged {
            problems.append("Choose allergens, or confirm there are none.")
        }
        return problems
    }

    public var canSave: Bool { validationProblems.isEmpty }

    public func build(cookID: UUID) -> MenuItem? {
        guard canSave, let price else { return nil }
        let trimmedEN = nameEN.trimmingCharacters(in: .whitespaces)
        let trimmedES = nameES.trimmingCharacters(in: .whitespaces)
        let cat = category.trimmingCharacters(in: .whitespaces)
        return MenuItem(
            id: editingID ?? UUID(),
            cookID: cookID,
            nameEN: trimmedEN.isEmpty ? nil : trimmedEN,
            nameES: trimmedES.isEmpty ? nil : trimmedES,
            description: description.isEmpty ? nil : description,
            category: cat.isEmpty ? (trimmedEN.isEmpty ? trimmedES : trimmedEN) : cat,
            categoryType: categoryType,
            allergens: allergens.sorted(),
            // Editing must not silently un-sell-out a dish the cook marked
            // gone earlier today.
            isAvailable: isEditing ? wasAvailable : true,
            price: price,
            photos: photos,
            sortOrder: existingSortOrder
        )
    }
}
