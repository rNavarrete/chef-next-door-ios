import Testing
@testable import LitKitchen

/// The prices in these cases are taken verbatim from real listings in
/// `RESEARCH.md` Finding 2 — the exact strings that make the incumbent
/// marketplaces unusable.
@Suite("Price — the ambiguity that breaks the incumbents")
struct PriceTests {

    @Test("A price cannot exist without a unit")
    func unitIsRequired() throws {
        // This is the whole point of the type. The following does not compile,
        // and that is the test:
        //
        //     Price(amountCents: 300)   // ✗ missing argument for 'unit'
        //
        let p = try Price(amountCents: 300, unit: .each)
        #expect(p.unit == .each)
    }

    @Test("Zero and negative amounts are rejected")
    func rejectsNonPositive() {
        #expect(throws: Price.ValidationError.nonPositiveAmount(0)) {
            try Price(amountCents: 0, unit: .each)
        }
        #expect(throws: Price.ValidationError.nonPositiveAmount(-100)) {
            try Price(amountCents: -100, unit: .dozen)
        }
    }

    @Test("Minimum quantity must be at least one")
    func rejectsBadMinimum() {
        #expect(throws: Price.ValidationError.nonPositiveMinQuantity(0)) {
            try Price(amountCents: 300, unit: .each, minQuantity: 0)
        }
    }

    @Test("Per-piece is computed where the unit permits it")
    func perPiece() throws {
        #expect(try Price(amountCents: 3600, unit: .dozen).perPieceCents == 300)
        #expect(try Price(amountCents: 1800, unit: .halfDozen).perPieceCents == 300)
        #expect(try Price(amountCents: 300, unit: .each).perPieceCents == 300)
    }

    @Test("Per-piece is nil — never zero, never invented — where it is meaningless")
    func perPieceIsNilForNonComparableUnits() throws {
        // A tray and a weekly package have no honest per-piece price.
        // Returning 0 or a guess would reintroduce the ambiguity this type
        // exists to prevent, and would silently poison any sort.
        #expect(try Price(amountCents: 15000, unit: .tray).perPieceCents == nil)
        #expect(try Price(amountCents: 11000, unit: .weeklyPackage).perPieceCents == nil)
        #expect(try Price(amountCents: 1300, unit: .perPerson).perPieceCents == nil)
    }

    @Test("Display always carries the unit")
    func displayCarriesUnit() throws {
        #expect(try Price(amountCents: 300, unit: .each).display == "$3 each")
        #expect(try Price(amountCents: 3600, unit: .dozen).display == "$36/dozen")
        #expect(try Price(amountCents: 11000, unit: .weeklyPackage).display == "$110/week")
        #expect(try Price(amountCents: 900, unit: .loaf).display == "$9/loaf")
    }

    @Test("Bulk units show the per-piece equivalent so buyers can compare")
    func displayWithPerPiece() throws {
        #expect(try Price(amountCents: 3600, unit: .dozen).displayWithPerPiece == "$36/dozen · $3 ea")
        // Already per-piece — no redundant restatement.
        #expect(try Price(amountCents: 300, unit: .each).displayWithPerPiece == "$3 each")
        // Not comparable — no fabricated equivalent.
        #expect(try Price(amountCents: 15000, unit: .tray).displayWithPerPiece == "$150/tray")
    }

    @Test("Minimums appear when they exist")
    func displayWithMinimum() throws {
        let p = try Price(amountCents: 300, unit: .each, minQuantity: 3)
        #expect(p.displayWithMinimum == "$3 each · min 3")
        let noMin = try Price(amountCents: 300, unit: .each)
        #expect(noMin.displayWithMinimum == "$3 each")
    }

    @Test("Whole dollars drop the cents; partial amounts keep them")
    func currencyFormatting() throws {
        #expect(try Price(amountCents: 300, unit: .each).display == "$3 each")
        #expect(try Price(amountCents: 250, unit: .each).display == "$2.50 each")
    }

    @Test("Totals respect the minimum")
    func totalsHonourMinimum() throws {
        let p = try Price(amountCents: 300, unit: .each, minQuantity: 3)
        #expect(p.totalCents(quantity: 6) == 1800)
        // Ordering below the minimum still charges the minimum.
        #expect(p.totalCents(quantity: 1) == 900)
    }

    @Test("Real listings that are indistinguishable on the incumbents are distinct here")
    func realWorldAmbiguityIsResolved() throws {
        // From RESEARCH.md: `Pupusas $3`, `Pupusas 4x1 $1`, `Pupusa $90`.
        // On OfferUp these are three rows with one number each and no way to
        // tell them apart. Here the unit disambiguates all three.
        let each = try Price(amountCents: 300, unit: .each)
        let fourForADollar = try Price(amountCents: 100, unit: .each, minQuantity: 4)
        let byTheTray = try Price(amountCents: 9000, unit: .tray)

        #expect(each.display != byTheTray.display)
        #expect(fourForADollar.displayWithMinimum == "$1 each · min 4")
        #expect(byTheTray.perPieceCents == nil)
    }
}
