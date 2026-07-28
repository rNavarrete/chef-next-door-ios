import Foundation

extension DiscoveryResult {
    /// Mirrors the SQL fixtures used to verify the discovery RPCs, including
    /// a cook who is `unconfirmed` — the state most likely to be designed
    /// badly precisely because it's easy to forget it exists.
    public static var samples: [DiscoveryResult] {
        let now = Date()
        return [
            DiscoveryResult(
                cookID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                displayName: "María G.",
                avatarURL: nil,
                permitStatus: .verified, permitNumber: "24417",
                agencyName: "LA County Dept. of Public Health",
                neighborhood: "Covina",
                distanceM: 1930,
                publicLat: 34.08936, publicLon: -117.89156,
                sessionID: UUID(),
                openedAt: now.addingTimeInterval(-2 * 3600),
                lastConfirmedAt: now.addingTimeInterval(-20 * 60),
                freshness: .lit,
                itemCount: 2,
                headlineItems: ["Tamal de puerco", "Tamal de rajas con queso"],
                headlineItemsES: ["Tamal de puerco", "Tamal de rajas con queso"],
                headlinePhoto: nil,
                minPriceCents: 300, minPriceUnit: .each, minPriceMinQty: 3
            ),
            DiscoveryResult(
                cookID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                displayName: "Beto R.",
                avatarURL: nil,
                permitStatus: .verified, permitNumber: "24418",
                agencyName: "LA County Dept. of Public Health",
                neighborhood: "West Covina",
                distanceM: 5150,
                publicLat: 34.06736, publicLon: -117.93902,
                sessionID: UUID(),
                openedAt: now.addingTimeInterval(-9 * 3600),
                lastConfirmedAt: now.addingTimeInterval(-9 * 3600),
                freshness: .unconfirmed,
                itemCount: 1,
                headlineItems: ["Birria de res"],
                headlineItemsES: ["Birria de res"],
                headlinePhoto: nil,
                minPriceCents: 400, minPriceUnit: .each, minPriceMinQty: 1
            ),
            DiscoveryResult(
                cookID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                displayName: "Yesenia O.",
                avatarURL: nil,
                permitStatus: .verified, permitNumber: "24419",
                agencyName: "LA County Dept. of Public Health",
                neighborhood: "Azusa",
                distanceM: 5490,
                publicLat: 34.13252, publicLon: -117.90937,
                sessionID: nil, openedAt: nil, lastConfirmedAt: nil, freshness: nil,
                itemCount: 1,
                headlineItems: ["Masa madre"],
                headlineItemsES: ["Masa madre"],
                headlinePhoto: nil,
                minPriceCents: 900, minPriceUnit: .loaf, minPriceMinQty: 1
            ),
        ]
    }
}
