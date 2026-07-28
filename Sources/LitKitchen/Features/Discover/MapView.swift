import MapKit
import Observation
import SwiftUI

@Observable
@MainActor
final class MapViewModel {
    private let repository: any DiscoveryRepository
    private let browsing: BrowsingOrigin

    var results: [DiscoveryResult] = []
    var selected: DiscoveryResult?
    var showClosed = false
    var isLoading = false

    /// Read, never stored. The one answer lives in `BrowsingOrigin`, so the
    /// feed and the map cannot disagree about where "near you" is.
    var origin: Coordinate { browsing.coordinate }

    init(repository: any DiscoveryRepository, browsing: BrowsingOrigin) {
        self.repository = repository
        self.browsing = browsing
    }

    var visible: [DiscoveryResult] {
        showClosed ? results : results.filter(\.isCooking)
    }

    var litCount: Int { results.filter(\.isCooking).count }

    /// A region containing every visible kitchen, with padding so no pin sits
    /// under the chrome or off the edge.
    var boundingRegion: MKCoordinateRegion? {
        let points = visible.map(\.coordinate)
        guard !points.isEmpty else { return nil }

        let lats = points.map(\.latitude), lons = points.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                // 1.8× padding, with a floor so a single kitchen doesn't zoom
                // to street level and imply precision the fuzz doesn't have.
                latitudeDelta: max((maxLat - minLat) * 1.8, 0.03),
                longitudeDelta: max((maxLon - minLon) * 1.8, 0.03)
            )
        )
    }

    func load() async {
        await load(near: origin, radiusM: 12000)
    }

    /// Loads whatever is inside a given circle.
    ///
    /// The map calls this with wherever it has been dragged to, rather than the
    /// browsing origin, because a map that only ever shows one fixed circle is
    /// not a map — you pan, nothing arrives, and it looks like there is nobody
    /// out there. `radiusM` comes from the visible span, so zooming out asks
    /// for more.
    func load(near centre: Coordinate, radiusM: Int) async {
        isLoading = true
        defer { isLoading = false }
        results = (try? await repository.cookingNow(
            near: centre, radiusM: radiusM, includeClosed: true)) ?? []
    }
}

/// The neighbourhood in daylight.
///
/// A street of lit kitchens is the truest picture of what this product is, and
/// the halo around each one *is* the privacy cell: the published point is
/// grid-snapped to ~400m, so the glow is drawn at that radius rather than
/// implying a precise address. "Lights are approximate" says so out loud.
struct MapKitchenView: View {
    @State var model: MapViewModel
    /// Where we're looking. Owned by `RootView`; this screen is the one place
    /// it can be changed.
    var browsing: BrowsingOrigin
    @State private var showingPlaceSearch = false
    /// Debounces the reload while a drag is still settling.
    @State private var panTask: Task<Void, Never>?
    /// The circle the currently-loaded results were fetched for, so a small
    /// nudge does not re-query.
    @State private var loadedCentre: CLLocationCoordinate2D?
    @State private var loadedRadius: Double = 0
    /// Seeded from the launch cluster and replaced on first load, either by the
    /// bounding region of what's actually lit or by wherever `browsing` lands.
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: BrowsingOrigin.launchCluster.coordinate.latitude,
                longitude: BrowsingOrigin.launchCluster.coordinate.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.09)
        )
    )
    /// Current zoom, used to decide whether price pills fit and how tightly to
    /// cluster.
    @State private var span: Double = 0.09
    /// A tapped cluster whose members can't be separated by zooming.
    @State private var stackedCluster: MapCluster?

    /// Price pills only survive at neighbourhood zoom.
    ///
    /// The design gives every lit kitchen a price pill, which reads beautifully
    /// with four kitchens and becomes unusable with fifteen — verified in the
    /// simulator, the Covina cluster rendered "$9 each · Dumplings" and
    /// "$3 each · Tamal de" stacked on top of each other, all illegible.
    /// Zoomed out the map answers "where is anyone cooking"; only zoomed in
    /// does it need to answer "what and how much".
    private var showPills: Bool { span < 0.045 }

    /// How solid the privacy halo is, by zoom.
    ///
    /// A fixed fill cannot work at every zoom. The cell is ~400 m across, so
    /// once the viewport is only a few cells wide you are standing *inside* one
    /// — and the fill stops being a pool of light and becomes a colour cast
    /// over the entire map, which is what made the whole surface read sepia.
    /// A radial gradient does not help for the same reason: near the centre
    /// there is no falloff to see.
    ///
    /// The ring stays at full strength at every zoom. That is the part actually
    /// carrying the meaning — "somewhere in here" — and it says it just as well
    /// without flooding the streets underneath.
    private var haloFill: Double {
        switch span {
        case ..<0.012: 0.07     // inside the cell; the ring does the work
        case ..<0.030: 0.20
        default:       0.34     // neighbourhood view: a warm pool of light
        }
    }

    private var clusters: [MapCluster] {
        MapClustering.cluster(model.visible, span: span)
    }

    var body: some View {
        ZStack(alignment: .top) {
            map
            topChrome
        }
        // Keyed on the origin, so choosing a ZIP or getting a device fix
        // reloads and re-frames rather than leaving the map on the old city
        // with the new city's name in the bar.
        .task(id: browsing.coordinate) {
            browsing.start()
            await model.load()
            if let region = model.boundingRegion {
                // Frame every lit kitchen rather than a fixed span — a pin at
                // the screen edge is a pin nobody taps.
                camera = .region(region)
            } else {
                // Nobody is cooking here. Still move: the person asked to look
                // at this place, and staying put would read as a broken search.
                camera = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: browsing.coordinate.latitude,
                        longitude: browsing.coordinate.longitude
                    ),
                    span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.09)
                ))
            }
        }
        // Load what is under the map, not just what was near the origin at
        // launch. `.onEnd` rather than `.continuous`: the query only matters
        // once the drag has settled, and firing mid-gesture just burns requests
        // that are stale before they return.
        .onMapCameraChange(frequency: .onEnd) { context in
            let region = context.region
            guard needsReload(region) else { return }
            panTask?.cancel()
            panTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let r = radius(for: region)
                await model.load(
                    near: Coordinate(latitude: region.center.latitude,
                                     longitude: region.center.longitude),
                    radiusM: Int(r)
                )
                guard !Task.isCancelled else { return }
                loadedCentre = region.center
                loadedRadius = r
            }
        }
        .sheet(isPresented: $showingPlaceSearch) {
            PlaceSearchSheet(browsing: browsing)
        }
        .sheet(item: Bindable(model).selected) { result in
            MapDetailSheet(result: result, origin: browsing.coordinate)
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
                .presentationBackground(LK.Palette.ground)
        }
        // Kitchens sharing one fuzz cell publish identical points, so zooming
        // can never separate them. They get a list instead.
        .sheet(item: $stackedCluster) { cluster in
            ClusterListSheet(cluster: cluster, origin: browsing.coordinate) { result in
                stackedCluster = nil
                model.selected = result
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(LK.Palette.ground)
        }
    }

    /// Metres from the map's centre to the edge of what is on screen, padded so
    /// pins just outside the corners still arrive. Clamped at both ends: below
    /// a kilometre the query returns a street, and above 80km it starts pulling
    /// the whole state back on every pinch.
    private func radius(for region: MKCoordinateRegion) -> Double {
        let lat = region.span.latitudeDelta * 111_000
        let lon = region.span.longitudeDelta * 111_000
            * cos(region.center.latitude * .pi / 180)
        return min(max(max(lat, lon) / 2 * 1.15, 1_000), 80_000)
    }

    /// Whether the map has moved far enough to be worth another round trip.
    ///
    /// Without this, every frame of a drag queues a query and the map spends
    /// its time cancelling itself. A fifth of the current radius is roughly
    /// "you have panned a screen's worth".
    private func needsReload(_ region: MKCoordinateRegion) -> Bool {
        guard let loadedCentre else { return true }
        let r = radius(for: region)
        if abs(r - loadedRadius) / max(loadedRadius, 1) > 0.35 { return true }
        let moved = CLLocation(latitude: region.center.latitude,
                               longitude: region.center.longitude)
            .distance(from: CLLocation(latitude: loadedCentre.latitude,
                                       longitude: loadedCentre.longitude))
        return moved > loadedRadius * 0.2
    }

    private var map: some View {
        Map(position: $camera) {
            // Halos stay per-kitchen even inside a cluster: each one is a real
            // privacy cell, and merging them would misrepresent the area.
            ForEach(model.visible) { result in
                MapCircle(
                    center: result.coordinate.clLocationCoordinate,
                    radius: DiscoveryResult.fuzzRadiusM
                )
                .foregroundStyle(
                    result.isCooking
                        ? LK.Palette.heat.opacity(haloFill)
                        : LK.Palette.inkTertiary.opacity(0.10)
                )
                .stroke(
                    // A defined edge is what makes a circle read as a pool of
                    // light rather than a smudge.
                    result.isCooking ? LK.Palette.heat.opacity(0.7) : .clear,
                    lineWidth: 1.5
                )
            }

            ForEach(clusters) { cluster in
                Annotation("", coordinate: cluster.coordinate, anchor: .center) {
                    if let single = cluster.single, cluster.isSingle {
                        MapPin(
                            result: single,
                            isSelected: model.selected?.id == single.id,
                            showsPricePill: showPills || model.selected?.id == single.id
                        )
                        .onTapGesture {
                            // Raises the sheet in place. Tapping a pin must
                            // never navigate away — losing map context is the
                            // whole reason this screen exists separately.
                            model.selected = single
                        }
                    } else {
                        ClusterPin(cluster: cluster)
                            .onTapGesture {
                                if let region = MapClustering.zoomRegion(for: cluster) {
                                    withAnimation(.easeInOut(duration: 0.35)) {
                                        camera = .region(region)
                                    }
                                } else {
                                    // Same fuzz cell — no amount of zoom
                                    // separates them, so list them instead.
                                    stackedCluster = cluster
                                }
                            }
                    }
                }
                .annotationTitles(.hidden)
            }
        }
        .onMapCameraChange(frequency: .continuous) { context in
            // Only publish a meaningful change: writing `span` on every frame
            // of a pinch recomputes the clusters sixty times a second.
            //
            // The band has to stay narrow, because `span` also feeds two hard
            // thresholds — `showPills` at 0.045 and `haloFill` at 0.012/0.030 —
            // and a stale reading pushes them off by exactly its own width. At
            // 8% that was visible: a street-level map sitting just under 0.045
            // still read as "too far out for pills", so lit kitchens showed no
            // price until they were tapped. 3% keeps the thresholds honest and
            // still removes ~95% of the recomputes.
            let latest = context.region.span.latitudeDelta
            if latest < span * 0.97 || latest > span * 1.03 { span = latest }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        // Still pinned to light, and now *only* pinned — the warm multiply
        // wash that used to sit on top is gone.
        //
        // The wash existed to pull Apple's cool, green daylight tiles toward
        // the app's warm cream ground. That ground is now a cool grey, so the
        // wash had stopped reconciling anything and had become a colour cast
        // over someone else's cartography. Removing it costs nothing and the
        // map reads as a map again.
        //
        // Pinning the scheme is the open question, not the wash: in dark mode a
        // bright map on a night-blue ground is the one screen that does not
        // follow the system. The fix is a dark map with marigold pins, which is
        // a design decision rather than a cleanup.
        .environment(\.colorScheme, .light)
        // Full-bleed, including under the tab bar.
        //
        // The bar therefore adopts the map's dark scheme — white icons on this
        // tab, dark icons on the others. That was investigated as a bug and
        // deliberately left: it is what iOS does over dark content, and both
        // fixes were worse. `.toolbarColorScheme(.light, for: .tabBar)` pinned
        // the scheme but killed the blue selected-tab tint;
        // `.ignoresSafeArea(edges: [.top, .horizontal])` stopped the map above
        // the bar and left a strip of map visible below it. Revisit only with
        // a design opinion, not a code fix.
        .ignoresSafeArea()
    }

    private var topChrome: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // A Button, at last. This was a `Text` with a magnifying glass
                // beside it for months — the one search affordance in the app,
                // and it did nothing. Every user everywhere browsed Covina.
                Button {
                    showingPlaceSearch = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: browsing.isFollowingDevice ? "location.fill" : "magnifyingglass")
                        Text(browsing.isLocating
                             ? "Finding you…"
                             : "\(browsing.placeName) · lit right now")
                            .font(LK.Typography.bodyEmphasis)
                            .lineLimit(1)
                        Spacer()
                        // "in view", not "lit". The count follows the map now
                        // that panning re-queries, so beside a place name it
                        // used to read as "31 lit near Covina" while the map
                        // was over Santa Monica. The place name is the search
                        // control; the count describes what is on screen.
                        Text("\(model.litCount) in view")
                            .font(LK.Typography.ui(13.5, weight: .heavy))
                            .foregroundStyle(LK.Palette.heatInk)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Solid cream and dark ink. All of this chrome used to be
                // `.ultraThinMaterial` forced to `.dark` — white text on a
                // smoked-glass capsule, which only ever worked because the map
                // underneath was near-black. On daylight it turned into grey
                // text over park green.
                .foregroundStyle(LK.Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(LK.Palette.surface.opacity(0.96), in: Capsule())
                .overlay(Capsule().strokeBorder(LK.Palette.hairline, lineWidth: 1.5))
                .shadow(color: LK.Palette.ink.opacity(0.16), radius: 6, y: 3)
            }

            HStack {
                Text("Lights are approximate")
                    .font(LK.Typography.ui(12, weight: .semibold))
                    .foregroundStyle(LK.Palette.inkQuiet)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    // The disclaimer needs its own backing now. Bare text over
                    // a light map disappeared entirely against pale terrain —
                    // and this is the sentence that keeps the fuzzed point
                    // honest, so it cannot be the one that goes unread.
                    .background(LK.Palette.surface.opacity(0.92), in: Capsule())
                Spacer()
                Button {
                    model.showClosed.toggle()
                } label: {
                    Text(model.showClosed ? "Hide dark" : "Show dark")
                        .font(LK.Typography.ui(13.5, weight: .heavy))
                        .foregroundStyle(LK.Palette.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(LK.Palette.surface.opacity(0.96), in: Capsule())
                        .overlay(Capsule().strokeBorder(LK.Palette.hairline, lineWidth: 1.5))
                        .shadow(color: LK.Palette.ink.opacity(0.16), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, LK.Metrics.feedGutter)
        .padding(.top, 6)
    }
}

/// Lamp dot plus a warm price pill. Amber marks heat here too — the pill is a
/// label, not a control, so it stays within the rule.
private struct MapPin: View {
    let result: DiscoveryResult
    let isSelected: Bool
    var showsPricePill: Bool = true

    private var tier: FreshnessTier { result.freshness ?? .out }

    @State private var bob: CGFloat = 0

    var body: some View {
        // Zero spacing: the stem has to touch the marker, or it reads as a
        // stray arrow rather than a pin. The pill gets its own padding.
        VStack(spacing: 0) {
            if showsPricePill, let price = result.startingPrice, result.isCooking {
                Text("\(price.display) · \(shortDish)")
                    .font(LK.Typography.ui(12, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(LK.Palette.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    // Fixed cream, NOT `LK.Palette.chip`. That token is
                    // adaptive, and this surface pins its own colour scheme —
                    // so an adaptive colour here resolves against the device's
                    // setting, not the map's, and picked dark brown text on a
                    // dark brown capsule. Adaptive tokens and a hardcoded
                    // scheme never agree.
                    .background(LK.Palette.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(LK.Palette.hairline, lineWidth: 1.5))
                    .shadow(color: LK.Palette.ink.opacity(0.22), radius: 3, y: 2)
                    .padding(.bottom, 5)
            }

            ZStack {
                // The lamp glow, kept behind the marker so a lit kitchen reads
                // warm from across the map before you can make out the food.
                if result.isCooking {
                    Circle()
                        .fill(LK.Palette.heat.opacity(tier == .lit ? 0.55 : 0.3))
                        .frame(width: diameter + 26, height: diameter + 26)
                        .blur(radius: 11)
                }

                // Thick cream ring. This is the whole trick behind a marker
                // reading as a friendly *place* rather than a data point: a
                // heavy light outline separates it from whatever the map is
                // doing underneath, at any zoom, over park green or freeway
                // grey alike.
                Circle()
                    .fill(LK.Palette.surface)
                    .frame(width: diameter + 9, height: diameter + 9)
                    .shadow(color: LK.Palette.ink.opacity(0.28), radius: 5, y: 3)

                DishPhoto(
                    urlString: result.headlinePhoto,
                    size: diameter,
                    cornerRadius: diameter / 2,      // a circle
                    isLit: result.isCooking          // dark kitchens desaturate
                )
                .opacity(result.isCooking ? 1 : 0.62)

                if tier == .unconfirmed {
                    Circle()
                        .strokeBorder(LK.Palette.inkTertiary, lineWidth: 2.5)
                        .frame(width: diameter + 9, height: diameter + 9)
                }
            }
            // A slow bob, lit kitchens only. Enough to catch the eye on a still
            // map; slow enough that six of them at once is not a disco.
            .offset(y: bob)
            .animation(
                tier == .lit
                    ? .easeInOut(duration: 1.9).repeatForever(autoreverses: true)
                    : nil,
                value: bob
            )
            .onAppear { if tier == .lit { bob = -4 } }
            .animation(.spring(response: 0.3), value: isSelected)

            // The stem, so the marker points at a place instead of floating
            // over one.
            Triangle()
                .fill(LK.Palette.surface)
                .frame(width: 11, height: 7)
                .shadow(color: LK.Palette.ink.opacity(0.22), radius: 2, y: 2)
                .offset(y: -1 + bob)
        }
    }

    /// Selected pins grow; dark kitchens shrink back so the lit ones win the
    /// screen. The feed makes the same call — closed kitchens are present, not
    /// prominent.
    private var diameter: CGFloat {
        if isSelected { return 54 }
        return result.isCooking ? 44 : 32
    }

    /// A dish name short enough for a map pill, cut at a word that can stand
    /// alone.
    ///
    /// Taking the first two words produced "Tamal de" and "Pizza de" — Spanish
    /// dish names put the distinguishing word third, so a fixed word count
    /// reliably drops the part that identifies the food and leaves a
    /// preposition dangling.
    private var shortDish: String {
        guard let first = result.localizedHeadlineItems?.first else { return result.neighborhood }
        // Words that carry no meaning alone and must never end the label.
        let connectors: Set<String> = ["de", "del", "la", "el", "los", "las",
                                       "con", "y", "a", "en", "al", "of", "in", "and"]
        var words: [String] = []
        for word in first.split(separator: " ").map(String.init) {
            let candidate = words + [word]
            // Budget rather than a word count: "Pie" and "Tamal de puerco" are
            // both fine, "Chocolate chip cookie sampler" is not.
            if candidate.joined(separator: " ").count > 18, !words.isEmpty { break }
            words = candidate
        }
        while let last = words.last, connectors.contains(last.lowercased()), words.count > 1 {
            words.removeLast()
        }
        return words.isEmpty ? first : words.joined(separator: " ")
    }
}

/// Raised in place on pin tap. Light against the dark map, per the design.
private struct MapDetailSheet: View {
    let result: DiscoveryResult
    /// Where the person is, not where the map is. See
    /// `DiscoveryResult.distanceLabel(from:)`.
    let origin: Coordinate
    private var tier: FreshnessTier { result.freshness ?? .out }

    @State private var bob: CGFloat = 0

    @State private var showingDetail = false
    @State private var isFollowed = false

    private var firstName: String {
        result.displayName.familiarName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The whole card opens the kitchen, not just the button below.
            // Everything here — the photo, the name, the dishes, the price —
            // looked like a summary you could tap into and did nothing; the
            // only live target was the button, which is the one thing already
            // labelled with what it does.
            //
            // Deliberately separate from that button. This is "show me this
            // kitchen", which is the same wherever the light is. The button is
            // the *action*, and that does differ: order from a lit cook, follow
            // a dark one.
            Button {
                showingDetail = true
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    DishPhoto(urlString: result.headlinePhoto, size: 104, isLit: result.isCooking)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            LampIndicator(tier: tier, size: 8)
                            Text(result.availabilityLabel)
                                .font(LK.Typography.caps)
                                .textCase(.uppercase)
                                .tracking(0.3)
                                .foregroundStyle(tier == .unconfirmed ? LK.Palette.inkTertiary : LK.Palette.heatInk)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }

                        Text(result.displayName)
                            .font(LK.Typography.dishNameCard)
                            .foregroundStyle(LK.Palette.ink)

                        // Deduped: two menu rows can legitimately share a name —
                        // a cook with two churros variants — and rendering the raw
                        // list gives "Churros · Churros", which reads as a bug even
                        // though the data is fine.
                        if let items = result.localizedHeadlineItems.map(NSOrderedSet.init(array:))
                            .map({ $0.array.compactMap { $0 as? String } }), !items.isEmpty {
                            Text(items.prefix(2).joined(separator: " · "))
                                .font(LK.Typography.meta)
                                .foregroundStyle(LK.Palette.inkTertiary)
                                .lineLimit(1)
                        }

                        if let price = result.startingPrice {
                            Text(price.displayWithMinimum)
                                .font(LK.Typography.bodyEmphasis)
                                .monospacedDigit()
                                .foregroundStyle(LK.Palette.ink)
                        }
                    }
                    Spacer(minLength: 0)
                }

                // Deliberately vague: the exact address is not ours to show until
                // the cook confirms a claim.
                Text("Somewhere in \(result.neighborhood) · \(result.distanceLabel(from: origin))")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                }
                // Without this only the glyphs are tappable and the gaps
                // between them fall through — the same defect that made the
                // Apple sign-in button dead.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Had an empty body — `// Claim flow lands in M3.` — so it was a
            // control that looked tappable and did nothing, on the surface most
            // likely to be a buyer's first tap. Ordering lives on the kitchen
            // page, so a lit cook opens it; a dark one follows, which is what
            // the label has always promised.
            Button {
                if result.isCooking {
                    showingDetail = true
                } else {
                    Task {
                        try? await RootView.follows.setFollowing(true, cookID: result.cookID)
                        isFollowed = true
                    }
                }
            } label: {
                Text(result.isCooking
                     ? "See what \(firstName)'s making"
                     : isFollowed ? "We'll tell you when they're cooking"
                                  : "Turn their light on for me")
                    .font(LK.Typography.navBarEmphasis)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        isFollowed ? LK.Palette.heatInk : LK.Palette.action,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isFollowed)
            // The old caption said "it opens a text with them", which was untrue
            // twice over: the button did nothing, and the handoff has been
            // in-app since `migrations/043`.
        }
        .padding(LK.Metrics.screenPadding)
        .sheet(isPresented: $showingDetail) {
            CookDetailView(model: CookDetailViewModel(
                result: result, repository: RootView.discoveryRepository
            ))
        }
    }
}

/// Dark glass pill with a count, per the design. Amber is reserved for the
/// count itself — the pill is glass, not heat, so the rule holds.
private struct ClusterPin: View {
    let cluster: MapCluster

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(cluster.isLit ? LK.Palette.heat : LK.Palette.inkTertiary)
                .frame(width: 9, height: 9)
                .shadow(color: cluster.isLit ? LK.Palette.heat.opacity(0.9) : .clear, radius: 5)
            Text(cluster.isLit ? "\(cluster.litCount) lit" : "\(cluster.count)")
                .font(LK.Typography.ui(14, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(LK.Palette.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Solid cream, not `.ultraThinMaterial`. The glass capsule was built
        // for the dusk map and worked because it sat on near-black; on a
        // daylight map it picks up whatever is behind it and the count stops
        // being legible over park green.
        .background(LK.Palette.surface, in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                cluster.isLit ? LK.Palette.heat : LK.Palette.hairline,
                lineWidth: 2
            )
        }
        .shadow(color: LK.Palette.ink.opacity(0.28), radius: 5, y: 3)
        .accessibilityElement()
        .accessibilityLabel(
            cluster.isLit
                ? "\(cluster.litCount) kitchens cooking here, \(cluster.count) total"
                : "\(cluster.count) kitchens here, none cooking"
        )
        .accessibilityAddTraits(.isButton)
    }
}

/// Members of a cluster that share a fuzz cell. They publish the same point by
/// design, so a list is the only way to reach the one underneath.
private struct ClusterListSheet: View {
    let cluster: MapCluster
    let origin: Coordinate
    let onSelect: (DiscoveryResult) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("^[\(cluster.count) kitchen](inflect: true) here")
                        .font(LK.Typography.titleSecondary)
                        .foregroundStyle(LK.Palette.ink)
                    Text("They're within about a block of each other, so they share a spot on the map.")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                }
                .padding(.bottom, 2)

                ForEach(cluster.members) { result in
                    Button { onSelect(result) } label: {
                        HStack(alignment: .top, spacing: 11) {
                            DishPhoto(
                                urlString: result.headlinePhoto,
                                size: 56, cornerRadius: 12,
                                isLit: result.isCooking
                            )
                            VStack(alignment: .leading, spacing: 3) {
                                if result.isCooking {
                                    HStack(spacing: 5) {
                                        LampIndicator(tier: result.freshness ?? .out, size: 7)
                                        Text(result.availabilityLabel)
                                            .font(LK.Typography.ui(12, weight: .bold))
                                            .textCase(.uppercase)
                                            .foregroundStyle(
                                                result.freshness == .unconfirmed
                                                    ? LK.Palette.inkTertiary : LK.Palette.heatInk
                                            )
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                }
                                Text(result.localizedHeadlineItems?.first ?? result.displayName)
                                    .font(LK.Typography.dishNameRow)
                                    .foregroundStyle(LK.Palette.ink)
                                    .lineLimit(1)
                                Text("\(result.displayName) · \(result.distanceLabel(from: origin))")
                                    .font(LK.Typography.meta)
                                    .foregroundStyle(LK.Palette.inkTertiary)
                                if let price = result.startingPrice {
                                    Text(price.display)
                                        .font(LK.Typography.ui(14, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(LK.Palette.ink)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(LK.Typography.ui(13.5, weight: .semibold))
                                .foregroundStyle(LK.Palette.inkTertiary.opacity(0.6))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(LK.Metrics.screenPadding)
        }
    }
}


/// The pin's stem. A marker without one hovers over the map instead of
/// pointing at a spot on it.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
