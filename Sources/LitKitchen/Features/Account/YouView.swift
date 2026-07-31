import SwiftUI

/// You, as a buyer — whether or not you also cook.
///
/// This took the place of a second Messages list. `Account` used to open onto
/// `Kitchen | Messages`, and the Messages half showed the same threads, in the
/// same order, as the Messages tab two inches below it. Two doors, one room.
///
/// ## Why cooks need this most
///
/// A cook's public identity is their kitchen: photo, story, menu, permit. What
/// they had nowhere to see is the *other* half of their account. The first real
/// cook on this app has bought from four kitchens and there was no screen in
/// the product that admitted it — the person who cooks and the person who
/// collects were the same account with only one of them visible.
struct YouView: View {
    @Bindable var session: SessionController
    let profiles: any ProfileRepository

    @State private var profile: Profile?
    @State private var history: [BuyingHistoryEntry] = []
    @State private var avatarURL: URL?
    @State private var isLoading = true
    @State private var showingEditor = false

    /// Content, not a screen. Deliberately no `ScrollView` of its own: a cook
    /// reaches this inside one and a buyer reaches it inside another, and
    /// nesting two is how you get a pane that scrolls the wrong thing.
    var body: some View {
        VStack(alignment: .leading, spacing: LK.Metrics.blockSpacing) {
            header

            if isLoading && profile == nil {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
            } else {
                reviewsSummary
                historySection
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingEditor, onDismiss: { Task { await load() } }) {
            ProfileView(session: session, profiles: profiles)
        }
    }

    private func load() async {
        defer { isLoading = false }
        profile = try? await profiles.myProfile()
        history = (try? await profiles.buyingHistory()) ?? []
        avatarURL = try? await profiles.avatarURL(for: profile?.avatarPath)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Group {
                    if let avatarURL {
                        AsyncImage(url: avatarURL) { $0.resizable().scaledToFill() }
                            placeholder: { Circle().fill(LK.Palette.chip) }
                    } else {
                        Circle().fill(LK.Palette.chip).overlay {
                            Image(systemName: "person.fill")
                                .foregroundStyle(LK.Palette.inkTertiary)
                        }
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile?.displayName ?? "Your profile")
                        .font(LK.Typography.screenTitle)
                        .foregroundStyle(LK.Palette.ink)
                    if let since = profile?.createdAt {
                        Text("Here since \(since.formatted(.dateTime.month(.wide).year()))")
                            .font(LK.Typography.meta)
                            .foregroundStyle(LK.Palette.inkTertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            // Shown even when empty, with the prompt as the placeholder. A bio
            // nobody knows exists is a bio nobody writes.
            Text(profile?.bio?.isEmpty == false
                 ? profile!.bio!
                 : "Add a line about yourself — when you usually collect, say. Cooks you message can see it.")
                .font(LK.Typography.body)
                .foregroundStyle(profile?.bio?.isEmpty == false
                                 ? LK.Palette.ink : LK.Palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showingEditor = true
            } label: {
                Text("Edit profile")
                    .font(LK.Typography.navBarEmphasis)
                    .foregroundStyle(LK.Palette.action)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: LK.Metrics.radiusButton, style: .continuous)
                            .strokeBorder(LK.Palette.action.opacity(0.35), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var written: [BuyingHistoryEntry] {
        history.filter { $0.myRating != nil }
    }

    @ViewBuilder
    private var reviewsSummary: some View {
        if !history.isEmpty {
            HStack(spacing: 0) {
                stat("\(history.count)", history.count == 1 ? "kitchen" : "kitchens")
                divider
                stat("\(history.reduce(0) { $0 + $1.pickups })", "picked up")
                divider
                stat("\(written.count)", written.count == 1 ? "review" : "reviews")
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous)
                    .strokeBorder(LK.Palette.hairline, lineWidth: 0.5)
            }
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
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(LK.Palette.hairline).frame(width: 0.5, height: 34)
    }

    @ViewBuilder
    private var historySection: some View {
        if history.isEmpty {
            VStack(spacing: 6) {
                Text("You haven't ordered from anyone yet.")
                    .font(LK.Typography.body)
                    .foregroundStyle(LK.Palette.inkQuiet)
                Text("Kitchens you order from show up here, with anything you said about them.")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Kitchens you've bought from")
                GroupedCard {
                    ForEach(Array(history.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().overlay(LK.Palette.hairline).padding(.leading, 14)
                        }
                        row(entry)
                    }
                }
            }
        }
    }

    private func row(_ entry: BuyingHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: entry.avatarURL.flatMap(URL.init(string:))) {
                $0.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(LK.Palette.chip)
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.cookName)
                    .font(LK.Typography.bodyEmphasis)
                    .foregroundStyle(LK.Palette.ink)

                Text(subtitle(entry))
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)

                // Your own words, kept with the kitchen they were about. A
                // review in a list of its own is a sentence with nowhere to go.
                if let review = entry.myReview, !review.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= (entry.myRating ?? 0) ? "star.fill" : "star")
                                .font(LK.Typography.ui(10))
                                .foregroundStyle(star <= (entry.myRating ?? 0)
                                                 ? LK.Palette.heat
                                                 : LK.Palette.inkTertiary.opacity(0.35))
                        }
                    }
                    .padding(.top, 2)
                    Text(review)
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private func subtitle(_ entry: BuyingHistoryEntry) -> String {
        var parts: [String] = []
        if let hood = entry.neighborhood, !hood.isEmpty { parts.append(hood) }
        if entry.pickups > 0 {
            parts.append(entry.pickups == 1 ? "picked up once" : "picked up \(entry.pickups) times")
        } else if entry.orders > 0 {
            parts.append(entry.orders == 1 ? "1 order" : "\(entry.orders) orders")
        }
        return parts.joined(separator: " · ")
    }
}
