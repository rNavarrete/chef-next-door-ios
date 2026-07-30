import Foundation

/// How far the app looks.
///
/// One answer, read by the feed and by search, for the same reason
/// `BrowsingOrigin` owns one coordinate: two surfaces answering "what is near
/// me" with different numbers is a bug waiting for someone to notice the feed
/// and the search results disagree about the same neighbourhood. They already
/// did — 12 km and 40 km — and nobody would have found it by reading either
/// file alone.
///
/// ## Why it is this wide
///
/// A TestFlight tester in Los Angeles searched for a dish that existed 19 miles
/// away in West Covina and was told there was nothing nearby. The app was not
/// wrong about its own question; the question was too small. Southern
/// California is not a city, it is sixty of them in a row, and a radius tuned
/// for somewhere denser quietly hides most of the map.
///
/// 40 miles covers the Los Angeles basin — Long Beach at 22, Pomona at 30,
/// Malibu and Santa Clarita at about 30 — and reaches into Orange County. It is
/// a circle and not a county line, so it does *not* reach Lancaster or Palmdale
/// over the mountains. That is deliberate: nobody drives from the Antelope
/// Valley for a tray of tamales, and stretching the circle far enough to
/// include them would drag in three more counties on every other bearing.
///
/// ## Wide by default, narrowed by the person
///
/// This is the load, not the answer. `FeedFilter` narrows what arrived, on the
/// device, with no round trip — so the cost of a wide net is paid once and
/// buying it back is instant. Showing someone a kitchen 30 miles away is a
/// choice they can dismiss; hiding it is a choice they cannot see.
public enum DiscoveryRadius {
    /// 40 miles, in metres.
    public static let defaultM = 64_374

    /// The same number in the unit the interface speaks, so copy that quotes
    /// the radius cannot drift away from the radius actually used.
    public static var defaultMiles: Int { Int((Double(defaultM) / 1609.34).rounded()) }
}
