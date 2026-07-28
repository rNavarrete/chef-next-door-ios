import Foundation

/// The unit a price is quoted in.
///
/// Mirrors the `price_unit` enum in `supabase/migrations/001_extensions_and_enums.sql`.
/// Raw values are the Postgres spellings.
public enum PriceUnit: String, Codable, Sendable, CaseIterable, Hashable {
    case each
    case halfDozen = "half_dozen"
    case dozen
    case loaf
    case jar
    case tray
    case weeklyPackage = "weekly_package"
    case perPerson = "per_person"

    /// How many individual pieces this unit represents, when that's a
    /// meaningful question. `nil` means the unit is genuinely not
    /// per-piece comparable — a tray or a weekly package has no honest
    /// per-piece price, and inventing one would reintroduce exactly the
    /// ambiguity this type exists to prevent.
    var piecesPerUnit: Int? {
        switch self {
        case .each, .loaf, .jar: 1
        case .halfDozen: 6
        case .dozen: 12
        case .tray, .weeklyPackage, .perPerson: nil
        }
    }

    /// Short form used after the amount: "$3 **each**", "$36/**dozen**".
    var shortLabel: String {
        switch self {
        case .each: "each"
        case .halfDozen: "half dozen"
        case .dozen: "dozen"
        case .loaf: "loaf"
        case .jar: "jar"
        case .tray: "tray"
        case .weeklyPackage: "week"
        case .perPerson: "person"
        }
    }

    /// Whether the display form reads better as "$36/dozen" than "$36 dozen".
    var usesSlash: Bool {
        switch self {
        case .each: false
        default: true
        }
    }
}

/// A price that cannot be ambiguous.
///
/// This is the single most important type in the app. Both marketplaces we
/// researched break on the same thing: a bare number in a `price` field, with
/// the unit either missing, buried in prose, or deliberately faked
/// (`RESEARCH.md` Finding 2 — `$1` cards hiding `$110` packages, `Pupusas 4x1`
/// next to `Pupusa $90`).
///
/// There is deliberately **no initializer that omits `unit`**. The type system
/// refuses to represent the ambiguity that makes the incumbents unusable.
public struct Price: Codable, Sendable, Equatable, Hashable {
    public let amountCents: Int
    public let unit: PriceUnit
    public let minQuantity: Int

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case nonPositiveAmount(Int)
        case nonPositiveMinQuantity(Int)

        public var description: String {
            switch self {
            case .nonPositiveAmount(let cents):
                "Price amount must be greater than zero (got \(cents) cents)."
            case .nonPositiveMinQuantity(let qty):
                "Minimum quantity must be at least 1 (got \(qty))."
            }
        }
    }

    public init(amountCents: Int, unit: PriceUnit, minQuantity: Int = 1) throws {
        guard amountCents > 0 else { throw ValidationError.nonPositiveAmount(amountCents) }
        guard minQuantity > 0 else { throw ValidationError.nonPositiveMinQuantity(minQuantity) }
        self.amountCents = amountCents
        self.unit = unit
        self.minQuantity = minQuantity
    }

    /// Comparable per-piece price, where the unit permits one.
    ///
    /// Returns `nil` for trays, weekly packages, and per-person pricing rather
    /// than fabricating a comparison. Sort and filter must treat `nil` as
    /// "not comparable", never as zero.
    public var perPieceCents: Int? {
        guard let pieces = unit.piecesPerUnit else { return nil }
        return amountCents / pieces
    }

    // MARK: - Display

    /// The primary display string. Always amount **and** unit.
    ///
    /// `$3 each` · `$36/dozen` · `$110/week`
    public var display: String {
        unit.usesSlash
            ? "\(Self.currency(amountCents))/\(unit.shortLabel)"
            : "\(Self.currency(amountCents)) \(unit.shortLabel)"
    }

    /// Display plus the per-piece equivalent when one exists and the unit
    /// isn't already per-piece: `$36/dozen · $3 ea`
    public var displayWithPerPiece: String {
        guard unit != .each,
              let per = perPieceCents,
              unit.piecesPerUnit ?? 1 > 1
        else { return display }
        return "\(display) · \(Self.currency(per)) ea"
    }

    /// Full form including the minimum, for the cook's live preview and
    /// the detail row: `$3 each · min 3`
    public var displayWithMinimum: String {
        minQuantity > 1 ? "\(displayWithPerPiece) · min \(minQuantity)" : displayWithPerPiece
    }

    // MARK: - Split display
    //
    // The polish pass sets a price as three typographic weights on one line —
    // figure at display 19, unit at 14 semibold, qualifier at 13.5 tertiary —
    // instead of one string in a pill. Splitting here rather than in the view
    // keeps every surface agreeing on where the boundaries fall.

    /// Just the money: `$3`.
    public var figure: String { Self.currency(amountCents) }

    /// What the money buys: `each`, `/dozen`.
    public var unitLabel: String {
        unit.usesSlash ? "/\(unit.shortLabel)" : unit.shortLabel
    }

    /// Everything after the unit, already joined: `· $3 ea · min 3`. Empty when
    /// there is no per-piece equivalent and no minimum.
    public var qualifier: String {
        var parts: [String] = []
        if unit != .each, let per = perPieceCents, (unit.piecesPerUnit ?? 1) > 1 {
            parts.append("\(Self.currency(per)) ea")
        }
        if minQuantity > 1 { parts.append("min \(minQuantity)") }
        return parts.isEmpty ? "" : "· " + parts.joined(separator: " · ")
    }

    /// Total for a quantity of *units* (not pieces).
    public func totalCents(quantity: Int) -> Int {
        amountCents * max(quantity, minQuantity)
    }

    static func currency(_ cents: Int) -> String {
        let dollars = Double(cents) / 100
        // Whole dollars render without cents — "$3", not "$3.00". Prices in
        // this market are overwhelmingly whole, and the noise costs legibility.
        if cents % 100 == 0 {
            return "$\(cents / 100)"
        }
        return String(format: "$%.2f", dollars)
    }
}
