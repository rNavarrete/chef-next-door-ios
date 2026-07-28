import SwiftUI

/// Ways to narrow the feed.
///
/// Three, deliberately. A filter bar is a promise that each control changes the
/// answer meaningfully, and a row of eight chips on a feed of nine kitchens is
/// furniture rather than a tool. Each of these answers a question a buyer
/// actually has at six o'clock on a weeknight.
///
/// All three are computed from what the feed has already loaded, so they apply
/// instantly and cost no round trip. That also means they narrow *what is on
/// screen* rather than re-querying a wider net — the radius still decides what
/// arrived, and a filter cannot reach past it.
enum FeedFilter: String, CaseIterable, Identifiable {
    /// Only kitchens whose permit matched the county register.
    ///
    /// The one filter that changes what a buyer is trusting rather than what
    /// they are eating. Deliberately reads "Permitted" and not "Verified" —
    /// `verified` means the permit exists at this address and is unclaimed
    /// here, which is not the same as this person holding it (030), and the
    /// badge copy has never claimed otherwise.
    case permitted
    /// Confirmed in the last couple of hours, rather than lit this morning and
    /// untouched since.
    ///
    /// This is the app's whole premise expressed as a control. `isCooking`
    /// already excludes kitchens that decayed all the way out, but it still
    /// includes `unconfirmed` — somebody who turned their light on at 11am and
    /// has not opened the app since. That is the exact case the feed warns
    /// about in prose ("Ask before you drive"); this lets a buyer skip it.
    case stillCooking
    /// Within roughly a fifteen-minute round trip.
    case closeBy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .permitted:    "Permitted"
        case .stillCooking: "Still cooking"
        case .closeBy:      "Under 2 mi"
        }
    }

    var icon: String {
        switch self {
        case .permitted:    "checkmark.seal"
        case .stillCooking: "flame"
        case .closeBy:      "location"
        }
    }

    /// 2 miles in metres. A round number to a buyer, an awkward one here.
    private static let closeByMetres: Double = 3218.7

    func accepts(_ result: DiscoveryResult) -> Bool {
        switch self {
        case .permitted:    result.isVerified
        case .stillCooking: result.freshness == .lit
        case .closeBy:      result.distanceM <= Self.closeByMetres
        }
    }
}

extension Set where Element == FeedFilter {
    /// Every active filter must accept the kitchen. Narrowing rather than
    /// widening: two chips means "permitted *and* close", which is what
    /// selecting two things looks like it should do.
    func apply(to results: [DiscoveryResult]) -> [DiscoveryResult] {
        guard !isEmpty else { return results }
        return results.filter { r in allSatisfy { $0.accepts(r) } }
    }
}

/// The chip row under the search field.
struct FeedFilterBar: View {
    @Binding var active: Set<FeedFilter>
    /// How many kitchens each filter would leave, so a chip that empties the
    /// feed says so before it is tapped rather than after.
    var counts: (FeedFilter) -> Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedFilter.allCases) { filter in
                    let on = active.contains(filter)
                    let n = counts(filter)
                    Button {
                        if on { active.remove(filter) } else { active.insert(filter) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: filter.icon)
                                .font(LK.Typography.ui(11.5, weight: .semibold))
                            Text(filter.label)
                                .font(LK.Typography.ui(13.5, weight: .semibold))
                            // The count is the honest part: "Permitted 0" is a
                            // useful thing to know without tapping.
                            Text("\(n)")
                                .font(LK.Typography.ui(12, weight: .bold))
                                .monospacedDigit()
                                .opacity(on ? 0.75 : 0.5)
                        }
                        .foregroundStyle(on ? Color.white : LK.Palette.inkQuiet)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(on ? LK.Palette.ink : LK.Palette.chip, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(n == 0 && !on)
                    .opacity(n == 0 && !on ? 0.45 : 1)
                }

                if !active.isEmpty {
                    Button("Clear") { active.removeAll() }
                        .font(LK.Typography.ui(13, weight: .semibold))
                        .foregroundStyle(LK.Palette.action)
                        .padding(.horizontal, 4)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, LK.Metrics.feedGutter)
        }
        .scrollClipDisabled()
    }
}
