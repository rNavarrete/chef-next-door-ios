import Observation
import SwiftUI

@Observable
@MainActor
final class CookDetailViewModel {
    private let repository: any DiscoveryRepository
    let result: DiscoveryResult

    var menu: [MenuItem] = []
    /// The cook's own row. Nil until loaded, and nil forever against the
    /// in-memory double — every use has to degrade rather than assume.
    var cook: Cook?
    var isLoading = false

    init(result: DiscoveryResult, repository: any DiscoveryRepository) {
        self.result = result
        self.repository = repository
    }

    var available: [MenuItem] { menu.filter(\.isAvailable) }
    var soldOut: [MenuItem] { menu.filter { !$0.isAvailable } }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        menu = (try? await repository.menu(for: result.cookID)) ?? []
        // Separate and non-fatal: a menu that loads without a profile is still
        // a usable screen, and the story degrades to absent.
        cook = try? await repository.cook(result.cookID)
    }
}

/// Everything a buyer needs to decide, and nothing that pretends to be a
/// transaction. The claim CTA is honest about what it does.
struct CookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State var model: CookDetailViewModel
    @State private var isFollowed = false
    @State private var showingReport = false
    @State private var showingThread = false
    @State private var showingVerifiedInfo = false
    @State private var isBlocked = false
    @State private var showingBlockConfirm = false
    /// Collapsed by default so a long story can't push the menu off-screen.
    @State private var storyExpanded = false
    /// The dish a buyer tapped to look at properly.
    @State private var selectedDish: MenuItem?
    @State private var reviews: [Review] = []
    @State private var rating: CookRating?

    private let trust = TrustRepository()

    private var tier: FreshnessTier { model.result.freshness ?? .out }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    content
                }
            }
            .contentMargins(.bottom, 108, for: .scrollContent)
            .ignoresSafeArea(edges: .top)

            bottomBar
        }
        .background(LK.Palette.paper)
        .task {
            await model.load()
            isFollowed = ((try? await RootView.follows.follows()) ?? [])
                .contains { $0.cookID == model.result.cookID }
            await loadTrust()
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) { backButton }
        .overlay(alignment: .topTrailing) { followButton }
        .sheet(isPresented: $showingReport) {
            ReportSheet(cookID: model.result.cookID, cookName: firstName)
        }
        .sheet(item: $selectedDish) { dish in
            DishDetailSheet(
                item: dish,
                cookName: firstName,
                // Nil when there's no backend: the dish still reads, it just
                // can't be ordered, which is the honest state.
                onOrder: RootView.messageRepository == nil ? nil : { showingThread = true }
            )
        }
        .sheet(isPresented: $showingThread) {
            threadSheet
                // Every other sheet in the app offers a way out — Cancel on the
                // order sheet, "Not now" on the gate, a grabber on both map
                // sheets. This one had neither a grabber nor a button, so a
                // buyer who opened a thread from a profile could only leave by
                // guessing at a swipe.
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingVerifiedInfo) {
            VerifiedExplainerSheet(
                cookName: firstName,
                agencyName: model.result.agencyName,
                permitNumber: model.result.permitNumber
            )
        }
        .confirmationDialog(
            "Stop showing \(firstName)?",
            isPresented: $showingBlockConfirm, titleVisibility: .visible
        ) {
            Button(isBlocked ? "Show them again" : "Block this kitchen",
                   role: isBlocked ? nil : .destructive) {
                Task { await toggleBlock() }
            }
        } message: {
            Text(isBlocked
                 ? "They'll appear in your feed, map and search again."
                 : "They'll disappear from your feed, map and search. They aren't told, and you can undo this any time.")
        }
    }

    private func loadTrust() async {
        async let found = try? trust.reviews(forCook: model.result.cookID)
        async let score = try? trust.rating(forCook: model.result.cookID)
        async let blocked = trust.isBlocked(cookID: model.result.cookID)
        reviews = await found ?? []
        rating = await score
        isBlocked = await blocked
    }

    private func toggleBlock() async {
        do {
            if isBlocked {
                try await trust.unblock(cookID: model.result.cookID)
                isBlocked = false
            } else {
                try await trust.block(cookID: model.result.cookID)
                isBlocked = true
                // Blocking from the kitchen page means you don't want to be
                // here. Leaving you staring at it would be a strange reward.
                dismiss()
            }
        } catch {
            // Non-fatal: the state simply doesn't change.
        }
    }

    // MARK: - Reviews

    @ViewBuilder
    private var reviewsSection: some View {
        if let rating, rating.isMeaningful {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    SectionHeader("What neighbours said")
                    Spacer(minLength: 0)
                    // Count always next to the average. "5.0" from one review
                    // and "4.6" from ninety are not the same claim.
                    Text("\(rating.average.map { String(format: "%.1f", $0) } ?? "—") · \(rating.reviewCount) review\(rating.reviewCount == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LK.Palette.inkSecondary)
                }

                GroupedCard {
                    ForEach(Array(reviews.prefix(5).enumerated()), id: \.element.id) { index, review in
                        if index > 0 { Divider().overlay(LK.Palette.hairline).padding(.leading, 14) }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 3) {
                                ForEach(1...5, id: \.self) { star in
                                    Image(systemName: star <= review.rating ? "star.fill" : "star")
                                        .font(.system(size: 11))
                                        .foregroundStyle(star <= review.rating
                                                         ? LK.Palette.lamp
                                                         : LK.Palette.inkTertiary.opacity(0.35))
                                }
                            }
                            if let body = review.body, !body.isEmpty {
                                Text(body)
                                    .font(LK.Typography.body)
                                    .foregroundStyle(LK.Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                }
            }
        }
    }

    /// Report and block, at the bottom and understated. These are not things to
    /// put next to the claim button — but they must exist, and be findable
    /// without a search.
    private var safetyActions: some View {
        HStack(spacing: 18) {
            Button("Report this kitchen") { showingReport = true }
            Button(isBlocked ? "Unblock" : "Block") { showingBlockConfirm = true }
            Spacer(minLength: 0)
        }
        .font(LK.Typography.meta)
        .foregroundStyle(LK.Palette.inkTertiary)
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Hero

    /// The cook's cover if they have set one, otherwise the headline dish.
    ///
    /// The fallback is the whole reason the cover exists: rendering
    /// `headlinePhoto` here showed the buyer the *same image they just tapped*
    /// on the feed card. A cover is about the kitchen — the setup, the spread,
    /// hands working — so the page opens with something the card could not
    /// already have said.
    ///
    /// `model.cook` loads after `model.result`, so this starts on the dish photo
    /// and swaps when the profile arrives. `DishPhoto` cross-fades, and the
    /// cached image means a revisit is instant.
    private var heroPhoto: String? {
        model.cook?.coverURL ?? model.result.headlinePhoto
    }

    private var hero: some View {
        ZStack(alignment: .bottom) {
            DishPhoto(
                urlString: heroPhoto,
                size: 400,
                cornerRadius: 0,
                isLit: model.result.isCooking
            )
            .frame(height: heroHeight)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [.clear, LK.Palette.paper.opacity(0.4)],
                startPoint: .center, endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .frame(height: heroHeight)
        .overlay(alignment: .topLeading) {
            // Amber wash from the top-left, as if the light came from inside.
            LinearGradient(
                colors: [LK.Palette.lamp.opacity(model.result.isCooking ? 0.28 : 0), .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        }
    }

    /// 224 → 188. The page's job is helping someone decide, and the deciding
    /// material — the story, the permit, the menu — all sat below the fold
    /// behind a quarter-screen photo.
    private let heroHeight: CGFloat = 188

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LK.Palette.ink)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.leading, LK.Metrics.feedGutter)
        .padding(.top, 6)
    }

    private var followButton: some View {
        Button {
            Task {
                try? await RootView.follows.setFollowing(!isFollowed, cookID: model.result.cookID)
                isFollowed.toggle()
            }
        } label: {
            Image(systemName: isFollowed ? "heart.fill" : "heart")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isFollowed ? LK.Palette.action : LK.Palette.ink)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, LK.Metrics.feedGutter)
        .padding(.top, 6)
        .accessibilityLabel(isFollowed ? "Following" : "Turn their light on for me")
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            availabilityAndName
            unconfirmedNote
            if model.result.isCooking { servingNote }
            // Above the menu: who this person is should land before what they
            // are selling. It is also the answer to "why would I walk to a
            // stranger's house", which a buyer asks before reading prices.
            storySection
            menuSection
            permitCard
            reviewsSection
            safetyActions
        }
        .padding(LK.Metrics.screenPadding)
        .background(
            LK.Palette.paper,
            in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
        )
        .offset(y: -20)
    }

    private var availabilityAndName: some View {
        // The avatar sits beside the whole identity block rather than above the
        // name, so it reads as belonging to the person the three lines describe.
        // Top-aligned: the block grows downward when a kitchen is unconfirmed
        // and picks up an explanatory paragraph, and a centred avatar would
        // drift away from the name it belongs to.
        HStack(alignment: .top, spacing: 14) {
            identityBlock
            Spacer(minLength: 8)
            polaroidPortrait
        }
    }

    /// The cook, as a Polaroid taped to the page.
    ///
    /// A circle is the neutral shape for "a person in a list" and it is right
    /// in the inbox. On a profile it was reading as an org chart headshot. The
    /// frame — even margins, a deep bottom lip, a couple of degrees off square
    /// — is the whole trick: it turns the same photo into an object somebody
    /// put there by hand.
    private var polaroidPortrait: some View {
        ProfileAvatar(
            name: model.result.displayName,
            // A cook's avatar is a public URL — `needsSigning` is for the buyer
            // side, whose avatars live in a private bucket.
            source: model.result.avatarURL,
            size: 84,
            // Barely rounded, not sharp. A true right angle reads as a crop
            // artefact at this size.
            cornerRadius: 3
        )
        .padding(8)
        // The Polaroid tell. Nothing else about the shape says instant film;
        // the deep lower margin does all of it.
        .padding(.bottom, 22)
        .background(Color(hex: 0xFFFDF8))
        .overlay {
            // Warm hairline, or the white frame dissolves into the paper.
            Rectangle().stroke(Color(hex: 0xE6DAC4), lineWidth: 1)
        }
        .shadow(color: Color(hex: 0x4A3411).opacity(0.22), radius: 8, y: 5)
        // Off-square, and tilted *away* from the name so the gap between them
        // opens rather than pinches.
        .rotationEffect(.degrees(3.5))
        .padding(.top, 6)
        // The tilt would otherwise let a corner overhang the screen edge.
        .padding(.trailing, 4)
        .accessibilityHidden(true)
    }

    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Availability leads, before the name — same priority as everywhere.
            HStack(spacing: 6) {
                LampIndicator(tier: tier, size: 9)
                Text(model.result.availabilityLabel)
                    .font(LK.Typography.availabilityLabel)
                    .textCase(.uppercase)
                    .tracking(0.3)
                    .foregroundStyle(tier == .unconfirmed ? LK.Palette.inkTertiary : LK.Palette.lampInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 6) {
                Text(model.result.displayName)
                    .font(LK.Typography.cookNameDetail)
                    .foregroundStyle(LK.Palette.ink)
                if model.result.isVerified {
                    // Tappable, because a blue check implies more than this one
                    // earns. Anyone who wonders what it means should be one tap
                    // from finding out, including what it does *not* cover.
                    Button { showingVerifiedInfo = true } label: {
                        VerifiedBadge(size: 19)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Permit verified. Learn what this means")
                }
            }

            Text("\(model.result.neighborhood) · \(model.result.distanceLabel)")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)

        }
    }

    /// Never asserts the cook is closed — states what's known and offers the one
    /// action that resolves it (`DESIGN_BRIEF.md` §7a).
    ///
    /// Full width, *below* the portrait row rather than inside the name column.
    /// Beside the Polaroid it had roughly half the width and wrapped to six
    /// lines — the longest and most careful sentence on the page, squeezed into
    /// the narrowest space on it.
    @ViewBuilder
    private var unconfirmedNote: some View {
        if tier == .unconfirmed {
            Text("\(firstName) turned their light on this morning and hasn't touched the app since. That usually means they're busy — sometimes it means they're done. Ask before you drive.")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LK.Palette.actionTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    /// What this cook actually said, when they said anything.
    ///
    /// This rendered a hardcoded string — "Hice 8 docenas hoy — til 6pm or
    /// sold out" — for every cook on the platform, because the view only ever
    /// had a `DiscoveryResult` and `serving_note` lives on `cooks`. It read as
    /// real copy, which is what made it survive: three different cooks showing
    /// the same sentence looks like seed data, not like a bug.
    @ViewBuilder
    private var servingNote: some View {
        if let note = model.cook?.servingNote?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader("What they said")
                Text("“\(note)”")
                    .font(.system(size: 15))
                    .italic()
                    .foregroundStyle(LK.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(LK.Palette.surfaceWarm, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }

    /// The cook's story.
    ///
    /// Every other trust signal on this screen is institutional — a permit
    /// number, a county register, a decay ladder proving someone is really
    /// there. Those establish that a kitchen is legitimate. This is the only
    /// thing that establishes that a cook is a person, which is what the
    /// product is actually asking a buyer to believe.
    @ViewBuilder
    private var storySection: some View {
        if let story = model.cook?.bio?.trimmingCharacters(in: .whitespacesAndNewlines),
           !story.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(model.result.displayName.familiarName + "'s story")
                Text(story)
                    .font(.system(size: 15))
                    .foregroundStyle(LK.Palette.inkSecondary)
                    .lineSpacing(4)
                    .lineLimit(storyExpanded ? nil : 5)
                    .fixedSize(horizontal: false, vertical: true)

                // Only offered when there is more to see. A "Read more" that
                // expands nothing is worse than no control.
                if !storyExpanded, story.count > 260 {
                    Button("Read more") {
                        withAnimation(.easeInOut(duration: 0.22)) { storyExpanded = true }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .tint(LK.Palette.action)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                LK.Palette.surfaceWarm,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
    }

    private var menuSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(model.result.isCooking ? "On today" : "Usually makes")

            GroupedCard {
                ForEach(Array((model.available + model.soldOut).enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(LK.Palette.hairline).padding(.leading, 14) }
                    Button { selectedDish = item } label: {
                        MenuDetailRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Legally required on every MEHKO listing surface, rendered from the
    /// category and the cook's agency rather than left to the cook to remember
    /// (`PRD.md` §8).
    private var permitCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: model.result.isVerified ? "checkmark.shield.fill" : "shield")
                    .font(.system(size: 14, weight: .semibold))
                Text(model.result.isVerified
                     ? "Made in a Home Kitchen · permit \(model.result.permitNumber ?? "—")"
                     : "Not yet verified")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(model.result.isVerified ? LK.Palette.action : LK.Palette.inkTertiary)

            Text(model.result.isVerified
                 ? "\(model.result.agencyName) · cooked and picked up the same day"
                 : "This cook hasn't shown us a permit yet.")
                .font(.system(size: 13))
                .foregroundStyle(LK.Palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            // Was a Button with an empty action — a control that looked
            // tappable and did nothing. The disclosure screen behind it was
            // never built, and its wording depends on the IFSI classification,
            // so shipping the button ahead of the screen promised something we
            // could not yet say. The fact it carried is stated plainly instead.
            Text("We take no payment and charge no fees. You pay \(firstName) directly.")
                .font(.system(size: 13))
                .foregroundStyle(LK.Palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(LK.Palette.actionTint, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 6) {
            Button {
                // Everything a buyer does with a cook now happens in the
                // thread. There is no claim to file: they order, or they ask,
                // and both are messages. `showingClaim` and the whole Claim
                // feature are retired (`migrations/043`).
                if model.result.isCooking {
                    showingThread = true
                } else {
                    Task {
                        try? await RootView.follows.setFollowing(true, cookID: model.result.cookID)
                        isFollowed = true
                    }
                }
            } label: {
                Text(model.result.isCooking
                     ? (isStale ? "Ask if \(firstName) is still cooking" : "Order from \(firstName)")
                     : "Turn their light on for me")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(LK.Palette.action, in: Capsule())
                    .shadow(color: LK.Palette.action.opacity(0.28), radius: 8, y: 4)
            }
            .buttonStyle(.plain)

            // A dark kitchen still needs a way to be asked something —
            // "are you cooking this weekend?" is the case messaging exists for
            // (`migrations/039`), and for a moment this button only existed on
            // lit kitchens, which removed the contact path from exactly the
            // cooks you most need to ask.
            if !model.result.isCooking, RootView.messageRepository != nil {
                Button {
                    showingThread = true
                } label: {
                    Text("Message \(firstName)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LK.Palette.action)
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.plain)
            }

            if model.result.isCooking {
                // Says what actually happens next. The old copy promised "it
                // opens a text with them", which was untrue in two different
                // ways — the `sms:` link had no recipient, and the handoff is
                // in-app now.
                Text("Opens a chat with \(firstName). You pick dishes there; nothing is charged.")
                    .font(.system(size: 12))
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, LK.Metrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var firstName: String {
        model.result.displayName.familiarName
    }

    /// Lit, but not confirmed recently enough to trust. The decay ladder's
    /// "probably, but ask" rung.
    private var isStale: Bool {
        model.result.isCooking && tier == .unconfirmed
    }

    @ViewBuilder
    private var threadSheet: some View {
        if let repo = RootView.messageRepository {
            NavigationStack {
                ThreadView(
                    model: ThreadViewModel(
                        repository: repo,
                        profiles: RootView.profileRepository,
                        subject: .cook(model.result.cookID),
                        title: firstName,
                        avatar: model.result.avatarURL,
                        myID: RootView.session?.userID
                    ).withMenu(model.menu),
                    session: RootView.session,
                    profiles: RootView.profileRepository
                )
                // On the presentation, not inside `ThreadView`: the same view
                // is *pushed* from the inbox, where a Close button would be
                // wrong and the back chevron is already correct.
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { showingThread = false }
                    }
                }
            }
        }
    }
}

private struct MenuDetailRow: View {
    let item: MenuItem

    /// A list entry, deliberately.
    ///
    /// This carried a horizontal strip of every photo, which predated the dish
    /// page. Once the row became tappable that strip was showing the same
    /// photos twice, in the worse of the two places — no counter, no
    /// thumbnails, stuck at whatever scroll offset it was last left at — and
    /// pushing rows to ~340pt so a six-dish menu took several screens to read.
    ///
    /// Photos live on the dish page now. A menu's job here is to be scannable.
    var body: some View {
        textAndPrice
    }

    /// One photo, leading.
    ///
    /// The row briefly carried the whole photo strip, which was too much, and
    /// then nothing at all, which left a dish with no description reading as a
    /// line of text against empty space. A single thumbnail is what a menu row
    /// wants: it identifies the dish at a glance and gives the row something to
    /// be built around.
    ///
    /// The count rides in its corner rather than in the trailing column — it is
    /// a fact about the photo, so it belongs on the photo, and the price then
    /// has that side to itself.
    private var thumbnail: some View {
        DishPhoto(
            urlString: item.photos.first,
            size: 66,
            cornerRadius: 15,
            isLit: item.isAvailable
        )
        .overlay(alignment: .bottomTrailing) {
            if item.photos.count > 1 {
                HStack(spacing: 2) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 8, weight: .semibold))
                    Text("\(item.photos.count)")
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(4)
            }
        }
        .opacity(item.isAvailable ? 1 : 0.6)
    }

    private var textAndPrice: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 5) {
                Text(item.displayName())
                    .font(LK.Typography.dishNameRow)
                    .foregroundStyle(LK.Palette.ink)

                if let description = item.description {
                    Text(description)
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Dish-level, always visible. Never a tooltip, never collapsed
                // — this is the one screen where a UI shortcut is a safety bug.
                if !item.allergens.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(item.allergens, id: \.self) { allergen in
                            Text(allergen)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(LK.Palette.allergenInk)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(LK.Palette.allergenBG, in: Capsule())
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                // The same warm pill the feed card, the map pin and the order
                // sheet use, so a price is one recognisable object everywhere.
                // Greyed when sold out: an amber pill is a live offer.
                Text(item.price.display)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(item.isAvailable ? Color(hex: 0x5A3900) : LK.Palette.inkTertiary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        item.isAvailable ? LK.Palette.lampTint : LK.Palette.chipNeutral,
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            item.isAvailable ? LK.Palette.lamp.opacity(0.35) : .clear,
                            lineWidth: 1.5
                        )
                    )
                if item.price.minQuantity > 1 {
                    Text("min \(item.price.minQuantity)")
                        .font(.system(size: 12))
                        .foregroundStyle(LK.Palette.inkTertiary)
                }
                if !item.isAvailable {
                    Text("Sold out")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(LK.Palette.chipNeutral, in: Capsule())
                        .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .opacity(item.isAvailable ? 1 : 0.5)
    }
}
