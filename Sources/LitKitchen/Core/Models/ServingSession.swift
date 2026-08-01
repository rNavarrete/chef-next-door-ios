import Foundation

/// One period of service — a cook opened, cooked, and eventually closed.
///
/// This is **not** the scheduled "drop" object we removed: no future
/// scheduling, no declared capacity, no pickup window. It records what
/// happened, not what is planned (`PRD.md` §5).
///
/// It exists because putting availability directly on the mutable cook row
/// erased history — the timestamps were overwritten on every open, so nothing
/// could say *which* service period a claim or a complaint belonged to, and
/// the freshness metrics in `PRD.md` §9 were uncomputable.
public struct ServingSession: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: UUID
    public let cookID: UUID
    public let kitchenID: UUID

    /// When they lit up. This is what the UI **displays**: "Cooking · since 9:40 am".
    public let openedAt: Date
    /// Last proof of life. This is what **drives the decay tier**. Bumped only
    /// by activity that asserts current service — see ``CookActivity``.
    public let lastConfirmedAt: Date
    public let closedAt: Date?
    public let closedBy: String?
    public let status: ServingStatus

    enum CodingKeys: String, CodingKey {
        case id
        case cookID = "cook_id"
        case kitchenID = "kitchen_id"
        case openedAt = "opened_at"
        case lastConfirmedAt = "last_confirmed_at"
        case closedAt = "closed_at"
        case closedBy = "closed_by"
        case status
    }

    public var isOpen: Bool { closedAt == nil }

    public func freshness(now: Date = .now) -> FreshnessTier {
        FreshnessTier.of(lastConfirmedAt: lastConfirmedAt, closedAt: closedAt, now: now)
    }

    /// The label shown beside the lamp dot. **Absolute clock time, always** —
    /// elapsed durations ("15 min ago", "6h ago") never appear in the
    /// interface; they read as either ambiguous or accusatory
    /// (`DESIGN_BRIEF.md` §7a, rule 1).
    public func availabilityLabel(now: Date = .now, calendar: Calendar = .current) -> String {
        let clock = Self.clockFormatter.string(from: openedAt).lowercased()
        switch freshness(now: now) {
        case .lit, .dimming:
            return "Cooking · since \(clock)"
        case .unconfirmed:
            return "Open since \(clock) · not confirmed recently"
        case .out:
            guard let closedAt else { return "Closed" }
            return "Closed at \(Self.clockFormatter.string(from: closedAt).lowercased())"
        }
    }

    static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}
