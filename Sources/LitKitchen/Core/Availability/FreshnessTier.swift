import Foundation

/// How much a kitchen's "I'm cooking" claim can still be trusted.
///
/// The light metaphor makes "open" unmissable, which means it can also lie
/// unmissably. This is the decay ladder from `DESIGN_BRIEF.md` §7a, and it
/// mirrors `freshness_of()` in
/// `supabase/migrations/007_decay_ladder.sql` — **the two must stay in step.**
/// The server is authoritative for ranking; the client computes the same tier
/// so presentation can update between fetches without a round trip.
public enum FreshnessTier: String, Codable, Sendable, CaseIterable {
    /// 0–4h. Full glow, pulsing dot. Primary action: claim.
    case lit
    /// 4–6h. Desaturated, no pulse. Still claimable.
    case dimming
    /// 6h+. Hollow ring, no glow, neutral label. Primary action becomes
    /// *ask*, not claim.
    case unconfirmed
    /// Session closed, by the cook or by the quiet-close (`migrations/054`).
    case out

    static let dimmingThreshold: TimeInterval = 4 * 3600
    static let unconfirmedThreshold: TimeInterval = 6 * 3600

    /// - Parameter now: injected so boundary transitions are testable. Never
    ///   defaulted at a call site that matters — see `FreshnessTierTests`.
    public static func of(
        lastConfirmedAt: Date,
        closedAt: Date? = nil,
        now: Date = .now
    ) -> FreshnessTier {
        if closedAt != nil { return .out }
        let age = now.timeIntervalSince(lastConfirmedAt)
        // A future timestamp (clock skew) is treated as freshly confirmed
        // rather than wrapping into a stale tier.
        if age < dimmingThreshold { return .lit }
        if age < unconfirmedThreshold { return .dimming }
        return .unconfirmed
    }

    /// Whether claiming is still the primary affordance. Past 6 hours the
    /// interface stops leading with the clock and starts leading with the
    /// question — see `DESIGN_BRIEF.md` §7a.
    public var allowsPrimaryClaim: Bool {
        switch self {
        case .lit, .dimming: true
        case .unconfirmed, .out: false
        }
    }

    /// Ranking weight. Lower sorts first. `unconfirmed` must never outrank a
    /// confirmed kitchen, and must never be the first row of the feed
    /// (`PRD.md` §5, rule 3).
    public var rankOrder: Int {
        switch self {
        case .lit: 0
        case .dimming: 1
        case .unconfirmed: 2
        case .out: 3
        }
    }
}

/// What a cook did, and whether it counts as proof they're cooking *now*.
///
/// An earlier draft relit a kitchen on **any** cook activity, which meant
/// clearing a three-day-old claim at 9pm would relight a kitchen that went
/// cold at noon — the exact failure the ladder exists to prevent, wired in
/// backwards. Only actions that necessarily assert current service confirm.
public enum CookActivity: Sendable, Equatable {
    case explicitStillCooking
    case toggledItemAvailability
    case editedServingNote
    case answeredClaim(fromCurrentSession: Bool)
    case editedMenuPricesOrPhotos
    case editedProfileOrPermit

    public var confirmsCurrentService: Bool {
        switch self {
        case .explicitStillCooking, .toggledItemAvailability, .editedServingNote:
            true
        case .answeredClaim(let fromCurrentSession):
            fromCurrentSession
        case .editedMenuPricesOrPhotos, .editedProfileOrPermit:
            false  // bookkeeping is not cooking
        }
    }
}
