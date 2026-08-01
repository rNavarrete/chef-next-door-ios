import CoreLocation
import Foundation
import Observation

/// A place the app can look from.
public struct ResolvedPlace: Sendable, Equatable, Codable {
    /// What to call it on screen — "Long Beach", "91801", "Alhambra".
    public let name: String
    public let coordinate: Coordinate

    public init(name: String, coordinate: Coordinate) {
        self.name = name
        self.coordinate = coordinate
    }
}

/// Where the app is looking right now.
///
/// Until this existed there was no location code in the app at all. One
/// coordinate — Covina, 34.0900/-117.8903 — was written out by hand in four
/// separate view models, declared `var` and never once assigned. Everybody
/// browsed the San Gabriel Valley: a buyer in Long Beach saw Covina, and so did
/// the same buyer after moving to Alhambra. The map's search bar was a `Text`
/// view with a magnifying glass next to it, which advertised an action it could
/// not perform.
///
/// One object owns the answer now. The feed, the map, the saved list and search
/// all read it, so they cannot disagree about where "near you" is.
///
/// ## Two ways to be somewhere, and neither is a consolation prize
///
/// The device knows, or the person tells us. A manual choice **wins** over the
/// device and persists across launches, because wanting to look somewhere else
/// is a normal thing to want — checking your home ZIP from work, or seeing what
/// is cooking where you are headed. Someone who declined the permission prompt
/// is not running a degraded app; they are using the same feature deliberately.
///
/// So `place` is not a fallback slot. It is the override, and it happens to
/// also be what fills the gap when there is no device fix to be had.
@Observable
@MainActor
public final class BrowsingOrigin {
    /// The San Gabriel Valley, where the launch cluster of cooks is. Used
    /// before any answer exists — first launch, permission undecided, no
    /// remembered place — so the feed has something real to show rather than an
    /// empty state that looks like a broken app.
    public static let launchCluster = ResolvedPlace(
        name: "Covina",
        coordinate: Coordinate(latitude: 34.0900, longitude: -117.8903)
    )

    /// The place the person chose, if they chose one. Beats the device.
    public private(set) var place: ResolvedPlace?
    /// The last device fix, if we have one and are allowed to use it.
    public private(set) var deviceFix: ResolvedPlace?
    public private(set) var authorization: CLAuthorizationStatus

    /// Set while a device fix is being resolved into a name, so the label can
    /// say something other than a stale place.
    public private(set) var isLocating = false

    private let manager = CLLocationManager()
    /// The live-updates loop, if one is running. Also the re-entrancy guard:
    /// `start()` is called from every surface's `.task`, and without this a tab
    /// switch would open a second stream.
    private var updates: Task<Void, Never>?
    private let defaults: UserDefaults
    private static let placeKey = "litkitchen.browsingPlace"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.authorization = manager.authorizationStatus
        if let data = defaults.data(forKey: Self.placeKey),
           let saved = try? JSONDecoder().decode(ResolvedPlace.self, from: data) {
            self.place = saved
        }
    }

    // No `deinit` cancelling `updates`: it is main-actor isolated and `deinit`
    // is not. Nothing leaks — the task captures `self` weakly and returns after
    // a single fix.

    // MARK: - What everything else reads

    /// The origin every discovery surface searches from.
    public var coordinate: Coordinate { current.coordinate }

    /// What to show in the map's bar: "Long Beach · lit right now".
    public var placeName: String { current.name }

    private var current: ResolvedPlace {
        place ?? deviceFix ?? Self.launchCluster
    }

    /// Whether the origin is coming from the device rather than a choice.
    public var isFollowingDevice: Bool { place == nil && deviceFix != nil }

    /// The person has no device location available and hasn't picked anywhere,
    /// so the origin is a guess. The map says so and offers the search.
    public var isGuessing: Bool {
        place == nil && deviceFix == nil
            && (authorization == .denied || authorization == .restricted)
    }

    // MARK: - Device location

    /// Called the first time a surface needs an origin.
    ///
    /// Safe to call on every appearance: `requestWhenInUseAuthorization` is a
    /// no-op once a decision exists, and starting updates twice is harmless.
    /// Deliberately does nothing when a manual place is set — asking for a
    /// permission whose answer we would then ignore is a prompt spent for
    /// nothing.
    /// Held shut until the welcome screen has been answered.
    ///
    /// `start()` is called from every surface's `.task`, so before this the
    /// system location dialog appeared on the very first frame of the very
    /// first launch — cold, before anyone knew what the app was for. The
    /// welcome screen asks first and opens this only if they say yes.
    ///
    /// Not persisted: once `hasSeenWelcome` is set the gate opens on launch, so
    /// this is only ever closed during the one launch that shows the welcome.
    private var deferredForWelcome = !OnboardingFlag.welcome.isSet

    /// Called by the welcome screen. `wantsLocation` false leaves the gate shut
    /// for this launch — the map's own "use my location" control is still there
    /// and still works.
    public func welcomeAnswered(wantsLocation: Bool) {
        deferredForWelcome = false
        if wantsLocation { start() }
    }

    public func start() {
        guard !deferredForWelcome else { return }
        guard place == nil, updates == nil else { return }

        authorization = manager.authorizationStatus
        if authorization == .notDetermined {
            // The prompt. Everything below waits on the answer.
            manager.requestWhenInUseAuthorization()
        }
        guard authorization != .denied, authorization != .restricted else { return }

        isLocating = deviceFix == nil
        updates = Task { [weak self] in
            do {
                // `liveUpdates` rather than a delegate: `CLLocationManager`'s
                // callbacks arrive on a non-isolated boundary, and bridging them
                // into this `@MainActor` type meant sending a non-`Sendable`
                // delegate across it. The async sequence has no such problem,
                // and iOS 18 is the floor here anyway.
                for try await update in CLLocationUpdate.liveUpdates(.default) {
                    guard let self, !Task.isCancelled else { return }

                    if update.authorizationDenied || update.authorizationRestricted {
                        self.authorization = self.manager.authorizationStatus
                        self.isLocating = false
                        self.updates = nil
                        return
                    }
                    guard let location = update.location else { continue }

                    self.authorization = self.manager.authorizationStatus
                    await self.adopt(location)
                    // One fix is enough. This is a browsing origin, not
                    // turn-by-turn — following the user metre by metre would
                    // reshuffle the feed under their thumb and burn battery to
                    // do it. `followDevice()` re-runs this when they ask.
                    self.updates = nil
                    return
                }
            } catch {
                guard let self else { return }
                self.isLocating = false
                self.updates = nil
            }
        }
    }

    /// Whether asking the device is worth doing at all.
    ///
    /// False only for a hard no — denied or restricted. `notDetermined` is
    /// true, because the ask is exactly what resolves it.
    public var canUseDeviceLocation: Bool {
        authorization != .denied && authorization != .restricted
    }

    /// Take a fresh fix and browse from it. The map's recentre control.
    ///
    /// Deliberately not `followDevice()`, which clears `deviceFix` before
    /// asking for a new one. Every surface keys off `coordinate`, so that
    /// momentarily drops the origin back to Covina — the feed and the map would
    /// load the San Gabriel Valley, then load again when the fix arrived.
    /// Someone in Long Beach pressing "where am I" would watch the map fly to a
    /// city they have never been to and then fly back.
    ///
    /// The old fix stays until a newer one replaces it, so the origin only ever
    /// moves forwards. A manual place *is* cleared: recentring is the explicit
    /// instruction to stop looking somewhere else.
    ///
    /// Also opens the welcome gate. Someone who declined location on the
    /// welcome screen and later pressed this button has plainly changed their
    /// mind, and `start()` would otherwise refuse to run for the rest of the
    /// launch.
    public func recenter() {
        deferredForWelcome = false
        place = nil
        defaults.removeObject(forKey: Self.placeKey)
        updates?.cancel()
        updates = nil
        // Shown even when a fix already exists — the button has to acknowledge
        // the press, and "already know where you are" is not visible feedback.
        isLocating = canUseDeviceLocation
        start()
    }

    /// Drop the manual choice and go back to following the device.
    public func followDevice() {
        place = nil
        defaults.removeObject(forKey: Self.placeKey)
        deviceFix = nil
        updates?.cancel()
        updates = nil
        start()
    }

    // MARK: - Manual choice

    public func use(_ chosen: ResolvedPlace) {
        place = chosen
        if let data = try? JSONEncoder().encode(chosen) {
            defaults.set(data, forKey: Self.placeKey)
        }
        isLocating = false
    }

    /// Turn a fix into a named place and adopt it as the origin.
    private func adopt(_ location: CLLocation) async {
        let name = await Self.name(for: location)
        deviceFix = ResolvedPlace(
            name: name,
            coordinate: Coordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        )
        isLocating = false
    }

    /// A city for a coordinate. Falls back to the coordinate's own rough
    /// description rather than an empty label.
    private static func name(for location: CLLocation) async -> String {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let mark = placemarks?.first else { return "Nearby" }
        return mark.locality
            ?? mark.subAdministrativeArea
            ?? mark.postalCode
            ?? "Nearby"
    }

}

/// Turns what someone types into places they can pick.
///
/// `CLGeocoder` handles both halves of the ask — "90802" and "Alhambra" — so
/// there is no need to branch on whether the query looks like a ZIP. It is
/// rate-limited by Apple, which is why the sheet debounces rather than
/// searching on every keystroke.
public struct PlaceSearch: Sendable {
    public init() {}

    public func places(matching query: String) async -> [ResolvedPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let marks = try? await CLGeocoder().geocodeAddressString(trimmed)
        guard let marks else { return [] }

        return marks.compactMap { mark -> ResolvedPlace? in
            guard let location = mark.location else { return nil }
            return ResolvedPlace(
                name: Self.label(for: mark, query: trimmed),
                coordinate: Coordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
            )
        }
    }

    /// "Alhambra, CA" or "91801 · Alhambra" — enough to tell two results apart.
    ///
    /// A bare ZIP reverse-reads as its city, and showing only the city would
    /// give a list of identical-looking rows for someone who typed a number.
    private static func label(for mark: CLPlacemark, query: String) -> String {
        let isPostal = query.allSatisfy(\.isNumber)
        let city = mark.locality ?? mark.subAdministrativeArea ?? mark.name ?? query
        if isPostal, let code = mark.postalCode {
            return "\(code) · \(city)"
        }
        if let state = mark.administrativeArea, mark.locality != nil {
            return "\(city), \(state)"
        }
        return city
    }
}
