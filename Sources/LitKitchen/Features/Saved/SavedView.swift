import Observation
import SwiftUI

@Observable
@MainActor
final class SavedViewModel {
    private let store: any FollowStore

    var follows: [Follow] = []
    var rows: [DiscoveryResult] = []
    var isLoading = false

    var origin = Coordinate(latitude: 34.0900, longitude: -117.8903)

    init(store: any FollowStore) { self.store = store }

    var lit: [DiscoveryResult] { rows.filter(\.isCooking) }
    var dark: [DiscoveryResult] { rows.filter { !$0.isCooking } }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        follows = (try? await store.follows()) ?? []
        rows = (try? await store.rows(for: follows, near: origin)) ?? []
    }

    func notify(for cookID: UUID) -> Bool {
        follows.first { $0.cookID == cookID }?.notify ?? true
    }

    func setNotify(_ on: Bool, cookID: UUID) async {
        try? await store.setNotify(on, cookID: cookID)
        follows = (try? await store.follows()) ?? []
    }

    func unfollow(_ cookID: UUID) async {
        try? await store.setFollowing(false, cookID: cookID)
        await load()
    }
}

struct SavedView: View {
    @State var model: SavedViewModel
    /// 3 = Messages. Was 0 for the Claims segment, which no longer exists —
    /// leaving it would land on a tag with no matching segment, so the picker
    /// renders with nothing selected.
    @State private var tab = 3
    @State private var blocked: [BlockedKitchen] = []
    @State private var showingProfile = false
    @State private var myName = "?"
    @State private var myAvatarPath: String?
    private let trust = TrustRepository()

    /// Built once and held, so switching segments doesn't rebuild the list and
    /// lose the unread counts mid-read.
    @State private var messagesModel: ConversationsViewModel? = {
        guard let repo = RootView.messageRepository else { return nil }
        return ConversationsViewModel(repository: repo, profiles: RootView.profileRepository)
    }()

    var body: some View {
        NavigationStack {
        VStack(spacing: 0) {
            // The profile chip that used to sit here is gone. It was added when
            // this tab was "Saved" — the buyer's home, and the only place "you"
            // could live. The Account tab owns that now, with a labelled row
            // rather than a 30pt avatar in a corner, and a signed-in buyer with
            // no photo saw it render as a bare "?".

            if messagesModel != nil {
                // "Claims" is gone. Ordering happens in the thread now
                // (`migrations/043`), so a buyer's outstanding orders *are*
                // their conversations — a separate list of them was the
                // duplicate surface that made claiming confusing.
                Picker("", selection: $tab) {
                    // The unread count rides in the label: a segmented control
                    // has nowhere to put a badge, and an inbox you can't tell
                    // is waiting on you is an inbox nobody opens.
                    // "Inbox", not "Messages" — the tab is already called
                    // Messages, and a segment repeating its parent's name says
                    // nothing about what is inside it.
                    Text(inboxLabel).tag(3)
                    Text("Following").tag(1)
                    // A blocked kitchen vanishes from the feed, map and search
                    // — so without a list here there is no route back to it,
                    // and the block confirmation's promise that you can undo it
                    // any time would simply be false.
                    Text("Blocked").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, LK.Metrics.feedGutter)
                .padding(.top, 8)
            }

            if tab == 2 {
                blockedList
            } else if tab == 3 {
                if let messagesModel {
                    ConversationsView(model: messagesModel, session: RootView.session)
                } else {
                    unavailable
                }
            } else {
                follows
            }
        }
        .background(LK.Palette.ground)
        // Wraps the whole tab, not just the Following list, so the destination
        // is reachable from any segment that grows a link later.
        .navigationDestination(for: DiscoveryResult.self) { result in
            CookDetailView(model: CookDetailViewModel(
                result: result,
                repository: RootView.discoveryRepository
            ))
        }
        .sheet(isPresented: $showingProfile) {
            if let session = RootView.session, let profiles = RootView.profileRepository {
                ProfileView(session: session, profiles: profiles)
            }
        }
        .task(id: tab) {
            if tab == 2 { blocked = (try? await trust.blockedKitchens()) ?? [] }
            if tab == 3 { await messagesModel?.load() }
        }
        // Loads once on appear too, so the unread count in the segment label is
        // right before anyone opens the segment — which is the only way a badge
        // is any use.
        .task { await messagesModel?.load() }
        // Refreshed on every appear, not just the first: returning from the
        // profile sheet after a rename should not leave the old initials.
        .task(id: showingProfile) {
            if let me = try? await RootView.profileRepository?.myProfile() {
                myName = me.displayName
                myAvatarPath = me.avatarPath
            }
        }
        }
    }

    private var inboxLabel: String {
        let unread = messagesModel?.totalUnread ?? 0
        return unread > 0 ? "Inbox (\(unread))" : "Inbox"
    }

    private var unavailable: some View {
        Text("Messages need a connection to the kitchen network.")
            .font(LK.Typography.body)
            .foregroundStyle(LK.Palette.inkQuiet)
            .multilineTextAlignment(.center)
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var blockedList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if blocked.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nothing blocked")
                            .font(LK.Typography.titleSecondary)
                            .foregroundStyle(LK.Palette.ink)
                        Text("Blocking a kitchen hides it from your feed, map and search. They're never told.")
                            .font(LK.Typography.meta)
                            .foregroundStyle(LK.Palette.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 40)
                } else {
                    ForEach(blocked) { kitchen in
                        HStack(spacing: 12) {
                            DishPhoto(urlString: kitchen.avatarURL, size: 44, cornerRadius: 22)
                            Text(kitchen.displayName)
                                .font(LK.Typography.dishNameRow)
                                .foregroundStyle(LK.Palette.ink)
                            Spacer(minLength: 8)
                            Button("Unblock") {
                                Task {
                                    try? await trust.unblock(cookID: kitchen.cookID)
                                    blocked = (try? await trust.blockedKitchens()) ?? []
                                }
                            }
                            .font(LK.Typography.ui(14, weight: .semibold))
                            .foregroundStyle(LK.Palette.action)
                            .buttonStyle(.plain)
                        }
                        .padding(13)
                        .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, LK.Metrics.feedGutter)
        }
        .contentMargins(.bottom, 28, for: .scrollContent)
    }

    private var follows: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                header
                if model.rows.isEmpty && !model.isLoading {
                    emptyState
                } else {
                    ForEach(model.lit) { result in
                        NavigationLink(value: result) { LitFollowCard(result: result) }
                            .buttonStyle(.plain)
                    }
                    if !model.dark.isEmpty { darkSection }
                }
            }
            .padding(.horizontal, LK.Metrics.feedGutter)
        }
        .contentMargins(.bottom, 28, for: .scrollContent)
        .background(LK.Palette.ground)
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Counts lit-of-followed, not just a total. The number a buyer
            // actually cares about opening this tab is "is anyone on right now".
            Text(model.rows.isEmpty
                 ? "Nobody followed yet"
                 : "\(model.lit.count) of your \(model.rows.count) are lit")
                .font(LK.Typography.screenTitle)
                .foregroundStyle(LK.Palette.ink)
            Text("Cooks you follow, and whether they're cooking right now.")
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.inkTertiary)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart")
                .font(LK.Typography.screenTitle)
                .foregroundStyle(LK.Palette.inkTertiary.opacity(0.6))
            Text("Follow a cook and their light shows up here.")
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.inkQuiet)
            Text("Tap “Turn their light on for me” on any dark kitchen.")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private var darkSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Dark right now")
                .padding(.top, 12)
                .padding(.bottom, 8)

            GroupedCard {
                ForEach(Array(model.dark.enumerated()), id: \.element.id) { index, result in
                    if index > 0 {
                        Divider().overlay(LK.Palette.hairline).padding(.leading, 68)
                    }
                    DarkFollowRow(
                        result: result,
                        notify: model.notify(for: result.cookID),
                        onNotifyChange: { on in
                            Task { await model.setNotify(on, cookID: result.cookID) }
                        }
                    )
                }
            }

            // The switch writes a preference either way, but nothing can be
                // delivered without an account — 050 fans out to `device_tokens`,
                // which are per user. Saying "the switch is the push" to someone
                // signed out promises a notification that cannot arrive.
                Text(RootView.session?.isAnonymous ?? true
                     ? "The switch is the push, per cook — sign in to receive them."
                     : "The switch is the push, per cook.")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)
                .padding(.top, 10)
        }
    }
}

/// A followed cook who is cooking right now. Glow card, big avatar — this is
/// the payoff for following, so it gets the full treatment.
private struct LitFollowCard: View {
    let result: DiscoveryResult
    private var tier: FreshnessTier { result.freshness ?? .out }

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: result.displayName, urlString: result.avatarURL, size: 60, isLit: true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    LampIndicator(tier: tier, size: 8)
                    Text(result.availabilityLabel)
                        .font(LK.Typography.caps)
                        .textCase(.uppercase)
                        .tracking(0.3)
                        .foregroundStyle(tier == .unconfirmed ? LK.Palette.inkTertiary : LK.Palette.heatInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                HStack(spacing: 4) {
                    Text(result.displayName)
                    if result.isVerified { VerifiedBadge(size: 12) }
                }
                    .font(LK.Typography.dishNameCard)
                    .foregroundStyle(LK.Palette.ink)

                if let items = result.localizedHeadlineItems, !items.isEmpty {
                    Text(items.prefix(2).joined(separator: " · "))
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .lineLimit(1)
                }

                if let price = result.startingPrice {
                    Text("\(price.display) · \(result.distanceLabel)")
                        .font(LK.Typography.ui(14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(LK.Palette.ink)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous)
                .strokeBorder(LK.Palette.hairline, lineWidth: LK.Metrics.cardBorderWidth)
        }
        .lkCardShadow()
    }
}

/// A followed cook who isn't cooking. Quiet hairline row, greyscale avatar,
/// and the per-cook push switch — following without notifications is a
/// legitimate choice, not a degraded one.
private struct DarkFollowRow: View {
    let result: DiscoveryResult
    let notify: Bool
    let onNotifyChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: result.displayName, urlString: result.avatarURL, size: 44, isLit: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.displayName)
                    .font(LK.Typography.ui(16, weight: .semibold))
                    .foregroundStyle(LK.Palette.inkQuiet)
                Text(result.localizedHeadlineItems?.first ?? result.neighborhood)
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(get: { notify }, set: onNotifyChange))
                .labelsHidden()
                .tint(LK.Palette.action)
                .accessibilityLabel("Notify me when \(result.displayName) lights up")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// Initials placeholder until cook photos land. Lit avatars keep their colour;
/// dark ones go greyscale, same rule as everywhere else.
private struct Avatar: View {
    let name: String
    var urlString: String?
    let size: CGFloat
    let isLit: Bool

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
    }

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsCircle
                }
            } else {
                initialsCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .saturation(isLit ? 1 : 0)
        .overlay {
            if isLit {
                Circle().strokeBorder(LK.Palette.heat.opacity(0.45), lineWidth: 1.5)
            }
        }
    }

    private var initialsCircle: some View {
        Circle()
            .fill(isLit ? LK.Palette.chip : LK.Palette.chip)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(isLit ? LK.Palette.heatInk : LK.Palette.inkTertiary)
            }
    }
}
