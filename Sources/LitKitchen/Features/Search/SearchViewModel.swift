import Observation
import SwiftUI

@Observable
@MainActor
final class SearchViewModel {
    private let repository: any DiscoveryRepository
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

    var origin = Coordinate(latitude: 34.0900, longitude: -117.8903)

    init(repository: any DiscoveryRepository) {
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
            async let results = repository.search(q, near: origin, radiusM: 12000)
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
