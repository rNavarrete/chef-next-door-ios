import SwiftUI

/// Who this buyer is, from the cook's side of the thread.
///
/// A cook reading a message at nine at night is answering one question: have I
/// cooked for this person before, and did they turn up. That was previously
/// answerable only by scrolling the thread, and not at all for the platform as
/// a whole.
///
/// ## Deliberately not a reputation page
///
/// No score, no stars out of five, no badge. Buyers are not rated in this app
/// and this screen does not quietly start rating them — a number a buyer cannot
/// see and cannot appeal is worse than no number. What is here is history and
/// counts, which are facts rather than judgements, and the cook can read them
/// however they like.
///
/// The reviews figure is a count for the same reason. Reviews are anonymous on
/// a kitchen page, which is what makes an honest two-star review possible; the
/// only review shown in full is the one this buyer wrote for *this* cook, which
/// they can already read on their own kitchen page.
struct BuyerProfileView: View {
    let buyerID: UUID
    let profiles: any ProfileRepository

    @State private var profile: BuyerProfile?
    @State private var avatarURL: URL?
    @State private var isLoading = true
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let profile {
                    content(profile)
                } else if isLoading {
                    ProgressView().padding(.top, 60)
                } else if failed {
                    Text("Couldn't load this profile.")
                        .font(LK.Typography.body)
                        .foregroundStyle(LK.Palette.inkQuiet)
                        .padding(.top, 60)
                }
            }
            .background(LK.Palette.ground)
            .navigationTitle(profile?.displayName ?? "Buyer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            defer { isLoading = false }
            do {
                profile = try await profiles.buyerProfile(for: buyerID)
                failed = profile == nil
                if let path = profile?.avatarPath {
                    avatarURL = try? await profiles.avatarURL(for: path)
                }
            } catch {
                failed = true
            }
        }
    }

    @ViewBuilder
    private func content(_ p: BuyerProfile) -> some View {
        VStack(spacing: LK.Metrics.blockSpacing) {
            header(p)

            // The answer to the question the cook actually opened this for,
            // written as a sentence rather than left to be inferred from two
            // numbers sitting next to each other.
            if p.pickupsWithMe > 0 {
                calloutCard(
                    icon: "checkmark.circle.fill",
                    title: p.pickupsWithMe == 1
                        ? "Collected once from you"
                        : "Collected \(p.pickupsWithMe) times from you",
                    detail: firstOrderLine(p)
                )
            } else {
                calloutCard(
                    icon: "sparkles",
                    title: "First time with you",
                    detail: p.pickupsTotal > 0
                        ? "They've collected \(p.pickupsTotal) order\(p.pickupsTotal == 1 ? "" : "s") elsewhere on Chef Next Door."
                        : "No completed pickups yet, here or anywhere."
                )
            }

            stats(p)

            if let body = p.reviewForMe, !body.isEmpty {
                reviewCard(body: body, stars: p.reviewForMeStars ?? 0)
            }

            // Said out loud so a cook does not read the silence as "no reviews
            // written" or go looking for a list that is deliberately absent.
            Text(p.reviewsWritten == 0
                 ? "They haven't written any reviews yet."
                 : "They've written \(p.reviewsWritten) review\(p.reviewsWritten == 1 ? "" : "s"). Reviews are anonymous, so only the one they left you is shown.")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LK.Metrics.screenPadding)
    }

    private func header(_ p: BuyerProfile) -> some View {
        HStack(spacing: 14) {
            Group {
                if let avatarURL {
                    AsyncImage(url: avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(LK.Palette.chip)
                    }
                } else {
                    Circle().fill(LK.Palette.chip)
                        .overlay {
                            Image(systemName: "person.fill")
                                .foregroundStyle(LK.Palette.inkTertiary)
                        }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(p.displayName)
                    .font(LK.Typography.screenTitle)
                    .foregroundStyle(LK.Palette.ink)
                Text("On Chef Next Door since \(p.memberSince.formatted(.dateTime.month(.wide).year()))")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func calloutCard(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(LK.Typography.ui(16, weight: .semibold))
                .foregroundStyle(LK.Palette.action)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LK.Typography.bodyEmphasis)
                    .foregroundStyle(LK.Palette.ink)
                Text(detail)
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LK.Palette.chip, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous))
    }

    private func firstOrderLine(_ p: BuyerProfile) -> String {
        guard let first = p.firstOrderWithMe else {
            return "Across \(p.pickupsTotal) pickup\(p.pickupsTotal == 1 ? "" : "s") on Chef Next Door."
        }
        return "First ordered from you in \(first.formatted(.dateTime.month(.wide).year()))."
    }

    /// Counts, side by side, with the platform figure labelled as such. A cook
    /// misreading "12" as twelve orders from *them* would be worse than not
    /// showing it.
    private func stats(_ p: BuyerProfile) -> some View {
        HStack(spacing: 0) {
            stat("\(p.pickupsWithMe)", "picked up\nfrom you")
            divider
            // Pluralised, because "1 orders with you" is the kind of thing that
            // makes a screen look like nobody read it.
            stat("\(p.ordersWithMe)", p.ordersWithMe == 1 ? "order\nwith you" : "orders\nwith you")
            divider
            stat("\(p.pickupsTotal)", "picked up\nin total")
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous)
                .strokeBorder(LK.Palette.hairline, lineWidth: 0.5)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(LK.Typography.ui(22, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(LK.Palette.ink)
            Text(label)
                .font(LK.Typography.ui(11.5, weight: .medium))
                .foregroundStyle(LK.Palette.inkTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(LK.Palette.hairline).frame(width: 0.5, height: 34)
    }

    private func reviewCard(body: String, stars: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("What they said about you")
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= stars ? "star.fill" : "star")
                            .font(LK.Typography.ui(12))
                            .foregroundStyle(star <= stars
                                             ? LK.Palette.heat
                                             : LK.Palette.inkTertiary.opacity(0.35))
                    }
                }
                Text(body)
                    .font(LK.Typography.body)
                    .foregroundStyle(LK.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous)
                    .strokeBorder(LK.Palette.hairline, lineWidth: 0.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
