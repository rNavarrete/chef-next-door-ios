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
    /// How many kitchens `load` held back for having no photograph.
    private(set) var hiddenWithoutPhoto = 0

    /// A kitchen earns a place in the feed by having something to show.
    ///
    /// The photograph is the whole row now, and a listing without one is a
    /// grey tile among pictures of food — it reads as a broken row rather than
    /// as a cook who has not got round to it, and it drags down every real
    /// listing beside it.
    ///
    /// **This hides real cooks, not just ugly rows.** Someone who lights their
    /// burner before uploading a photo is invisible here until they add one —
    /// no warning, no placement at the bottom, simply absent. That is the
    /// intended trade for now, but it is a policy and not a layout detail, and
    /// it is the reason `hiddenWithoutPhoto` is counted rather than discarded
    /// silently. Search and the map are deliberately unaffected: a buyer
    /// looking for a specific dish should still find it.
    private static func hasPhoto(_ result: DiscoveryResult) -> Bool {
        guard let photo = result.headlinePhoto else { return false }
        return !photo.trimmingCharacters(in: .whitespaces).isEmpty
    }

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
            let shown = all.filter(Self.hasPhoto)
            hiddenWithoutPhoto = all.count - shown.count
            lit = shown.filter(\.isCooking)
            dark = shown.filter { !$0.isCooking }
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
    /// Says how the list is ordered.
    ///
    /// Too Good To Go — the closest analogue to this app, surplus food collected
    /// in a window — sorts by distance and never tells anyone, and design
    /// critiques of it name that as a specific failure: people cannot tell
    /// whether the top result is the closest, the cheapest or the newest, so
    /// they read the whole list to be sure. Three words fix it.
    var subtitleLine: String {
        let place = browsing.placeName
        guard !lit.isEmpty else { return "Nobody's cooking near \(place)" }
        return "\(lit.count) kitchen\(lit.count == 1 ? "" : "s") near \(place) · nearest first"
    }

    /// 15 minutes at the driving estimate.
    private static let fifteenMinuteMetres: Double = 6.9 * 60 * 15

    /// The count that sits beside the title — "41 within 15 min".
    ///
    /// A reachability figure rather than a total. "76 kitchens" is a boast; the
    /// number a buyer can act on is how many are close enough to bother with,
    /// and it is the same unit the second filter chip uses.
    var reachLabel: String? {
        guard !lit.isEmpty else { return nil }
        let near = lit.filter { $0.metres(from: origin) <= Self.fifteenMinuteMetres }.count
        // Everything loaded is within reach: the qualifier would be noise.
        guard near > 0 else { return nil }
        return "\(near) within 15 min"
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
                // Search no longer sits above the title.
                //
                // It was pinned at the top with the title scrolling beneath it,
                // which put a text field — the control for the one job the feed
                // is *not* doing — in the most valuable strip on the screen.
                // The title leads, search follows, and both scroll away with
                // the chips so that pulling up gets you food rather than
                // furniture.
                if hasQuery {
                    searchField
                    if !searchModel.expansion.isEmpty { expansionRow }
                    searchResults
                } else {
                    feed
                }
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
        // A recessed grey well rather than a white card with a rule round it.
        // Sunk into the page, it stops competing with the rows, which are now
        // the only white — and a field that looks like a hole is the oldest
        // signal in the toolkit for "type here".
        .background(LK.Palette.chip, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusField, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LK.Metrics.radiusField, style: .continuous)
                .strokeBorder(
                    searchFocused ? LK.Palette.action.opacity(0.5) : .clear,
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
        .padding(.bottom, 12)
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
            LazyVStack(spacing: 0) {
                if !searchModel.lit.isEmpty {
                    SectionHeader("Cooking right now · \(searchModel.lit.count)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, LK.Metrics.feedGutter)
                        .padding(.bottom, 8)
                }
                ForEach(searchModel.lit) { result in
                    row(result)
                }
                if !searchModel.dark.isEmpty {
                    SectionHeader("Closed right now · \(searchModel.dark.count)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, LK.Metrics.feedGutter)
                        .padding(.top, 18)
                        .padding(.bottom, 8)
                }
                ForEach(searchModel.dark) { result in
                    row(result)
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
                        .padding(.horizontal, LK.Metrics.feedGutter)
                        .padding(.top, 40)
                }
            }
        }
        .contentMargins(.bottom, 96, for: .scrollContent)
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
        .padding(.horizontal, LK.Metrics.feedGutter)
        .padding(.vertical, 34)
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header
                searchField
                if !model.lit.isEmpty {
                    FeedFilterBar(active: $filters) { filter in
                        model.lit.filter(filter.accepts).count
                    }
                    .padding(.bottom, 14)
                }
                if !model.lit.isEmpty, !filters.apply(to: model.lit).isEmpty {
                    stoveHeader
                }
                ForEach(filters.apply(to: model.lit)) { result in
                    row(result)
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

                // Revealed on demand. `LitKitchenRow` already renders a closed
                // kitchen correctly — desaturated photo, no lamp glow — so this
                // needs no separate card, the same way search reuses it.
                if model.showingClosed {
                    ForEach(filters.apply(to: model.dark)) { result in
                        row(result)
                    }
                }
            }
        }
        .contentMargins(.bottom, 96, for: .scrollContent)
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
        HStack(alignment: .firstTextBaseline) {
            Text("Cooking now")
                .font(LK.Typography.screenTitle)
                .foregroundStyle(LK.Palette.ink)
            Spacer(minLength: 10)
            // The count moves onto the title's baseline instead of sitting on
            // its own line underneath. It was carrying three facts — a total, a
            // place name and the sort order — and a buyer reads none of them
            // before the first dish. What survives is the one that changes a
            // decision: how many are actually near.
            if let reach = model.reachLabel {
                Text(reach)
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, LK.Metrics.feedGutter)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    /// Says what the list is and how it is ordered.
    ///
    /// Too Good To Go — the closest analogue to this app, surplus food
    /// collected in a window — sorts by distance and never tells anyone, and
    /// design critiques name that as a specific failure: people cannot tell
    /// whether the top result is the closest, the cheapest or the newest, so
    /// they read the whole list to be sure. Two words fix it, and they belong
    /// against the rows they describe rather than up in the title block.
    private var stoveHeader: some View {
        VStack(spacing: 8) {
            Text("At the stove — nearest first")
                .font(LK.Typography.caps)
                .textCase(.uppercase)
                .tracking(LK.Typography.capsTracking)
                .foregroundStyle(LK.Palette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider().overlay(LK.Palette.hairline)
        }
        .padding(.horizontal, LK.Metrics.feedGutter)
    }

    /// One row plus the rule under it.
    private func row(_ result: DiscoveryResult) -> some View {
        VStack(spacing: 0) {
            NavigationLink(value: result) {
                LitKitchenRow(result: result, origin: model.origin)
            }
            .buttonStyle(.plain)
            Divider().overlay(LK.Palette.hairline)
        }
        .padding(.horizontal, LK.Metrics.feedGutter)
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
        .padding(.horizontal, LK.Metrics.feedGutter)
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
        .padding(.horizontal, LK.Metrics.feedGutter)
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
                Text("^[\(model.darkCount) kitchen](inflect: true) closed today")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                Spacer()
                Button(model.showingClosed ? "Hide closed" : "Look anyway") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        model.showingClosed.toggle()
                    }
                }
                .font(LK.Typography.bodyEmphasis)
                .tint(LK.Palette.action)
            }
            .padding(.horizontal, LK.Metrics.feedGutter)
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
struct LitKitchenRow: View {
    let result: DiscoveryResult
    /// Where the buyer is browsing from, so the travel estimate answers "how
    /// far is this from me" rather than "from the middle of the map".
    let origin: Coordinate

    private var tier: FreshnessTier { result.freshness ?? .out }
    private var isUnconfirmed: Bool { tier == .unconfirmed }
    private var dishName: String {
        result.localizedHeadlineItems?.first ?? result.displayName
    }

    /// The photograph is the row.
    ///
    /// It was a 56pt tile — the size you use for an icon, on a feed whose
    /// entire subject is what the food looks like. At 112 × 96 it holds about
    /// three and a half times the area and is the first thing the eye lands on,
    /// which is the correct order: nobody decides to walk to a stranger's house
    /// off a price column.
    ///
    /// 4:3 rather than square, and cropped to it. Food photographs are taken
    /// landscape and a square crop takes the plate's edges off.
    private var photoWidth: CGFloat { 112 }
    private var photoHeight: CGFloat { 96 }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            DishPhoto(
                urlString: result.headlinePhoto,
                size: photoWidth,
                height: photoHeight,
                cornerRadius: 10,
                isLit: result.isCooking,
                monogramSource: dishName
            )
            .opacity(isUnconfirmed ? 0.7 : 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(dishName)
                    .font(LK.Typography.dishNameCard)
                    .foregroundStyle(isUnconfirmed ? LK.Palette.inkQuiet : LK.Palette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                kitchenLine
                travelLine
            }
            // Matches the photo, so a one-line dish and a two-line dish make
            // the same row and the price column stays on a grid. Centred
            // rather than top-aligned: three lines against a 96pt photograph
            // left a visible hole under the travel time, and the block reads
            // as set beside the picture rather than dropped in above it.
            .frame(height: photoHeight, alignment: .leading)

            Spacer(minLength: 6)
            priceColumn
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Who is cooking it, and what people said. The rating rides here rather
    /// than on its own line because it qualifies the cook, not the dish.
    private var kitchenLine: some View {
        HStack(spacing: 5) {
            Text(result.displayName)
                .font(LK.Typography.dishNameRow.weight(.regular))
                .foregroundStyle(LK.Palette.inkQuiet)
                .lineLimit(1)
                .truncationMode(.tail)
            if result.hasMeaningfulRating, let rating = result.rating {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(LK.Typography.ui(10))
                    Text(String(format: "%.1f", rating))
                        .font(LK.Typography.ui(13, weight: .medium))
                        .monospacedDigit()
                }
                .foregroundStyle(LK.Palette.inkQuiet)
                .fixedSize()
            }
            if result.isVerified { VerifiedBadge(size: 12) }
        }
    }

    /// How long to get there, then how long they have been at it.
    ///
    /// The travel time is the only coloured text in the row. It is the fact
    /// that decides whether a buyer keeps reading, and it is the one thing here
    /// the app computed rather than merely relayed.
    private var travelLine: some View {
        HStack(spacing: 5) {
            Text(result.travelTime(from: origin).label)
                .foregroundStyle(LK.Palette.action)
            // The bullet belongs to the second half, so a row with nothing
            // honest to say about duration ends after the travel time rather
            // than trailing a dot.
            if isUnconfirmed {
                // Replaces the elapsed time rather than joining it. An
                // unconfirmed kitchen may well still be open and the row must
                // not assert otherwise — but a duration beside a stale light
                // reads as a promise, so the row asks instead.
                separator
                Text("ask if still cooking")
                    .foregroundStyle(LK.Palette.action)
            } else if let cooking = cookingForLabel {
                separator
                Text(cooking)
                    .foregroundStyle(LK.Palette.inkTertiary)
            }
        }
        .font(LK.Typography.ui(13.5))
        .lineLimit(1)
    }

    private var separator: some View {
        Text("•").foregroundStyle(LK.Palette.inkTertiary.opacity(0.5))
    }

    /// "on 44 min", "on 2 hr" — how long the light has been on.
    ///
    /// Elapsed, where every other surface in the app shows an absolute clock
    /// time. The trade is deliberate and narrow to this row: in a list you are
    /// scanning for freshness, and "on 20 min" answers that without arithmetic
    /// while "since 9:20 pm" makes you do it against a clock you have to find.
    /// The kitchen page still leads with the absolute time, which is the one
    /// that stays true if you read it an hour later.
    ///
    /// Computed at render rather than stored, so a feed left open does not go
    /// quietly wrong — and the feed reloads on appearance and on pull anyway.
    private var cookingForLabel: String? {
        guard let openedAt = result.openedAt, result.isCooking else { return nil }
        let minutes = Int(Date().timeIntervalSince(openedAt) / 60)
        guard minutes >= 1 else { return "just now" }
        if minutes < 60 { return "on \(minutes) min" }
        // Past half a day the number stops being a freshness signal and starts
        // being a bug report: the dev seed re-confirms its sessions on a cron,
        // so kitchens opened on Tuesday were reading "on 90 hr" in the feed. A
        // real cook who leaves their light on overnight would produce the same
        // line. Nothing honest can be said about a duration that long, so the
        // row says nothing and lets the travel time stand on its own.
        guard minutes < 12 * 60 else { return nil }
        return "on \(minutes / 60) hr"
    }

    /// Price right-aligned in its own column, so the figures form a line a
    /// buyer can run an eye down. This is the comparison the feed exists to
    /// support and it does not survive a price that starts wherever the dish
    /// name happened to end.
    @ViewBuilder
    private var priceColumn: some View {
        if let price = result.startingPrice {
            VStack(alignment: .trailing, spacing: 1) {
                Text(price.figure)
                    .font(LK.Typography.titleSecondary)
                    .monospacedDigit()
                    .foregroundStyle(isUnconfirmed ? LK.Palette.inkQuiet : LK.Palette.ink)
                Text(unitLine(price))
                    .font(LK.Typography.ui(12))
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .lineLimit(1)
            }
            .fixedSize()
        }
    }

    /// "each", or "each · min 3" when a minimum applies. The qualifier belongs
    /// under the figure rather than beside it — it is a condition on the price,
    /// and reading it as part of the number is how somebody turns up expecting
    /// to buy one tamale.
    private func unitLine(_ price: Price) -> String {
        price.qualifier.isEmpty
            ? price.unitLabel
            : "\(price.unitLabel) \(price.qualifier)"
    }

    private var metaText: String {
        var parts = [result.displayName, result.distanceLabel]
        if let since = result.sinceLabel { parts.append(since) }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        let state = isUnconfirmed ? "unconfirmed, ask if they're still cooking" : "cooking"
        let price = result.startingPrice.map { ", \($0.displayWithMinimum)" } ?? ""
        let travel = result.travelTime(from: origin).label
        return "\(dishName), \(state), \(travel), \(metaText)\(price)"
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
