import Foundation

/// Development fixtures. Drawn from dishes and price shapes actually observed
/// in the research — including the ones that are indistinguishable on the
/// incumbent marketplaces, so the UI is exercised against real ambiguity
/// rather than tidy invented data.
extension MenuItem {
    static let sampleCookID = UUID(uuidString: "A1B2C3D4-0000-0000-0000-000000000001")!

    static var samples: [MenuItem] {
        [
            MenuItem(
                cookID: sampleCookID,
                nameEN: "Pork tamale",
                nameES: "Tamal de puerco en rojo",
                description: "Pork shoulder, chile colorado, masa de maíz",
                category: "tamales",
                categoryType: .mehkoMeal,
                allergens: ["Pork", "Corn"],
                price: try! Price(amountCents: 300, unit: .each, minQuantity: 3)
            ),
            MenuItem(
                cookID: sampleCookID,
                nameES: "Tamal de rajas con queso",
                category: "tamales",
                categoryType: .mehkoMeal,
                allergens: ["Dairy", "Corn"],
                price: try! Price(amountCents: 3600, unit: .dozen)
            ),
            MenuItem(
                cookID: sampleCookID,
                nameEN: "Champurrado",
                category: "champurrado",
                categoryType: .mehkoMeal,
                allergens: ["Dairy"],
                isAvailable: false,
                price: try! Price(amountCents: 400, unit: .each)
            ),
        ]
    }
}
