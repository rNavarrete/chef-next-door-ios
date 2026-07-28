import ActivityKit
import Foundation

/// The Live Activity for a buyer's active claim.
///
/// **A persistent handoff card, not a countdown.** There is no fixed pickup
/// window under the availability model, so there is nothing to count down to.
/// What it carries is what a buyer needs while walking to a door: who they're
/// meeting, what they claimed, where to go, and one tap to reach the cook
/// (`DESIGN_BRIEF.md` §6, `PRD.md` §6).
///
/// Compiled into both the app and the widget extension — ActivityKit requires
/// the attribute type to be identical on both sides.
public struct CookingActivityAttributes: ActivityAttributes {

    /// Where the claim is in its short life. The card exists for **both**
    /// stages, which was not true at first: it used to start only once the cook
    /// confirmed, and so in practice never appeared at all. The wait is the
    /// part worth putting on a Lock Screen — "has Yolanda said yes yet?" is the
    /// question a buyer reaches for their phone to answer.
    public enum Stage: String, Codable, Hashable, Sendable {
        /// Claimed; the cook hasn't answered. No address exists yet.
        case waiting
        /// The cook said yes. The address is real and directions work.
        case confirmed
    }

    /// Changes over the life of the claim; delivered by ActivityKit push.
    public struct ContentState: Codable, Hashable {
        public var stage: Stage
        /// Drives the lamp dot. Mirrors the decay ladder server-side: when the
        /// cook's session goes `unconfirmed`, this goes false and the card
        /// stops asserting they're cooking.
        public var cookIsCooking: Bool
        /// "6 tamales de puerco"
        public var itemSummary: String
        /// "$18 · $3 each" — always amount **and** unit, same rule as everywhere.
        public var priceSummary: String
        /// Revealed only because this buyer holds a confirmed claim; empty
        /// while ``Stage/waiting``.
        public var addressLine: String
        /// Absolute clock time, never elapsed: "since 9:40 am".
        public var sinceLabel: String
        /// **State, not attribute.** It only becomes knowable when the cook
        /// confirms, and `ActivityAttributes` are frozen at `request` time — so
        /// holding it there forced the activity to start late, which is the
        /// bug that kept this card from ever showing up.
        public var directionsURL: URL?

        public init(
            stage: Stage,
            cookIsCooking: Bool,
            itemSummary: String,
            priceSummary: String,
            addressLine: String,
            sinceLabel: String,
            directionsURL: URL? = nil
        ) {
            self.stage = stage
            self.cookIsCooking = cookIsCooking
            self.itemSummary = itemSummary
            self.priceSummary = priceSummary
            self.addressLine = addressLine
            self.sinceLabel = sinceLabel
            self.directionsURL = directionsURL
        }
    }

    /// Fixed for the life of the activity — and only things that genuinely are.
    public var cookName: String
    /// The conversation this card is about.
    ///
    /// Was `claimID`. Claims were retired in `migrations/043`, and a card keyed
    /// to a table nothing writes to isn't broken so much as never created,
    /// which is worse — nothing fails and nobody notices.
    public var threadID: String

    public init(cookName: String, threadID: String) {
        self.cookName = cookName
        self.threadID = threadID
    }
}

public extension CookingActivityAttributes.ContentState {
    /// Headline copy. Never asserts the cook is closed — same rule as the
    /// decay ladder: state what is known.
    ///
    /// Two things this got wrong on a real Lock Screen, both only visible once
    /// push was delivering:
    ///
    /// 1. `"hasn't confirmed since"` was rendered next to `sinceLabel`, which
    ///    is itself `"since 2:15 pm"` — producing **"HASN'T CONFIRMED SINCE
    ///    SINCE 2:15 PM"**. The preposition belongs to the label, not here.
    /// 2. More seriously, it read `"hasn't confirmed"` on a claim the cook had
    ///    *just confirmed*, directly above the address that only exists
    ///    because she confirmed it. `cookIsCooking` tracks her serving
    ///    session's decay, which is the right signal while a buyer is
    ///    browsing and the wrong one here: answering a claim is a far stronger
    ///    statement of "I am here" than any session timer. Once confirmed, the
    ///    card stops second-guessing her.
    var headline: String {
        switch stage {
        case .waiting:
            "hasn't answered yet"
        case .confirmed:
            "said yes ·"
        }
    }

    /// Whether the lamp burns on this card.
    ///
    /// Same reasoning as `headline`: a confirmed claim means the cook answered
    /// you personally, so a dark lamp beside "said yes" would contradict
    /// itself. While waiting, her session freshness is still the honest signal.
    var lampIsLit: Bool {
        stage == .confirmed || cookIsCooking
    }
}
