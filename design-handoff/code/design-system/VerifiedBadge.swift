import SwiftUI

/// The verified seal, shown beside a cook's name.
///
/// Sits next to the name rather than in a row of its own because that is what
/// the gesture means everywhere else people have seen it — it marks *this
/// account*, and it has to survive being glanced at in a scrolling feed.
///
/// **Blue, and it is not an affordance.** `DESIGN_BRIEF.md` reserves blue for
/// controls and amber for heat; this is neither. The convention for a
/// verification mark is strong enough that inventing a third colour would read
/// as decoration, not trust. It is the one deliberate exception, and it is
/// never the only signal — `accessibilityLabel` says it in words.
struct VerifiedBadge: View {
    var size: CGFloat = 15

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(LK.Palette.action)
            .accessibilityLabel("Permit verified against the county register")
    }
}
/// What the check actually means — reachable from the badge itself.
///
/// A blue check carries a lot of implied meaning that this one does not earn:
/// it says a permit with that number is on LA County's published register at
/// this address and nobody else here has claimed it. It does **not** establish
/// that the person is the permit holder, and it is not a food-safety opinion.
/// Anyone who taps it should end up knowing that.
struct VerifiedExplainerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let cookName: String
    var agencyName: String?
    var permitNumber: String?

    @State private var freshness: RegistryFreshness?
    private let trust = TrustRepository()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        VerifiedBadge(size: 26)
                        Text("Permit verified")
                            .font(LK.Typography.screenTitleSecondary)
                            .foregroundStyle(LK.Palette.ink)
                    }

                    Text("\(cookName)'s permit number appears on \(agencyName ?? "the county")'s published list of permitted home kitchens, registered to the area they cook in.")
                        .font(LK.Typography.body)
                        .foregroundStyle(LK.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let permitNumber {
                        VStack(alignment: .leading, spacing: 3) {
                            SectionHeader("Permit number")
                            Text(permitNumber)
                                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                                .foregroundStyle(LK.Palette.ink)
                            Text("Public record. You can look it up yourself on the county's site.")
                                .font(LK.Typography.meta)
                                .foregroundStyle(LK.Palette.inkTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .background(LK.Palette.surfaceWarm, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusList, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("What it doesn't mean")
                        // Said plainly, because a blue check implies more than
                        // this one can support and the gap is where trust gets
                        // spent.
                        bullet("We checked a permit number, not a person. It's public record, so we can't rule out someone using a number that isn't theirs — though it has to match their area, and only one kitchen can use it.")
                        bullet("It isn't a food-safety rating. Inspections are the health department's job, and their results are published separately.")
                        bullet(recheckLine)
                    }

                    Text("Kitchens without a badge aren't necessarily unpermitted — a new permit takes a few days to appear, and three cities run their own health departments we can't check automatically.")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(LK.Metrics.screenPadding)
            }
            .background(LK.Palette.paper)
            .task { freshness = await trust.registryFreshness() }
            .navigationTitle("About this badge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .tint(LK.Palette.action)
    }

    /// States when the list was actually last read, not how often we intend to
    /// read it. A promise can't go stale on screen; a date can.
    private var recheckLine: String {
        guard let syncedAt = freshness?.syncedAt else {
            return "Permits lapse. We re-check against the county list and the badge comes off on its own if it stops appearing."
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        let stale = freshness?.isFresh == false
        return stale
            ? "Permits lapse, and we last read the county list on \(formatter.string(from: syncedAt)) — longer ago than we'd like. Treat this badge as out of date until it refreshes."
            : "Permits lapse. We last checked the county list on \(formatter.string(from: syncedAt)), and the badge comes off on its own if a permit stops appearing."
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(LK.Palette.inkTertiary)
            Text(text)
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
