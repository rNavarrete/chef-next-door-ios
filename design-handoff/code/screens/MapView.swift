import MapKit
import Observation
import SwiftUI

@Observable
@MainActor
final class MapViewModel {
    private let repository: any DiscoveryRepository

    var results: [DiscoveryResult] = []
    var selected: DiscoveryResult?
    var showClosed = false
    var isLoading = false

    var origin = Coordinate(latitude: 34.0900, longitude: -117.8903)

    init(repository: any DiscoveryRepository) { self.repository = repository }

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
        isLoading = true
        defer { isLoading = false }
        results = (try? await repository.cookingNow(near: origin, radiusM: 12000, includeClosed: true)) ?? []
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
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.0900, longitude: -117.8903),
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
        .task {
            await model.load()
            // Frame every lit kitchen rather than a fixed span — a pin at the
            // screen edge is a pin nobody taps.
            if let region = model.boundingRegion { camera = .region(region) }
        }
        .sheet(item: Bindable(model).selected) { result in
            MapDetailSheet(result: result)
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
                .presentationBackground(LK.Palette.paper)
        }
        // Kitchens sharing one fuzz cell publish identical points, so zooming
        // can never separate them. They get a list instead.
        .sheet(item: $stackedCluster) { cluster in
            ClusterListSheet(cluster: cluster) { result in
                stackedCluster = nil
                model.selected = result
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(LK.Palette.paper)
        }
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
                        ? LK.Palette.lamp.opacity(haloFill)
                        : Color(hex: 0x8A7F6B).opacity(0.07)
                )
                .stroke(
                    // A defined edge is what makes a circle read as a pool of
                    // light rather than a smudge.
                    result.isCooking ? LK.Palette.lampBright.opacity(0.7) : .clear,
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
        // Daylight. This surface used to force `.dark` so the lamps were the
        // only warm thing on screen — a dusk map, per the original brief. The
        // brief changed: these are meant to read as *your neighbours*, sunny
        // and legible, not as a city at night.
        .environment(\.colorScheme, .light)
        // A low sun over the whole map. Apple's daylight tiles run cool and
        // green, which fights amber just as the dark ones did; a light warm
        // multiply pulls the ground toward afternoon so the lamps sit in it
        // rather than on top of it. Kept weak on purpose — an earlier pass at
        // 0.42 turned the terrain to mud.
        .overlay {
            // A low sun rather than a night wash: warm the ground slightly so
            // the whole map feels like an afternoon, and let the pins carry the
            // colour. Multiply still, but with warm light instead of navy.
            LinearGradient(
                colors: [Color(hex: 0xFFF0D2).opacity(0.16), Color(hex: 0xFFDDA4).opacity(0.24)],
                startPoint: .top, endPoint: .bottom
            )
            .blendMode(.multiply)
            .allowsHitTesting(false)
        }
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
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("Covina · lit right now")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(model.litCount) lit")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: 0xC97A0C))
                }
                // Solid cream and dark ink. All of this chrome used to be
                // `.ultraThinMaterial` forced to `.dark` — white text on a
                // smoked-glass capsule, which only ever worked because the map
                // underneath was near-black. On daylight it turned into grey
                // text over park green.
                .foregroundStyle(Color(hex: 0x4A3411))
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color(hex: 0xFFFBF0).opacity(0.96), in: Capsule())
                .overlay(Capsule().strokeBorder(Color(hex: 0xEADFC9), lineWidth: 1.5))
                .shadow(color: Color(hex: 0x4A3411).opacity(0.16), radius: 6, y: 3)
            }

            HStack {
                Text("Lights are approximate")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x4A3411).opacity(0.85))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    // The disclaimer needs its own backing now. Bare text over
                    // a light map disappeared entirely against pale terrain —
                    // and this is the sentence that keeps the fuzzed point
                    // honest, so it cannot be the one that goes unread.
                    .background(Color(hex: 0xFFFBF0).opacity(0.88), in: Capsule())
                Spacer()
                Button {
                    model.showClosed.toggle()
                } label: {
                    Text(model.showClosed ? "Hide dark" : "Show dark")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: 0x4A3411))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(hex: 0xFFFBF0).opacity(0.96), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color(hex: 0xEADFC9), lineWidth: 1.5))
                        .shadow(color: Color(hex: 0x4A3411).opacity(0.16), radius: 4, y: 2)
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
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: 0x5A3900))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    // Fixed cream, NOT `LK.Palette.lampTint`. That token is
                    // adaptive, and this surface pins its own colour scheme —
                    // so an adaptive colour here resolves against the device's
                    // setting, not the map's, and picked dark brown text on a
                    // dark brown capsule. Adaptive tokens and a hardcoded
                    // scheme never agree.
                    .background(Color(hex: 0xFFFBF0), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(hex: 0xFFE0A3), lineWidth: 1.5))
                    .shadow(color: Color(hex: 0x4A3411).opacity(0.22), radius: 3, y: 2)
                    .padding(.bottom, 5)
            }

            ZStack {
                // The lamp glow, kept behind the marker so a lit kitchen reads
                // warm from across the map before you can make out the food.
                if result.isCooking {
                    Circle()
                        .fill(LK.Palette.lamp.opacity(tier == .lit ? 0.55 : 0.3))
                        .frame(width: diameter + 26, height: diameter + 26)
                        .blur(radius: 11)
                }

                // Thick cream ring. This is the whole trick behind a marker
                // reading as a friendly *place* rather than a data point: a
                // heavy light outline separates it from whatever the map is
                // doing underneath, at any zoom, over park green or freeway
                // grey alike.
                Circle()
                    .fill(Color(hex: 0xFFFBF0))
                    .frame(width: diameter + 9, height: diameter + 9)
                    .shadow(color: Color(hex: 0x4A3411).opacity(0.28), radius: 5, y: 3)

                DishPhoto(
                    urlString: result.headlinePhoto,
                    size: diameter,
                    cornerRadius: diameter / 2,      // a circle
                    isLit: result.isCooking          // dark kitchens desaturate
                )
                .opacity(result.isCooking ? 1 : 0.62)

                if tier == .unconfirmed {
                    Circle()
                        .strokeBorder(Color(hex: 0xC99A45), lineWidth: 2.5)
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
                .fill(Color(hex: 0xFFFBF0))
                .frame(width: 11, height: 7)
                .shadow(color: Color(hex: 0x4A3411).opacity(0.22), radius: 2, y: 2)
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
        guard let first = result.headlineItems?.first else { return result.neighborhood }
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
    private var tier: FreshnessTier { result.freshness ?? .out }

    @State private var bob: CGFloat = 0

    @State private var showingDetail = false
    @State private var isFollowed = false

    private var firstName: String {
        result.displayName.familiarName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                DishPhoto(urlString: result.headlinePhoto, size: 104, isLit: result.isCooking)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        LampIndicator(tier: tier, size: 8)
                        Text(result.availabilityLabel)
                            .font(LK.Typography.availabilityLabel)
                            .textCase(.uppercase)
                            .tracking(0.3)
                            .foregroundStyle(tier == .unconfirmed ? LK.Palette.inkTertiary : LK.Palette.lampInk)
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
                    if let items = result.headlineItems.map(NSOrderedSet.init(array:))
                        .map({ $0.array.compactMap { $0 as? String } }), !items.isEmpty {
                        Text(items.prefix(2).joined(separator: " · "))
                            .font(LK.Typography.meta)
                            .foregroundStyle(LK.Palette.inkTertiary)
                            .lineLimit(1)
                    }

                    if let price = result.startingPrice {
                        Text(price.displayWithMinimum)
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(LK.Palette.ink)
                    }
                }
                Spacer(minLength: 0)
            }

            // Deliberately vague: the exact address is not ours to show until
            // the cook confirms a claim.
            Text("Somewhere in \(result.neighborhood) · \(result.distanceLabel)")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)

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
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        isFollowed ? LK.Palette.lampInkDeep : LK.Palette.action,
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
                .fill(cluster.isLit ? LK.Palette.lampBright : Color(hex: 0xB6A98F))
                .frame(width: 9, height: 9)
                .shadow(color: cluster.isLit ? LK.Palette.lamp.opacity(0.9) : .clear, radius: 5)
            Text(cluster.isLit ? "\(cluster.litCount) lit" : "\(cluster.count)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0x5A3900))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Solid cream, not `.ultraThinMaterial`. The glass capsule was built
        // for the dusk map and worked because it sat on near-black; on a
        // daylight map it picks up whatever is behind it and the count stops
        // being legible over park green.
        .background(Color(hex: 0xFFFBF0), in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                cluster.isLit ? Color(hex: 0xFFC969) : Color(hex: 0xE4DAC6),
                lineWidth: 2
            )
        }
        .shadow(color: Color(hex: 0x4A3411).opacity(0.28), radius: 5, y: 3)
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
    let onSelect: (DiscoveryResult) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("^[\(cluster.count) kitchen](inflect: true) here")
                        .font(LK.Typography.screenTitleSecondary)
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
                                            .font(.system(size: 11, weight: .bold))
                                            .textCase(.uppercase)
                                            .foregroundStyle(
                                                result.freshness == .unconfirmed
                                                    ? LK.Palette.inkTertiary : LK.Palette.lampInk
                                            )
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                }
                                Text(result.headlineItems?.first ?? result.displayName)
                                    .font(LK.Typography.dishNameRow)
                                    .foregroundStyle(LK.Palette.ink)
                                    .lineLimit(1)
                                Text("\(result.displayName) · \(result.distanceLabel)")
                                    .font(LK.Typography.meta)
                                    .foregroundStyle(LK.Palette.inkTertiary)
                                if let price = result.startingPrice {
                                    Text(price.display)
                                        .font(.system(size: 14, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(LK.Palette.ink)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
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
