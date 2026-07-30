import Observation
import SwiftUI

@Observable
@MainActor
final class SearchViewModel {
    private let repository: any DiscoveryRepository
    private let browsing: BrowsingOrigin
    private var searchTask: Task<Void, Never>?

    var query: String = "" {
        didSet { scheduleSearch() }
    }
    var lit: [DiscoveryResult] = []
    var dark: [DiscoveryResult] = []
    /// The synonym terms the query expanded to. Shown to the buyer so a match
    /// is explainable rather than magic — and so a *missing* match is too.
    var expansion: [String] = []
    var isSearching = false
    var hasSearched = false

    /// Read, never stored. The one answer lives in `BrowsingOrigin`, so the
    /// feed and the map cannot disagree about where "near you" is.
    var origin: Coordinate { browsing.coordinate }

    /// Search reaches further than the feed, on purpose.
    ///
    /// The feed answers "what is near me right now", and 7.5 miles is a fair
    /// definition of near. Search answers "where can I find sushi", and in
    /// Southern California that answer is usually a freeway away. At the old
    /// 12 km both questions got the same radius, so a buyer downtown searching
    /// "sushi" was told *nothing matching that nearby* while a kitchen 19 miles
    /// out sat indexed, open, and matching. The kitchen was fine; the question
    /// being asked of the database was too small.
    ///
    /// Rows come back distance-ordered, so widening the net cannot bury a close
    /// match underneath far ones — the nearest is still first.
    static let radiusM = 40_000
    static var radiusMiles: Int { Int((Double(radiusM) / 1609.34).rounded()) }

    init(repository: any DiscoveryRepository, browsing: BrowsingOrigin) {
        self.browsing = browsing
        self.repository = repository
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)

        guard q.count >= 2 else {
            lit = []; dark = []; expansion = []; hasSearched = false
            return
        }

        searchTask = Task {
            // Debounce. Cancellation is the exit path, so a cancelled task
            // must not clear results the newer one is about to fill.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await run(q)
        }
    }

    private func run(_ q: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            async let results = repository.search(q, near: origin, radiusM: Self.radiusM)
            async let terms = repository.expansion(for: q)
            let (r, t) = try await (results, terms)
            guard !Task.isCancelled else { return }

            lit = r.filter(\.isCooking)
            dark = r.filter { !$0.isCooking }
            // Drop the raw query from the expansion — showing someone their
            // own word back as a "también" is noise.
            expansion = t.filter { $0.lowercased() != q.lowercased() }
            hasSearched = true
        } catch {
            guard !Task.isCancelled else { return }
            lit = []; dark = []; expansion = []; hasSearched = true
        }
    }
}
