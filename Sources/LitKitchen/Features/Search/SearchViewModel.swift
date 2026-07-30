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

    /// Search and the feed look equally far. See `DiscoveryRadius`.
    ///
    /// These were briefly different — search wide, feed narrow — on the theory
    /// that "where can I find sushi" and "what is near me" deserve different
    /// nets. They do not. A buyer who finds a kitchen by searching and then
    /// cannot see it in the feed has been shown two contradictory answers about
    /// their own neighbourhood, and the distance is on every card either way.

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
            async let results = repository.search(q, near: origin, radiusM: DiscoveryRadius.defaultM)
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
