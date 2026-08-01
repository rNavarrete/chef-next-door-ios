import SwiftUI

/// Ways to narrow the feed.
///
/// Each one answers a question a buyer actually has at six o'clock on a
/// weeknight, and all of them are computed from what the feed has already
/// loaded — so they apply instantly and cost no round trip. That also means
/// they narrow *what is on screen* rather than re-querying a wider net: the
/// radius still decides what arrived, and a filter cannot reach past it.
enum FeedFilter: String, CaseIterable, Identifiable {
    /// Confirmed in the last couple of hours, rather than lit this morning and
    /// untouched since.
    ///
    /// This is the app's whole premise expressed as a control. `isCooking`
    /// already excludes kitchens that decayed all the way out, but it still
    /// includes `unconfirmed` — somebody who turned their light on at 11am and
    /// has not opened the app since. That is the exact case the feed warns
    /// about in prose ("Ask if they're still cooking"); this lets a buyer skip
    /// it.
    ///
    /// Drawn first and never selected by default. The mock shows it filled,
    /// but switching it on at launch would silently hide every unconfirmed
    /// kitchen from a buyer who never asked for that — a filter that hides
    /// listings has to be a choice somebody made.
    case cookingNow
    /// Close enough to be there and back inside a lunch break.
    ///
    /// Reads as time rather than distance because that is the decision being
    /// made, and because ten minutes means roughly the same errand to a walker
    /// and to a driver while "under 2 mi" does not.
    case underTenMinutes
    /// Cheap enough not to think about.
    case underTenDollars
    /// Sold by the tray — the party and potluck case, and the one search is
    /// worst at, because nobody types "tray".
    case trays
    /// Only kitchens whose permit matched the county register.
    ///
    /// The one filter that changes what a buyer is trusting rather than what
    /// they are eating. Deliberately reads "Permitted" and not "Verified" —
    /// `verified` means the permit exists at this address and is unclaimed
    /// here, which is not the same as this person holding it (030), and the
    /// badge copy has never claimed otherwise.
    ///
    /// Not in the mock. Kept anyway: dropping the only trust control on the
    /// screen is a product decision, not a layout one.
    case permitted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cookingNow:      "Cooking now"
        case .underTenMinutes: "Under 10 min"
        case .underTenDollars: "Under $10"
        case .trays:           "Trays"
        case .permitted:       "Permitted"
        }
    }

    /// Ten minutes at the driving estimate. Held as a distance because that is
    /// what a result carries; `TravelTime` owns the conversion.
    private static let tenMinuteMetres: Double = 6.9 * 60 * 10
    private static let tenDollarsCents = 1_000

    func accepts(_ result: DiscoveryResult) -> Bool {
        switch self {
        case .cookingNow:      result.freshness == .lit
        case .underTenMinutes: result.distanceM <= Self.tenMinuteMetres
        case .underTenDollars: (result.minPriceCents ?? .max) <= Self.tenDollarsCents
        case .trays:           result.minPriceUnit == .tray
        case .permitted:       result.isVerified
        }
    }
}

extension Set where Element == FeedFilter {
    /// Every active filter must accept the kitchen. Narrowing rather than
    /// widening: two chips means "cheap *and* close", which is what selecting
    /// two things looks like it should do.
    func apply(to results: [DiscoveryResult]) -> [DiscoveryResult] {
        guard !isEmpty else { return results }
        return results.filter { r in allSatisfy { $0.accepts(r) } }
    }
}

/// The chip row under the search field.
///
/// Squared off rather than capsules, and unfilled until selected. A row of
/// filled pills reads as five buttons all asking to be pressed; an outline says
/// "these are available" and lets the food underneath stay the loudest thing on
/// the screen.
struct FeedFilterBar: View {
    @Binding var active: Set<FeedFilter>
    /// The unfiltered list. The bar counts against it directly rather than
    /// taking a closure, because the counts have to know what else is selected
    /// and only this view knows that.
    var results: [DiscoveryResult]

    /// What tapping this chip would actually leave you with.
    ///
    /// Measured against the *current selection*, not against the whole list.
    /// Independently each chip looked available — "Trays" read as tappable
    /// while "Cooking now" and "Under 10 min" were already on, and tapping it
    /// emptied a feed of sixty-four. A count that ignores the other chips is
    /// answering a question nobody asked.
    ///
    /// The union covers both states with one formula: for a chip that is
    /// already on, `active ∪ {filter}` is just `active`, so the number it shows
    /// is the count you are currently looking at.
    private func count(for filter: FeedFilter) -> Int {
        active.union([filter]).apply(to: results).count
    }

    /// A chip that would change nothing is not offered.
    ///
    /// "Cooking now" matches `lit`, and when every kitchen nearby is lit it is
    /// a control that visibly does something and measurably does not. Limited
    /// to the no-selection case on purpose: hiding chips *as you select* would
    /// make the row shuffle under your thumb, which is worse than an
    /// occasionally redundant chip.
    private func isNoOp(_ filter: FeedFilter) -> Bool {
        active.isEmpty && count(for: filter) == results.count
    }

    private var shown: [FeedFilter] {
        FeedFilter.allCases.filter { active.contains($0) || !isNoOp($0) }
    }

    var body: some View {
        HStack(spacing: 8) {
            chips
            // Outside the scroll view, so the way out of a filter is never the
            // thing you have to scroll to find. It sat after the fifth chip,
            // off the right edge — reachable only by swiping the row, at the
            // exact moment the feed had just emptied and the reason was not
            // visible either. Costs no width when nothing is selected.
            if !active.isEmpty {
                Button("Clear") { active.removeAll() }
                    .font(LK.Typography.ui(14, weight: .semibold))
                    .foregroundStyle(LK.Palette.action)
                    .buttonStyle(.plain)
                    .padding(.trailing, LK.Metrics.feedGutter)
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shown) { filter in
                    let on = active.contains(filter)
                    let n = count(for: filter)
                    Button {
                        if on { active.remove(filter) } else { active.insert(filter) }
                    } label: {
                        Text(filter.label)
                            .font(LK.Typography.ui(14, weight: .medium))
                            .foregroundStyle(on ? LK.Palette.inkOnAction : LK.Palette.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(on ? LK.Palette.action : .clear)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(
                                        on ? .clear : LK.Palette.ink.opacity(0.16),
                                        lineWidth: 1
                                    )
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(n == 0 && !on)
                    .opacity(n == 0 && !on ? 0.4 : 1)
                }
            }
            .padding(.leading, LK.Metrics.feedGutter)
            .padding(.trailing, 8)
        }
        // Clipped, deliberately. It was `.scrollClipDisabled()` — needed when
        // the chips were capsules with shadows, harmless while the row owned
        // the full width, and wrong the moment "Clear" moved out beside it:
        // the last chip drew straight through the button.
    }
}
