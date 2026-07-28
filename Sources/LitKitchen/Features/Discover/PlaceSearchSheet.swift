import SwiftUI

/// Pick where you're browsing from.
///
/// The map's bar used to be a `Text` view with a magnifying glass beside it,
/// which is the only reason this screen is worth a comment: the affordance
/// existed for months and did nothing. Everything here is in service of that
/// one promise finally being kept.
struct PlaceSearchSheet: View {
    @Bindable var browsing: BrowsingOrigin
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [ResolvedPlace] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    private let search = PlaceSearch()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LK.Metrics.blockSpacing) {
                    field

                    // Offered first, because for most people most of the time
                    // it is the right answer and it costs one tap.
                    if browsing.authorization != .denied,
                       browsing.authorization != .restricted {
                        deviceRow
                    } else {
                        deniedNote
                    }

                    if isSearching {
                        note("Looking…")
                    } else if !results.isEmpty {
                        resultList
                    } else if !query.trimmed.isEmpty, query.trimmed.count >= 2 {
                        note("Nothing matched that. Try a ZIP code, or a city and state.")
                    }
                }
                .padding(LK.Metrics.screenPadding)
            }
            .background(LK.Palette.ground)
            .navigationTitle("Where to look")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var field: some View {
        GroupedCard {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(LK.Palette.inkTertiary)
                TextField("ZIP code or city", text: $query)
                    .font(LK.Typography.body)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(LK.Palette.inkTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
        // Debounced, because CLGeocoder is rate-limited by Apple and a search
        // per keystroke gets the app throttled rather than being fast.
        .onChange(of: query) { _, text in
            searchTask?.cancel()
            results = []
            let trimmed = text.trimmed
            guard trimmed.count >= 2 else { isSearching = false; return }
            isSearching = true
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                let found = await search.places(matching: trimmed)
                guard !Task.isCancelled, trimmed == query.trimmed else { return }
                results = found
                isSearching = false
            }
        }
    }

    private var deviceRow: some View {
        Button {
            browsing.followDevice()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .foregroundStyle(LK.Palette.action)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use my location")
                        .font(LK.Typography.navBar)
                        .foregroundStyle(LK.Palette.ink)
                    Text(browsing.isFollowingDevice
                         ? "Following your location now"
                         : "Show kitchens near where you are")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                }
                Spacer(minLength: 8)
                if browsing.isFollowingDevice {
                    Image(systemName: "checkmark")
                        .foregroundStyle(LK.Palette.action)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Said plainly, and without a nag to go change it.
    ///
    /// Searching a ZIP is a first-class way to use this app, not a workaround,
    /// so a denied prompt gets one factual sentence rather than a banner
    /// pushing the person into Settings.
    private var deniedNote: some View {
        note("Location is off for Lit Kitchen, so search for a ZIP code or a city instead. You can change that in Settings whenever you like.")
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Places")
            GroupedCard {
                ForEach(Array(results.enumerated()), id: \.offset) { index, found in
                    if index > 0 {
                        Divider().overlay(LK.Palette.hairline).padding(.leading, 14)
                    }
                    Button {
                        browsing.use(found)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(LK.Palette.inkTertiary)
                            Text(found.name)
                                .font(LK.Typography.body)
                                .foregroundStyle(LK.Palette.ink)
                            Spacer(minLength: 8)
                            if browsing.place == found {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(LK.Palette.action)
                            }
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(LK.Typography.meta)
            .foregroundStyle(LK.Palette.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
