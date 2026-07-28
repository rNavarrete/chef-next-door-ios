import Foundation
import Testing
@testable import LitKitchen

/// The menu builder is where an ambiguous price would get back in. `Price`
/// already refuses to hold one, but a form needs somewhere to keep half-typed
/// input — so these tests guard the boundary between the two.
@Suite("Menu builder draft")
@MainActor
struct MenuItemDraftTests {

    func draft(_ configure: (MenuItemDraft) -> Void = { _ in }) -> MenuItemDraft {
        let d = MenuItemDraft()
        d.nameES = "Tamal de puerco"
        d.amountText = "3"
        d.unit = .each
        d.allergens = ["Pork", "Corn"]
        configure(d)
        return d
    }

    @Test("A dish cannot be saved without a price")
    func priceRequired() {
        let d = draft { $0.amountText = "" }
        #expect(!d.canSave)
        #expect(d.build(cookID: UUID()) == nil)
    }

    @Test("A dish cannot be saved without a name in either language")
    func nameRequired() {
        let d = draft { $0.nameES = ""; $0.nameEN = "" }
        #expect(!d.canSave)
    }

    @Test("Either language alone is enough — neither is 'the' name")
    func eitherLanguageSuffices() {
        #expect(draft { $0.nameEN = ""; $0.nameES = "Pupusa revuelta" }.canSave)
        #expect(draft { $0.nameES = ""; $0.nameEN = "Sourdough loaf" }.canSave)
    }

    @Test("Allergens must be chosen or explicitly acknowledged as none")
    func allergensCannotBeSkipped() {
        // An empty allergen list is indistinguishable from an unfilled form,
        // and this is the one field where that ambiguity is a safety problem.
        let skipped = draft { $0.allergens = [] }
        #expect(!skipped.canSave)

        let acknowledged = draft { $0.allergens = []; $0.allergensAcknowledged = true }
        #expect(acknowledged.canSave)
    }

    @Test("Zero and negative amounts never become a price")
    func rejectsNonPositive() {
        #expect(draft { $0.amountText = "0" }.price == nil)
        #expect(draft { $0.amountText = "-4" }.price == nil)
        #expect(draft { $0.amountText = "abc" }.price == nil)
    }

    @Test("Currency input is forgiving about how a cook types it")
    func parsesRealisticInput() {
        #expect(draft { $0.amountText = "$3" }.amountCents == 300)
        #expect(draft { $0.amountText = " 3.50 " }.amountCents == 350)
        #expect(draft { $0.amountText = "36" }.amountCents == 3600)
    }

    @Test("The buyer preview is exactly what a stranger will read")
    func buyerPreviewMatchesBuyerFacingString() {
        let d = draft { $0.amountText = "36"; $0.unit = .dozen; $0.minQuantityText = "1" }
        #expect(d.buyerPreview == "$36/dozen · $3 ea")

        let withMin = draft { $0.amountText = "3"; $0.unit = .each; $0.minQuantityText = "3" }
        #expect(withMin.buyerPreview == "$3 each · min 3")
    }

    @Test("An empty minimum is 1, never zero")
    func minimumDefaults() {
        #expect(draft { $0.minQuantityText = "" }.minQuantity == 1)
        #expect(draft { $0.minQuantityText = "0" }.minQuantity == 1)
    }

    @Test("A built item carries both names, so search can match either")
    func buildsBilingual() throws {
        let d = draft { $0.nameEN = "Pork tamale"; $0.nameES = "Tamal de puerco" }
        let item = try #require(d.build(cookID: UUID()))
        #expect(item.nameEN == "Pork tamale")
        #expect(item.nameES == "Tamal de puerco")
    }
}

@Suite("Cook repository rules")
@MainActor
struct CookRepositoryTests {

    @Test("Opening twice does not create a second session")
    func openIsIdempotent() async throws {
        let repo = InMemoryCookRepository()
        let first = try await repo.openKitchen(note: nil)
        let second = try await repo.openKitchen(note: nil)
        #expect(first.id == second.id)
    }

    @Test("Flipping an item sold out confirms the session")
    func availabilityConfirms() async throws {
        let item = MenuItem(
            cookID: UUID(), nameEN: "Tamal", category: "tamales",
            categoryType: .mehkoMeal, price: try Price(amountCents: 300, unit: .each)
        )
        let repo = InMemoryCookRepository(items: [item])
        try await repo.openKitchen(note: nil)

        try await repo.setAvailability(false, for: item.id)
        #expect(repo.confirmationCount == 1)
    }

    @Test("Bookkeeping does not confirm the session")
    func bookkeepingDoesNotConfirm() async throws {
        let repo = InMemoryCookRepository()
        try await repo.openKitchen(note: nil)

        try await repo.confirmServing(.editedMenuPricesOrPhotos)
        try await repo.confirmServing(.answeredClaim(fromCurrentSession: false))
        #expect(repo.confirmationCount == 0)

        try await repo.confirmServing(.explicitStillCooking)
        #expect(repo.confirmationCount == 1)
    }

    @Test("Confirming a closed kitchen does nothing")
    func closedKitchenIgnoresConfirmation() async throws {
        let repo = InMemoryCookRepository()
        try await repo.openKitchen(note: nil)
        try await repo.closeKitchen(reason: "cook")

        try await repo.confirmServing(.explicitStillCooking)
        #expect(repo.confirmationCount == 0)
        #expect(try await repo.currentSession() == nil)
    }
}
