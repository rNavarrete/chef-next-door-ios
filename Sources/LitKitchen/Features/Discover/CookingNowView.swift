import Observation
import SwiftUI

@Observable
@MainActor
final class CookingNowViewModel {
    private let repository: any DiscoveryRepository
    private let browsing: BrowsingOrigin

    var lit: [DiscoveryResult] = []
    /// Kitchens that aren't cooking. Kept, not counted: `load` already asks the
    /// repository for closed kitchens, and this used to throw the rows away and
    /// keep only the total — which left "Look anyway" with nothing to reveal.
    var dark: [DiscoveryResult] = []
    var showingClosed = false
    var isLoading = false
    var errorMessage: String?

    var darkCount: Int { dark.count }

    /// Read, never stored. The one answer lives in `BrowsingOrigin`, so the
    /// feed and the map cannot disagree about where "near you" is.
    var origin: Coordinate { browsing.coordinate }

    init(repository: any DiscoveryRepository, browsing: BrowsingOrigin) {
        self.browsing = browsing
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await repository.cookingNow(near: origin, radiusM: DiscoveryRadius.defaultM, includeClosed: true)
            // The feed runs from `.task(id: browsing.coordinate)`, which
            // cancels and restarts every time the origin settles during launch.
            // Without this guard a superseded load could return *after* its
            // replacement and overwrite good rows with its own — an empty feed
            // with no error, because nothing failed. Seen on launch: 72
            // kitchens were lit and the app said none were, while search from
            // the same origin found them, because `SearchViewModel` has always
            // had this line and this one did not.
            guard !Task.isCancelled else { return }
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
        lit.isEmpty ? "Nobody's cooking" : "\(lit.count) cooking now"
    }

    var subtitle: String {
        lit.isEmpty
            ? "No kitchens cooking near you right now"
            : "Kitchens cooking near you right now"
    }

    /// The count, folded into the subtitle now that the title is fixed text.
    ///
    /// Pluralised in Swift, not with `^[…](inflect:)` markup. That syntax is
    /// only parsed by the `LocalizedStringKey` overload of `Text`; handed a
    /// `String` variable it renders the markup verbatim on screen, which is
    /// exactly what it did here.
    /// The place name comes from `browsing`, not a literal. It said "near
    /// Covina" to everyone, including — caught in the simulator — someone who
    /// had just searched Long Beach and was looking at Long Beach results.
    var subtitleLine: String {
        let place = browsing.placeName
        guard !lit.isEmpty else { return "Nobody's cooking near \(place)" }
        return "\(lit.count) kitchen\(lit.count == 1 ? "" : "s") cooking near \(place)"
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
    /// Read-only here; the map owns changing it.
    var browsing: BrowsingOrigin
    @FocusState private var searchFocused: Bool
    /// Narrows what is shown, never what is fetched.
    @State private var filters: Set<FeedFilter> = []
    @State private var showingPlaceSearch = false

    private var hasQuery: Bool {
        !searchModel.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                if !hasQuery, !model.lit.isEmpty {
                    FeedFilterBar(active: $filters) { filter in
                        model.lit.filter(filter.accepts).count
                    }
                    .padding(.bottom, 10)
                }
                if hasQuery, !searchModel.expansion.isEmpty { expansionRow }
                if hasQuery { searchResults } else { feed }
            }
            .background(LK.Palette.ground)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        // Back to a field. The full-radius capsule with a 2pt ring was the
        // loudest control in the app — a search box shouldn't outrank the food
        // under it. Focus is a 1pt `action` border plus a soft halo, the same
        // treatment every other field gets.
        .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusField, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LK.Metrics.radiusField, style: .continuous)
                .strokeBorder(
                    searchFocused ? LK.Palette.action.opacity(0.5) : LK.Palette.hairline,
                    lineWidth: 1
                )
        }
        .overlay {
            if searchFocused {
                RoundedRectangle(cornerRadius: LK.Metrics.radiusField, style: .continuous)
                    .strokeBorder(LK.Palette.action.opacity(0.10), lineWidth: 3)
                    .padding(-2)
            }
        }
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
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                ForEach(searchModel.expansion, id: \.self) { term in
                    Text(term)
                        .font(LK.Typography.ui(14))
                        .foregroundStyle(LK.Palette.inkQuiet)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(LK.Palette.chip, in: Capsule())
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
                    // Says how far it looked. "Nothing nearby" is unfalsifiable
                    // — it reads as "this dish does not exist here" when it
                    // actually means "not inside a radius we never named", and
                    // the buyer has no way to tell those apart or to react.
                    Text("Nothing matching that within \(DiscoveryRadius.defaultMiles) miles.")
                        .font(LK.Typography.body)
                        .foregroundStyle(LK.Palette.inkQuiet)
                        .multilineTextAlignment(.center)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, LK.Metrics.feedGutter)
        }
        .contentMargins(.bottom, 28, for: .scrollContent)
    }

    /// Filtered the feed to nothing. Deliberately distinct from "nobody is
    /// cooking": one is a fact about the neighbourhood, the other is a
    /// consequence of a tap, and the way out of the second is one more tap.
    private var filteredEmptyState: some View {
        VStack(spacing: 8) {
            Text("Nothing matches those filters")
                .font(LK.Typography.bodyEmphasis)
                .foregroundStyle(LK.Palette.ink)
            Text("\(model.lit.count) kitchen\(model.lit.count == 1 ? " is" : "s are") cooking nearby.")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)
            Button("Clear filters") { filters.removeAll() }
                .font(LK.Typography.navBarEmphasis)
                .foregroundStyle(LK.Palette.action)
                .padding(.top, 2)
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                header
                ForEach(filters.apply(to: model.lit)) { result in
                    NavigationLink(value: result) {
                        LitKitchenCard(result: result)
                    }
                    .buttonStyle(.plain)
                }
                // Filtered everything away: distinct from having no
                // kitchens at all, and the way out is a tap.
                if !model.lit.isEmpty, filters.apply(to: model.lit).isEmpty {
                    filteredEmptyState
                }
                // A failed load and an empty neighbourhood are not the same
                // thing, and until now they looked identical: `errorMessage`
                // was assigned in `load()` and rendered nowhere, so a request
                // that fell over left "Nobody's cooking" on screen. Seen once
                // on a cold launch — eighteen kitchens were lit and the app
                // said none were. The person reading it has no way to tell a
                // quiet Tuesday from a dropped connection, and only one of
                // those is worth pulling to refresh.
                if model.lit.isEmpty && !model.isLoading, let message = model.errorMessage {
                    loadFailedState(message)
                } else if model.lit.isEmpty && !model.isLoading {
                    emptyState
                }
                darkRow

                // Revealed on demand. `LitKitchenCard` already renders a closed
                // kitchen correctly — desaturated photo, no lamp glow — so this
                // needs no separate card, the same way search reuses it.
                if model.showingClosed {
                    ForEach(filters.apply(to: model.dark)) { result in
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
        // Keyed on the origin: picking a ZIP on the map has to move the
        // feed too, or the two tabs describe different cities.
        .sheet(isPresented: $showingPlaceSearch) {
            PlaceSearchSheet(browsing: browsing)
        }
        .task(id: browsing.coordinate) {
            browsing.start()
            await model.load()
        }
        .refreshable { await model.load() }
    }

    /// One header, not two.
    ///
    /// A search field and a display title stacked above the first card cost
    /// roughly 150pt before any food appeared. The count moves into the
    /// subtitle, where it is still the first fact but no longer a second
    /// headline competing with the first.
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Cooking now")
                .font(LK.Typography.screenTitle)
                .foregroundStyle(LK.Palette.ink)
            Text(model.subtitleLine)
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    /// The moment the app has nothing to show is exactly when "look somewhere
    /// else" is worth knowing — which makes this the trigger, rather than a
    /// tip fired on first launch at somebody who has not hit the problem yet.
    /// It was a dead end before: a statement of fact with nothing to do about
    /// it, on the screen that opens the app.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Nobody's cooking near you right now.")
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.inkQuiet)
                .multilineTextAlignment(.center)
            Text("Most cooks are in the San Gabriel Valley today. Try another neighbourhood, or follow a cook and we'll tell you when they start.")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)

            Button {
                showingPlaceSearch = true
            } label: {
                Text("Search another area")
                    .font(LK.Typography.navBarEmphasis)
                    .foregroundStyle(LK.Palette.action)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: LK.Metrics.radiusButton, style: .continuous)
                            .strokeBorder(LK.Palette.action.opacity(0.35), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.vertical, 40)
    }

    /// Deliberately not `emptyState` with different words. That one is a fact
    /// about the neighbourhood and offers a way to hear about the next kitchen;
    /// this one is a fact about the request, and the way out is to try again.
    private func loadFailedState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.inkQuiet)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await model.load() }
            }
            .font(LK.Typography.bodyEmphasis)
            .foregroundStyle(LK.Palette.action)
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
                .font(LK.Typography.bodyEmphasis)
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
/// The one card.
///
/// Four card treatments collapsed into this. Deleted from the version that
/// shipped: the tinted wrapper, the 2pt amber border, the amber glow, the amber
/// price pill and its border, the white rim on the thumbnail, and the caps
/// `COOKING · SINCE 11:51 AM` line.
///
/// The caps line is the one worth explaining. It was the first thing on every
/// card and it read identically on all of them — the dot plus `since 11:51` in
/// the meta line says the same thing in a third of the space, and the dish name
/// gets to lead. The dish name is the only line that differs row to row, which
/// is the definition of what should be biggest.
///
/// Ordering is unchanged and still deliberate: availability, then dish, then
/// cook. It is now carried by position and weight rather than by colour.
struct LitKitchenCard: View {
    let result: DiscoveryResult

    private var tier: FreshnessTier { result.freshness ?? .out }
    private var isUnconfirmed: Bool { tier == .unconfirmed }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DishPhoto(
                urlString: result.headlinePhoto,
                size: 86,
                cornerRadius: LK.Metrics.radiusInner,
                isLit: result.isCooking
            )
            // Unconfirmed dims the food rather than hiding it — the kitchen may
            // well still be open, and the card must not assert otherwise.
            .opacity(isUnconfirmed ? 0.7 : 1)

            VStack(alignment: .leading, spacing: 5) {
                Text(result.localizedHeadlineItems?.first ?? result.displayName)
                    .font(LK.Typography.dishNameCard)
                    .tracking(-0.475)          // -0.025em at 19pt
                    .lineSpacing(19 * 0.15)
                    .foregroundStyle(isUnconfirmed ? LK.Palette.inkQuiet : LK.Palette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                metaLine
                priceLine
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous)
                .strokeBorder(LK.Palette.hairline, lineWidth: LK.Metrics.cardBorderWidth)
        }
        // No elevation when unconfirmed: a card that may be stale should not
        // sit forward of the ones that are certainly live.
        .modifier(ConditionalCardShadow(enabled: !isUnconfirmed))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            LampDot(tier: tier)
            Text(metaText)
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if result.isVerified { VerifiedBadge(size: 13) }
        }
    }

    private var metaText: String {
        var parts = [result.displayName, result.distanceLabel]
        if let since = result.sinceLabel { parts.append(since) }
        return parts.joined(separator: " · ")
    }

    /// A price, or — when the kitchen is unconfirmed — the thing to do about it.
    @ViewBuilder
    private var priceLine: some View {
        if isUnconfirmed {
            // There is something to *do* here, so this line is an affordance
            // rather than a fact. A price on an unconfirmed kitchen invites a
            // drive to a door that may be shut.
            Text("Ask if they're still cooking")
                .font(LK.Typography.bodyEmphasis)
                .foregroundStyle(LK.Palette.action)
        } else if let price = result.startingPrice {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(price.figure)
                    .font(LK.Typography.dishNameCard)
                    .monospacedDigit()
                    .foregroundStyle(LK.Palette.ink)
                Text(price.unitLabel)
                    .font(LK.Typography.ui(14, weight: .semibold))
                    .foregroundStyle(LK.Palette.ink)
                if !price.qualifier.isEmpty {
                    Text(price.qualifier)
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    private var accessibilityText: String {
        let dish = result.localizedHeadlineItems?.first ?? result.displayName
        let state = isUnconfirmed ? "unconfirmed, ask if they're still cooking" : "cooking"
        let price = result.startingPrice.map { ", \($0.displayWithMinimum)" } ?? ""
        return "\(dish), \(state), \(metaText)\(price)"
    }
}

/// Filled when the kitchen is certainly live; a hollow ring when it is not.
///
/// The shape carries the state, not just the colour — the difference survives
/// greyscale, and the dot is 7pt, which is below the size at which a colour
/// difference alone is reliable.
private struct LampDot: View {
    let tier: FreshnessTier

    var body: some View {
        Group {
            if tier == .unconfirmed {
                Circle().strokeBorder(LK.Palette.inkTertiary, lineWidth: 1.5)
            } else {
                Circle().fill(LK.Palette.heat)
            }
        }
        .frame(width: LK.Lamp.dotSize, height: LK.Lamp.dotSize)
    }
}

private struct ConditionalCardShadow: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.lkCardShadow() } else { content }
    }
}
