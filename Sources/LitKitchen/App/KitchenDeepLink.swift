import SwiftUI

/// Opens a kitchen from a shared `litkitchen://cook/<id>` link.
///
/// The cook's own row is fetched here rather than passed in, because whoever
/// followed the link has nothing but an id — they came from a Facebook post or
/// a QR code on a paper bag, not from the feed.
///
/// `cooks_by_ids` is used rather than a bare select: it returns the same
/// `discovery_row` the feed builds, so a kitchen reached by link renders
/// identically to one reached by scrolling, including freshness and distance.
struct KitchenDeepLinkView: View {
    let cookID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var result: DiscoveryResult?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    CookDetailView(model: CookDetailViewModel(
                        result: result,
                        repository: RootView.discoveryRepository
                    ))
                } else if failed {
                    // A cook can delete their account, and a link outlives it.
                    VStack(spacing: 8) {
                        Text("That kitchen isn't here anymore")
                            .font(LK.Typography.bodyEmphasis)
                            .foregroundStyle(LK.Palette.ink)
                        Text("The cook may have closed it. Have a look at who else is cooking nearby.")
                            .font(LK.Typography.meta)
                            .foregroundStyle(LK.Palette.inkTertiary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(LK.Metrics.screenPadding)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LK.Palette.ground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            let origin = RootView.origin.coordinate
            let rows = try? await RootView.discoveryRepository
                .rows(forCookIDs: [cookID], near: origin)
            if let found = rows?.first { result = found } else { failed = true }
        }
    }
}
