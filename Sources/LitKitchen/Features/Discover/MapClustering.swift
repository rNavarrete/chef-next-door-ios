import CoreLocation
import Foundation
import MapKit

/// A group of kitchens close enough together to collide on screen.
///
/// A cluster of one is a normal pin — callers don't branch, they just render
/// what they're given.
struct MapCluster: Identifiable, Equatable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let members: [DiscoveryResult]

    var count: Int { members.count }
    var litCount: Int { members.filter(\.isCooking).count }
    var isSingle: Bool { members.count == 1 }
    var single: DiscoveryResult? { members.first }

    /// A cluster reads as lit if anything inside it is cooking. Erring toward
    /// lit is deliberate: hiding an open kitchen inside a grey pill is worse
    /// than drawing attention to a group that turns out to be mostly closed.
    var isLit: Bool { litCount > 0 }

    static func == (a: MapCluster, b: MapCluster) -> Bool { a.id == b.id }
}

enum MapClustering {
    /// Fraction of the visible span used as the cluster cell.
    ///
    /// A pin is ~44pt of touch target on a ~400pt-wide screen, so anything
    /// closer than roughly a tenth of the viewport is unhittable. Two cooks in
    /// the same ~400m fuzz cell publish *identical* points and can never be
    /// separated by zooming — clustering is the only way they're both
    /// reachable.
    private static let cellFraction = 0.09

    /// Grid-snap clustering. Deterministic, allocation-light, and stable as
    /// the camera moves — a pin must not flicker between grouped and ungrouped
    /// while someone is panning.
    static func cluster(_ results: [DiscoveryResult], span: Double) -> [MapCluster] {
        guard !results.isEmpty else { return [] }

        let cell = max(span * cellFraction, 0.0001)
        var buckets: [String: [DiscoveryResult]] = [:]

        for result in results {
            let row = (result.publicLat / cell).rounded()
            let col = (result.publicLon / cell).rounded()
            buckets["\(Int(row)):\(Int(col))", default: []].append(result)
        }

        return buckets.map { key, members in
            // Centroid, so a cluster sits among its members rather than on the
            // grid line that happened to create it.
            let lat = members.map(\.publicLat).reduce(0, +) / Double(members.count)
            let lon = members.map(\.publicLon).reduce(0, +) / Double(members.count)
            return MapCluster(
                id: key,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                // Lit first, so a single-pin render and a cluster's headline
                // both surface a cooking kitchen over a closed one.
                members: members.sorted {
                    ($0.freshness?.rankOrder ?? 3) < ($1.freshness?.rankOrder ?? 3)
                }
            )
        }
        // Stable ordering, so SwiftUI diffs cleanly rather than re-adding
        // annotations on every camera change.
        .sorted { $0.id < $1.id }
    }

    /// The region to move to when a cluster is tapped.
    ///
    /// Members sharing one fuzz cell have identical coordinates, so zooming
    /// can never pull them apart — the caller must open a list instead. This
    /// returns `nil` in that case rather than zooming pointlessly.
    static func zoomRegion(for cluster: MapCluster) -> MKCoordinateRegion? {
        let lats = cluster.members.map(\.publicLat)
        let lons = cluster.members.map(\.publicLon)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max()
        else { return nil }

        let dLat = maxLat - minLat, dLon = maxLon - minLon
        // Everything at one point: zooming resolves nothing.
        if dLat < 0.00001 && dLon < 0.00001 { return nil }

        return MKCoordinateRegion(
            center: cluster.coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: max(dLat * 2.2, 0.006),
                longitudeDelta: max(dLon * 2.2, 0.006)
            )
        )
    }
}
