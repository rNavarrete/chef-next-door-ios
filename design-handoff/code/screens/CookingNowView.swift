import Observation
import SwiftUI

@Observable
@MainActor
final class CookingNowViewModel {
    private let repository: any DiscoveryRepository

    var lit: [DiscoveryResult] = []
    /// Kitchens that aren't cooking. Kept, not counted: `load` already asks the
    /// repository for closed kitchens, and this used to throw the rows away and
    /// keep only the total — which left "Look anyway" with nothing to reveal.
    var dark: [DiscoveryResult] = []
    var showingClosed = false
    var isLoading = false
    var errorMessage: String?

    var darkCount: Int { dark.count }

    /// Covina, the launch cluster. Real location wiring is a later step; the
    /// repository takes a coordinate either way.
    var origin = Coordinate(latitude: 34.0900, longitude: -117.8903)

    init(repository: any DiscoveryRepository) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await repository.cookingNow(near: origin, radiusM: 12000, includeClosed: true)
            lit = all.filter(\.isCooking)
            dark = all.filter { !$0.isCooking }
            errorMessage = nil
        } catch {
            errorMessage = UserFacingError.message(for: error, fallback: "Couldn't load who's cooking. Pull to refresh.")
        }
    }

    /// The feed counts *lit kitchens*, not listings — "6 lit up", not
    /// "6 dishes available".
    var headline: String {
        lit.isEmpty ? "Nobody's cooking" : "\(lit.count) lit up"
    }

    var subtitle: String {
        lit.isEmpty
            ? "No kitchens cooking near you right now"
            : "Kitchens cooking near you right now"
    }
}

struct CookingNowView: View {
    @State var model: CookingNowViewModel
    /// Search lives here rather than in its own tab. The results *are* the
    /// feed — same cards, same lit/dark split — so a separate tab spent a fifth
    /// of the bar on a text field and made "who's cooking" and "who's cooking
    /// tamales" feel like different places. `RootView` had already flagged the
    /// tab set as unsettled.
    @State var searchModel: SearchViewModel
    @FocusState private var searchFocused: Bool

    private var hasQuery: Bool {
        !searchModel.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                if hasQuery, !searchModel.expansion.isEmpty { expansionRow }
                if hasQuery { searchResults } else { feed }
            }
            .background(LK.Palette.paper)
            .navigationDestination(for: DiscoveryResult.self) { result in
                CookDetailView(model: CookDetailViewModel(
                    result: result,
                    repository: RootView.discoveryRepository
                ))
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(LK.Palette.inkTertiary)
            TextField("tamales, birria, pan dulce…", text: Bindable(searchModel).query)
                .font(LK.Typography.body)
                .focused($searchFocused)
                .autocorrectionDisabled()          // same reason as the menu builder
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !searchModel.query.isEmpty {
                Button { searchModel.query = ""; searchFocused = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(LK.Palette.inkTertiary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // A capsule, and a 2pt edge. The square field with a hairline was the
        // last thing on the screen still shaped like a form control, and it
        // sat directly above cards that are now round and heavy-edged.
        .background(LK.Palette.surface, in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                searchFocused ? LK.Palette.action : Color(hex: 0xE6DAC4),
                lineWidth: 2
            )
        }
        .shadow(color: Color(hex: 0x4A3411).opacity(0.07), radius: 4, y: 2)
        .padding(.horizontal, LK.Metrics.feedGutter)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// The answer to mixed-language input, made visible. Carried over from the
    /// old Search tab unchanged — a buyer who typed "pork tamale" can still see
    /// *why* a listing called "Tamal de puerco" came back, which is the whole
    /// bilingual thesis on screen.
    private var expansionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("también:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LK.Palette.inkTertiary)
                ForEach(searchModel.expansion, id: \.self) { term in
                    Text(term)
                        .font(.system(size: 13))
                        .foregroundStyle(LK.Palette.inkSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(LK.Palette.chipNeutral, in: Capsule())
                }
            }
            .padding(.horizontal, LK.Metrics.feedGutter)
        }
        .padding(.bottom, 8)
    }

    private var searchResults: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if !searchModel.lit.isEmpty {
                    SectionHeader("Cooking right now · \(searchModel.lit.count)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(searchModel.lit) { result in
                    NavigationLink(value: result) { LitKitchenCard(result: result) }
                        .buttonStyle(.plain)
                }
                if !searchModel.dark.isEmpty {
                    SectionHeader("Dark right now · \(searchModel.dark.count)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                ForEach(searchModel.dark) { result in
                    NavigationLink(value: result) { LitKitchenCard(result: result) }
                        .buttonStyle(.plain)
                }
                if searchModel.lit.isEmpty && searchModel.dark.isEmpty && searchModel.hasSearched && !searchModel.isSearching {
                    Text("Nothing matching that nearby.")
                        .font(LK.Typography.body)
                        .foregroundStyle(LK.Palette.inkSecondary)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, LK.Metrics.feedGutter)
        }
        .contentMargins(.bottom, 28, for: .scrollContent)
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                header
                ForEach(model.lit) { result in
                    NavigationLink(value: result) {
                        LitKitchenCard(result: result)
                    }
                    .buttonStyle(.plain)
                }
                if model.lit.isEmpty && !model.isLoading {
                    emptyState
                }
                darkRow

                // Revealed on demand. `LitKitchenCard` already renders a closed
                // kitchen correctly — desaturated photo, no lamp glow — so this
                // needs no separate card, the same way search reuses it.
                if model.showingClosed {
                    ForEach(model.dark) { result in
                        NavigationLink(value: result) {
                            LitKitchenCard(result: result)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, LK.Metrics.feedGutter)
        }
        .contentMargins(.bottom, 28, for: .scrollContent)
        .overlay(alignment: .top) { headerWash }
        // Content scrolls under the status bar, and dish names were colliding
        // with the clock — verified in the simulator with a full feed. A
        // frosted strip keeps the time legible without a hard bar that would
        // fight the amber wash.
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: proxy.safeAreaInsets.top)
                    .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    /// Amber wash behind the header — as if the light were coming from the list
    /// itself.
    ///
    /// Vertical, and it must stay vertical. This ran `.topLeading → .bottom`,
    /// whose axis points down-and-right: at the bottom-*left* corner the
    /// gradient is only about a third travelled, so it was still near-full
    /// amber when the 150pt frame cut it off. That left a hard horizontal seam
    /// down the left side of the feed. Any diagonal endpoint has the same
    /// problem — the corner nearest the start is always the one that gets
    /// clipped mid-fade.
    private var headerWash: some View {
        LinearGradient(
            stops: [
                .init(color: LK.Palette.lamp.opacity(0.17), location: 0),
                .init(color: LK.Palette.lamp.opacity(0.05), location: 0.55),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 190)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The numeral carries the lamp colour while "lit up" stays ink.
            // Amber is reserved for heat everywhere else in the app, and a
            // count of lit kitchens is heat — it is the literal thing the
            // colour means, so this is the rule being followed rather than
            // bent. The empty state has no number and stays ink throughout.
            if model.lit.isEmpty {
                Text(model.headline)
                    .font(LK.Typography.screenTitle)
                    .foregroundStyle(LK.Palette.ink)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(model.lit.count)")
                        .font(LK.Typography.screenTitle)
                        .foregroundStyle(LK.Palette.lampInk)
                    Text(" lit up")
                        .font(LK.Typography.screenTitle)
                        .foregroundStyle(LK.Palette.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(model.headline)
            }
            Text(model.subtitle)
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No kitchens are lit right now.")
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.inkSecondary)
            Text("Follow a cook and we'll push you the moment one lights up.")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private var darkRow: some View {
        // `if`, not `.opacity(0)`. A zero-opacity row still takes hits, so the
        // invisible version of this button was tappable — harmless while it did
        // nothing, and a way to silently reveal an empty list now that it does.
        if model.darkCount > 0 {
            HStack {
                // Inflected, not "1 kitchens". Uses the automatic grammar
                // agreement so it localises rather than hardcoding an English
                // plural rule.
                Text("^[\(model.darkCount) kitchen](inflect: true) dark today")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                Spacer()
                Button(model.showingClosed ? "Hide dark" : "Look anyway") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        model.showingClosed.toggle()
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .tint(LK.Palette.action)
            }
            .padding(.vertical, 10)
        }
    }
}

/// The card. Appears in the feed, in search, and on the map sheet.
///
/// Ordering is deliberate and inverts COOK Connect's: availability is the
/// loudest element, then the dish, then the price — cook name and rating come
/// after. Theirs leads with cook and rating (`DESIGN_RESEARCH.md` §2).
struct LitKitchenCard: View {
    let result: DiscoveryResult

    private var tier: FreshnessTier { result.freshness ?? .out }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DishPhoto(
                urlString: result.headlinePhoto,
                size: 98,
                // A generous squircle rather than the standard thumb radius.
                // Round corners are most of what separates "friendly" from
                // "database row", and at 108pt there is room for it without
                // eating into the food.
                cornerRadius: 24,
                isLit: result.isCooking
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color(hex: 0xFFFBF0), lineWidth: 3)
            }
            .shadow(color: Color(hex: 0x4A3411).opacity(0.13), radius: 5, y: 3)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    LampIndicator(tier: tier, size: 8)
                    // Availability is the most important text on the card, so
                    // it shrinks rather than truncates. "UNCONFIRMED SINCE"
                    // clipped to "UNCONFIRME…" at the default settings, which
                    // hid the one word a buyer most needs to read.
                    Text(result.availabilityLabel)
                        .font(LK.Typography.availabilityLabel)
                        .textCase(.uppercase)
                        .tracking(0.3)
                        .foregroundStyle(tier == .unconfirmed ? LK.Palette.inkTertiary : LK.Palette.lampInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Two lines: real dish names run long in Spanish
                // ("Tamal de rajas con queso"), and truncating the dish is
                // truncating the reason someone opened the app.
                Text(result.headlineItems?.first ?? result.displayName)
                    .font(LK.Typography.dishNameCard)
                    .foregroundStyle(LK.Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                // The seal rides with the name, not on a line of its own. It
                // has to read at a glance in a scrolling feed, and the row it
                // used to occupy said "Permitted home kitchen" under every
                // verified cook — a whole line spent restating the badge.
                HStack(spacing: 4) {
                    Text(result.displayName)
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .lineLimit(1)
                    if result.isVerified { VerifiedBadge(size: 12) }
                    Text("· \(result.distanceLabel) · \(result.neighborhood)")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    result.isVerified
                    ? "\(result.displayName), permit verified, \(result.distanceLabel), \(result.neighborhood)"
                    : "\(result.displayName), \(result.distanceLabel), \(result.neighborhood)"
                )

                if let price = result.startingPrice {
                    // The same warm pill the map pins carry, so a price reads
                    // as the same object in both places.
                    Text(price.displayWithMinimum)
                        .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: 0x5A3900))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(LK.Palette.lampTint, in: Capsule())
                        .overlay(Capsule().strokeBorder(LK.Palette.lamp.opacity(0.35), lineWidth: 1.5))
                        .padding(.top, 2)
                }

            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous))
        .overlay {
            // Glow intensity is driven by the decay tier, so a dimming kitchen
            // is visibly dimmer without a single word changing.
            //
            // Weight went 1 → 2. A hairline is the convention for a dense list
            // where the border is a separator; here it is the edge of a card
            // that is meant to feel like an object you could pick up, and a
            // hairline reads as a table rule instead.
            RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous)
                .strokeBorder(
                    tier == .unconfirmed ? LK.Palette.hairline : LK.Palette.lamp.opacity(LK.Glow.forTier(tier).ringOpacity),
                    lineWidth: tier == .unconfirmed ? 1 : 2
                )
        }
        .shadow(
            color: LK.Palette.lamp.opacity(LK.Glow.forTier(tier).opacity),
            radius: LK.Glow.forTier(tier).radius,
            y: 6
        )
        .accessibilityElement(children: .combine)
    }

}
