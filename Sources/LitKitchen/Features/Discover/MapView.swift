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
/// implying a precise address. "Locations are approximate" says so out loud.
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
    @State private var showingLocationDenied = false

    /// Back to me.
    ///
    /// The map re-queries wherever it is dragged, which is the right behaviour
    /// and leaves no way home: pan across to see what is cooking in Pasadena
    /// and the only route back was to close the tab or search your own city by
    /// name. Every map app has this control and people look for it.
    ///
    /// It does two things, because "recentre" and "recalculate" are different
    /// asks and the button is the answer to both. The camera moves immediately
    /// to the origin we already have — that alone fixes the panned-away case,
    /// and it has to be unconditional, because if the fix comes back identical
    /// then `coordinate` never changes and nothing else would move the map.
    /// `recenter()` then asks the device for a fresh fix, and the `.task(id:)`
    /// above re-frames if a better answer arrives.
    private var recenterButton: some View {
        Button {
            guard browsing.canUseDeviceLocation else {
                showingLocationDenied = true
                return
            }
            withAnimation(.easeInOut(duration: 0.4)) {
                camera = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: browsing.coordinate.latitude,
                        longitude: browsing.coordinate.longitude
                    ),
                    span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.09)
                ))
            }
            browsing.recenter()
        } label: {
            Group {
                if browsing.isLocating {
                    ProgressView().tint(LK.Palette.ink)
                } else {
                    Image(systemName: browsing.canUseDeviceLocation
                          ? (browsing.isFollowingDevice ? "location.fill" : "location")
                          : "location.slash")
                        .font(LK.Typography.ui(17, weight: .semibold))
                        .foregroundStyle(LK.Palette.ink)
                }
            }
            .frame(width: LK.Metrics.minHitTarget, height: LK.Metrics.minHitTarget)
            .background(LK.Palette.surface.opacity(0.96), in: Circle())
            .overlay(Circle().strokeBorder(LK.Palette.hairline, lineWidth: 1.5))
            .shadow(color: LK.Palette.ink.opacity(0.16), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(browsing.isLocating)
        .padding(.trailing, LK.Metrics.feedGutter)
        // Clears the tab bar. The map runs full-bleed underneath it, so the
        // safe area alone leaves the button under the glass.
        .padding(.bottom, 22)
        .accessibilityLabel(browsing.isFollowingDevice
                            ? "Recentre on my location"
                            : "Use my location")
    }

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
        case ..<0.012: 0.05     // inside the cell; the ring does the work
        case ..<0.030: 0.13
        default:       0.22     // enough to read as an area, not a spotlight
        }
    }

    /// What the map is actually drawing right now.
    ///
    /// Held in state rather than computed in `body`. As a computed property
    /// this re-clustered every single render — bucketing every result into a
    /// dictionary keyed by an interpolated string, sorting each bucket, then
    /// sorting the whole map — and `body` re-runs on every camera publication.
    /// The work was proportional to results × frames, which is exactly the
    /// shape that falls apart when the kitchen count grows.
    ///
    /// Now it is proportional to results × *meaningful changes*: a new load, a
    /// zoom that crossed the throttle band, or the closed toggle.
    @State private var clusters: [MapCluster] = []
    /// The last region we culled against, padded. Nil until the first camera
    /// publication, which is why `rebuild` treats nil as "draw everything".
    @State private var cullRegion: MKCoordinateRegion?

    /// Recompute clusters and drop anything off screen.
    ///
    /// Culling matters more than clustering. The loader pulls a radius sized to
    /// the viewport plus 15%, but after a zoom *out* the results from the
    /// previous, wider query are all still in `results` — so the map was
    /// handing MapKit annotations for kitchens hundreds of miles away, every
    /// one of them a full custom `MapPin` with a photograph in it. Apple's
    /// guidance for this is blunt: only render what is in the current region.
    ///
    /// Padded to 1.6× the viewport so a pin just past the edge is already on
    /// screen when a drag reaches it, rather than popping in.
    private func rebuild() {
        let built = MapClustering.cluster(model.visible, span: span)
        guard let region = cullRegion else {
            clusters = built
            return
        }
        let padLat = region.span.latitudeDelta * 0.8
        let padLon = region.span.longitudeDelta * 0.8
        clusters = built.filter { cluster in
            abs(cluster.coordinate.latitude - region.center.latitude) <= padLat
                && abs(cluster.coordinate.longitude - region.center.longitude) <= padLon
        }
    }

    /// Halos are the privacy disclosure — the published point is snapped to a
    /// ~400m cell and the circle is that cell — so they are never dropped for
    /// speed alone. They are dropped when they cannot be *read*.
    ///
    /// Zoomed out past a city the cell is sub-pixel: seventy translucent
    /// overlays that render as nothing. MapKit re-evaluates every overlay on
    /// every change and transparency forces it to redisplay more than once, so
    /// they were among the most expensive things on screen while being
    /// literally invisible. "Locations are approximate" carries the claim at
    /// that zoom; the circles carry it once they are big enough to see.
    private var showHalos: Bool { span < 0.35 }

    var body: some View {
        ZStack(alignment: .top) {
            map
            topChrome
        }
        .overlay(alignment: .bottomTrailing) { recenterButton }
        .alert("Location is off for Chef Next Door", isPresented: $showingLocationDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Turn it on in Settings to see who's cooking near you, or search for a place instead.")
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
            // privacy cell, and merging them would misrepresent the area. But
            // only for kitchens that survived the cull, and only at a zoom
            // where the cell is bigger than a pixel — this used to iterate
            // every loaded result regardless of either.
            ForEach(showHalos ? clusters.flatMap(\.members) : []) { result in
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
                            showsPricePill: model.selected?.id == single.id,
                            showsCookingGlow: model.showClosed
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
            let region = context.region

            // Zoom changed enough to re-cluster and re-check the thresholds.
            if latest < span * 0.97 || latest > span * 1.03 {
                span = latest
                cullRegion = region
                rebuild()
                return
            }

            // Panned far enough that the cull is stale. Compared against the
            // *padded* margin, so this fires roughly once per screen of travel
            // rather than once per frame — without it, culling would strand
            // pins at the edge of a long drag until the pan-end reload landed.
            if let culled = cullRegion {
                let movedLat = abs(region.center.latitude - culled.center.latitude)
                let movedLon = abs(region.center.longitude - culled.center.longitude)
                guard movedLat > culled.span.latitudeDelta * 0.4
                        || movedLon > culled.span.longitudeDelta * 0.4
                else { return }
            }
            cullRegion = region
            rebuild()
        }
        // The results themselves changed, or the closed toggle did.
        .onChange(of: model.results) { rebuild() }
        .onChange(of: model.showClosed) { rebuild() }
        // Muted, so the photos are the only saturated thing on screen.
        //
        // Basemap guidance for map-first UI is consistent about this: keep the
        // base tonal and low-contrast so the data layer becomes the focus by
        // sheer contrast differential. Apple's default is not that — park green
        // and freeway beige are strong colours, and they were competing with
        // the one element that actually matters here, which is a photograph of
        // somebody's food.
        //
        // `emphasis: .muted` flattens the difference between street types and
        // buildings. POIs were already excluded: a map of restaurants is a poor
        // backdrop for a map of home kitchens.
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
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
                             : "\(browsing.placeName) · cooking right now")
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
                Text("Locations are approximate")
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
                    Text(model.showClosed ? "Hide closed" : "Show closed")
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
    /// True only while closed kitchens share the map. See the glow below.
    var showsCookingGlow: Bool = false

    /// 4:3, the shape food photographs are actually taken in.
    private var photoWidth: CGFloat { 58 }
    private var photoHeight: CGFloat { 44 }
    private var photoRadius: CGFloat { 11 }
    private var shellRadius: CGFloat { 14 }
    private var priceHeight: CGFloat { hasPrice ? 15 : 0 }
    private var shellHeight: CGFloat { photoHeight + 8 + priceHeight }
    private var hasPrice: Bool { result.startingPrice != nil && result.isCooking }

    /// The price, carried by the marker itself.
    ///
    /// The photograph already says *what* — putting the dish name in text
    /// beside a picture of the dish is the redundancy that made the floating
    /// pills wide enough to collide. This says only *how much*, which is the
    /// one thing a picture cannot.
    @ViewBuilder
    private var priceStrip: some View {
        if let price = result.startingPrice, result.isCooking {
            Text(price.display)
                .font(LK.Typography.ui(10.5, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(LK.Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: photoWidth, height: priceHeight)
        }
    }

    private var tier: FreshnessTier { result.freshness ?? .out }

    @State private var bob: CGFloat = 0

    var body: some View {
        // Zero spacing: the stem has to touch the marker, or it reads as a
        // stray arrow rather than a pin. The pill gets its own padding.
        VStack(spacing: 0) {
            // Only the selected pin gets the wide "price · dish" banner now.
            // Floating it above every labelled pin put four of them across the
            // map at city zoom, overlapping each other and covering the very
            // photographs they were meant to annotate. The price moved into the
            // marker instead — see `priceStrip` — where it cannot collide with
            // anything the marker was not already covering.
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
                // Only when closed kitchens are on screen too.
                //
                // This was "the lamp glow" — the lit metaphor, drawn. With
                // `Show closed` off, which is the default, every pin on the map
                // is already cooking, so a glow meaning "this one is cooking"
                // separated nothing and was simply the loudest thing on screen.
                // Hierarchy has to be earned: the distinction appears exactly
                // when there is a distinction to make.
                if result.isCooking, showsCookingGlow {
                    RoundedRectangle(cornerRadius: shellRadius + 8, style: .continuous)
                        .fill(LK.Palette.heat.opacity(tier == .lit ? 0.55 : 0.3))
                        .frame(width: photoWidth + 26, height: shellHeight + 18)
                        .blur(radius: 11)
                }

                // Thick cream ring. This is the whole trick behind a marker
                // reading as a friendly *place* rather than a data point: a
                // heavy light outline separates it from whatever the map is
                // doing underneath, at any zoom, over park green or freeway
                // grey alike.
                // A rounded rectangle, not a circle.
                //
                // Food photographs are 4:3, and a circle inscribed in a square
                // crop throws away most of the plate — six kitchens rendered as
                // six brown-orange smudges, indistinguishable until tapped. The
                // pin's whole payload is the picture, and the shape was eating
                // it. Cropping 4:3 to 4:3 keeps the dish recognisable at the
                // size it is actually drawn.
                RoundedRectangle(cornerRadius: shellRadius, style: .continuous)
                    .fill(LK.Palette.surface)
                    .frame(width: photoWidth + 8, height: shellHeight)
                    .shadow(color: LK.Palette.ink.opacity(0.28), radius: 5, y: 3)

                VStack(spacing: 0) {
                    DishPhoto(
                        urlString: result.headlinePhoto,
                        size: photoWidth,
                        height: photoHeight,
                        cornerRadius: photoRadius,
                        isLit: result.isCooking      // closed kitchens desaturate
                    )
                    .opacity(result.isCooking ? 1 : 0.62)

                    priceStrip
                }

                if tier == .unconfirmed {
                    RoundedRectangle(cornerRadius: shellRadius, style: .continuous)
                        .strokeBorder(LK.Palette.inkTertiary, lineWidth: 2.5)
                        .frame(width: photoWidth + 8, height: shellHeight)
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
                                  : "Tell me when they're cooking")
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

    /// Built from the same parts as `MapPin`: cream disc, soft shadow, stem.
    ///
    /// It was a capsule with an amber ring and a glowing dot — which read as a
    /// floating legend rather than somewhere you could go, and pointed at
    /// nothing. Once the per-pin glow came off, it was also the only saturated
    /// thing left on the map, so the least informative marker had become the
    /// loudest.
    ///
    /// Now a cluster and a single kitchen are obviously the same kind of
    /// object: one shows a photograph, the other shows how many photographs it
    /// is standing in front of.
    private var diameter: CGFloat { 46 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(LK.Palette.surface)
                    .frame(width: diameter + 9, height: diameter + 9)
                    .shadow(color: LK.Palette.ink.opacity(0.28), radius: 5, y: 3)

                VStack(spacing: -2) {
                    Text("\(cluster.isLit ? cluster.litCount : cluster.count)")
                        .font(LK.Typography.ui(19, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(LK.Palette.ink)
                    // The unit, so a bare number is never ambiguous about what
                    // it counts. "cooking" spelled out costs a line but stops
                    // the marker meaning "2 somethings".
                    Text(cluster.isLit ? "cooking" : "closed")
                        .font(LK.Typography.ui(9.5, weight: .semibold))
                        .foregroundStyle(LK.Palette.inkTertiary)
                }

                // A thin amber ring rather than a thick one: enough to say
                // these are open, quiet enough not to outrank the food.
                if cluster.isLit {
                    Circle()
                        .strokeBorder(LK.Palette.heat, lineWidth: 2)
                        .frame(width: diameter + 9, height: diameter + 9)
                }
            }

            Triangle()
                .fill(LK.Palette.surface)
                .frame(width: 11, height: 7)
                .shadow(color: LK.Palette.ink.opacity(0.22), radius: 2, y: 2)
                .offset(y: -1)
        }
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
