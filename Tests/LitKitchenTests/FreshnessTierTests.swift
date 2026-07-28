import Foundation
import Testing
@testable import LitKitchen

/// The decay ladder is the mitigation for the highest-severity risk in the
/// product — a lit kitchen that stopped cooking hours ago (`PRD.md` §10).
/// Every boundary is tested against an injected clock rather than wall time.
@Suite("Decay ladder")
struct FreshnessTierTests {

    let opened = Date(timeIntervalSince1970: 1_753_430_400)  // 09:40 local-ish

    func at(_ hours: Double) -> Date { opened.addingTimeInterval(hours * 3600) }

    @Test("Tier boundaries", arguments: [
        (0.0, FreshnessTier.lit),
        (3.99, .lit),
        (4.0, .dimming),      // exact boundary belongs to the dimmer tier
        (5.99, .dimming),
        (6.0, .unconfirmed),  // exact boundary flips the primary action
        (12.0, .unconfirmed),
    ])
    func boundaries(hours: Double, expected: FreshnessTier) {
        #expect(FreshnessTier.of(lastConfirmedAt: opened, now: at(hours)) == expected)
    }

    @Test("A closed session is out regardless of how recently it was confirmed")
    func closedWins() {
        let tier = FreshnessTier.of(
            lastConfirmedAt: opened,
            closedAt: at(0.5),
            now: at(0.6)
        )
        #expect(tier == .out)
    }

    @Test("Clock skew reads as fresh, never as stale")
    func futureTimestampIsNotStale() {
        // A confirmation timestamped slightly in the future must not wrap
        // into `unconfirmed` and wrongly dim a kitchen that just opened.
        #expect(FreshnessTier.of(lastConfirmedAt: at(1), now: opened) == .lit)
    }

    @Test("Past six hours, claiming stops being the primary affordance")
    func primaryActionChanges() {
        #expect(FreshnessTier.lit.allowsPrimaryClaim)
        #expect(FreshnessTier.dimming.allowsPrimaryClaim)
        #expect(!FreshnessTier.unconfirmed.allowsPrimaryClaim)
        #expect(!FreshnessTier.out.allowsPrimaryClaim)
    }

    @Test("Unconfirmed never outranks a confirmed kitchen")
    func rankOrdering() {
        let sorted = FreshnessTier.allCases.sorted { $0.rankOrder < $1.rankOrder }
        #expect(sorted == [.lit, .dimming, .unconfirmed, .out])
    }
}

@Suite("What counts as proof a cook is still cooking")
struct CookActivityTests {

    @Test("Actions that assert current service confirm the session")
    func confirmingActions() {
        #expect(CookActivity.explicitStillCooking.confirmsCurrentService)
        #expect(CookActivity.toggledItemAvailability.confirmsCurrentService)
        #expect(CookActivity.editedServingNote.confirmsCurrentService)
        #expect(CookActivity.answeredClaim(fromCurrentSession: true).confirmsCurrentService)
    }

    @Test("Bookkeeping does not relight a cold kitchen")
    func nonConfirmingActions() {
        // The regression this guards: an earlier design bumped the clock on
        // *any* cook activity, so clearing a three-day-old claim at 9pm would
        // relight a kitchen that went cold at noon — the exact failure the
        // ladder exists to prevent, wired in backwards.
        #expect(!CookActivity.answeredClaim(fromCurrentSession: false).confirmsCurrentService)
        #expect(!CookActivity.editedMenuPricesOrPhotos.confirmsCurrentService)
        #expect(!CookActivity.editedProfileOrPermit.confirmsCurrentService)
    }
}

@Suite("Availability labels")
struct AvailabilityLabelTests {

    func session(openedHoursAgo: Double, closed: Bool = false, now: Date) -> ServingSession {
        let opened = now.addingTimeInterval(-openedHoursAgo * 3600)
        return ServingSession(
            id: UUID(), cookID: UUID(), kitchenID: UUID(),
            openedAt: opened,
            lastConfirmedAt: opened,
            closedAt: closed ? now.addingTimeInterval(-60) : nil,
            closedBy: closed ? "cook" : nil,
            status: closed ? .closed : .serving
        )
    }

    @Test("Labels use absolute clock time, never elapsed duration")
    func absoluteTimeOnly() {
        let now = Date()
        let label = session(openedHoursAgo: 2, now: now).availabilityLabel(now: now)

        // Rule 1 of the decay ladder: elapsed durations never appear —
        // they read as either ambiguous or accusatory.
        #expect(label.contains("since"))
        #expect(!label.contains("ago"))
        #expect(!label.contains("hr"))
        #expect(!label.lowercased().contains("min ago"))
    }

    @Test("An unconfirmed kitchen states what is known, not that it is closed")
    func unconfirmedWording() {
        let now = Date()
        let label = session(openedHoursAgo: 8, now: now).availabilityLabel(now: now)
        #expect(label.contains("unconfirmed"))
        // Never assert the cook is closed — we do not know that.
        #expect(!label.lowercased().contains("closed"))
    }
}
