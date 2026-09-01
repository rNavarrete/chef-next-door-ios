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
    @State private var askingPush = false
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
        .background(LK.Palette.ground)
        .task {
            await model.load()
            isFollowed = ((try? await RootView.follows.follows()) ?? [])
                .contains { $0.cookID == model.result.cookID }
            await loadTrust()
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) { backButton }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) { safetyMenu; followButton }
        }
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
        .sheet(isPresented: $askingPush) {
            PushSoftAsk(
                title: "We'll tell you when \(firstName) starts cooking",
                message: "That's what following is for. Without notifications we've no way to reach you.",
                onDecided: { OnboardingFlag.pushBuyer.set() }
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
                    SectionHeader("What neighbors said")
                    Spacer(minLength: 0)
                    // Count always next to the average. "5.0" from one review
                    // and "4.6" from ninety are not the same claim.
                    Text("\(rating.average.map { String(format: "%.1f", $0) } ?? "—") · \(rating.reviewCount) review\(rating.reviewCount == 1 ? "" : "s")")
                        .font(LK.Typography.ui(13.5, weight: .semibold))
                        .foregroundStyle(LK.Palette.inkQuiet)
                }

                GroupedCard {
                    ForEach(Array(reviews.prefix(5).enumerated()), id: \.element.id) { index, review in
                        if index > 0 { Divider().overlay(LK.Palette.hairline).padding(.leading, 14) }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 3) {
                                ForEach(1...5, id: \.self) { star in
                                    Image(systemName: star <= review.rating ? "star.fill" : "star")
                                        .font(LK.Typography.ui(12))
                                        .foregroundStyle(star <= review.rating
                                                         ? LK.Palette.heat
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
    /// Today's food while they are cooking; the kitchen's own photo otherwise.
    ///
    /// The cover won unconditionally, so the largest image on the page could
    /// show something nobody could buy — Mateos' hero is a bowl of mashed
    /// potato and the only dish on today is sushi. Product-card guidance is
    /// consistent that the most important content goes highest and largest, and
    /// on a page whose whole job is "should I get food from this person
    /// tonight", the most important content is tonight's food.
    ///
    /// The cover is not discarded, it is re-scoped: it is the kitchen's
    /// identity, which is exactly what you want to see when there is no
    /// "today" to show. A closed kitchen still gets the photograph the cook
    /// chose to represent themselves.
    private var heroPhoto: String? {
        if model.result.isCooking, let dish = model.result.headlinePhoto {
            return dish
        }
        return model.cook?.coverURL ?? model.result.headlinePhoto
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
                colors: [.clear, LK.Palette.ground.opacity(0.4)],
                startPoint: .center, endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .frame(height: heroHeight)
        .overlay(alignment: .topLeading) {
            // Amber wash from the top-left, as if the light came from inside.
            LinearGradient(
                colors: [LK.Palette.heat.opacity(model.result.isCooking ? 0.28 : 0), .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            // The status bar sits on top of this photo and is drawn in white.
            // Over Mateos' pale mashed potato the clock was barely readable —
            // the feed already solves this with a frosted strip, and the page
            // with the *largest* photo in the app had nothing.
            //
            // A gradient rather than a bar: it has to disappear over a dark
            // photo, where a strip would be a grey band across somebody's food.
            LinearGradient(
                colors: [.black.opacity(0.28), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 96)
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
                .font(LK.Typography.ui(16, weight: .semibold))
                .foregroundStyle(LK.Palette.ink)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.leading, LK.Metrics.feedGutter)
        .padding(.top, 6)
    }

    /// Report and block, in the place a reviewer looks for them.
    ///
    /// These actions already existed at the foot of the page, deliberately
    /// understated — the comment on `safetyActions` says they "must exist, and
    /// be findable without a search". They were not found: App Review rejected
    /// the app under Guideline 1.2 on 30 August 2026 reporting no mechanism to
    /// flag content or block a user, having evidently never scrolled to them.
    ///
    /// Understatement was the wrong instinct for a safety control. The
    /// convention on iOS is an overflow menu in the top-right corner, that is
    /// where anyone looks first, and a person who needs to block someone is
    /// having a bad time already. Both placements are kept: this one is found,
    /// the one at the foot is read.
    private var safetyMenu: some View {
        Menu {
            Button("Report this kitchen", systemImage: "flag") { showingReport = true }
            Button(
                isBlocked ? "Unblock this kitchen" : "Block this kitchen",
                systemImage: isBlocked ? "hand.raised.slash" : "hand.raised",
                role: isBlocked ? nil : .destructive
            ) { showingBlockConfirm = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(LK.Typography.bodyEmphasis)
                .foregroundStyle(LK.Palette.ink)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(.top, 6)
        .accessibilityLabel("Report or block this kitchen")
    }

    private var followButton: some View {
        Button {
            Task {
                let nowFollowing = !isFollowed
                try? await RootView.follows.setFollowing(nowFollowing, cookID: model.result.cookID)
                isFollowed.toggle()
                // Following *is* a request to be told. Asking here rather than
                // on launch means the sentence explaining why is the thing they
                // just did.
                if nowFollowing, await OnboardingFlag.shouldAsk(.pushBuyer) {
                    askingPush = true
                }
            }
        } label: {
            Image(systemName: isFollowed ? "heart.fill" : "heart")
                .font(LK.Typography.bodyEmphasis)
                .foregroundStyle(isFollowed ? LK.Palette.action : LK.Palette.ink)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, LK.Metrics.feedGutter)
        .padding(.top, 6)
        .accessibilityLabel(isFollowed ? "Following" : "Tell me when they're cooking")
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            availabilityAndName
            unconfirmedNote
            // Who this person is, before what they are selling — it is the
            // answer to "why would I walk to a stranger's house", which a buyer
            // asks before reading prices.
            voiceBlock
            menuSection
            permitCard
            reviewsSection
            safetyActions
        }
        .padding(LK.Metrics.screenPadding)
        .background(
            LK.Palette.ground,
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
        // `in: Rectangle()` is load-bearing — do not simplify it away.
        //
        // A bare `.background(style)` adopts the enclosing container's shape,
        // and the container here is the content card, an
        // `UnevenRoundedRectangle` with 24pt top corners. The frame was
        // inheriting exactly that: rounded across the top, square along the
        // bottom. A Polaroid with rounded corners is not a Polaroid, and the
        // stroke below stayed square the whole time, so the cream sat inside a
        // hairline that no longer traced it.
        //
        // Invisible until the frame moved onto the hero — against flat ground
        // the rounding read as nothing; against a photograph it read as a bug.
        .background(LK.Palette.printPaper, in: Rectangle())
        .overlay {
            // A hairline so the white frame does not dissolve into a light
            // ground. On night blue it needs no help.
            Rectangle().stroke(LK.Palette.hairline, lineWidth: 1)
        }
        .shadow(color: Color(hex: 0x14161A).opacity(0.22), radius: 8, y: 5)
        // Off-square, and tilted *away* from the name so the gap between them
        // opens rather than pinches.
        .rotationEffect(.degrees(3.5))
        // Taped over the seam where the hero meets the card, rather than
        // sitting inside the card below it.
        //
        // The frame is about 130pt tall and the three lines beside it are
        // about 90, so the Polaroid was setting the height of the row and
        // every kitchen without a story got 40pt of blank card between its
        // address and its menu. Mateos' page opened on a visible hole.
        //
        // The offset lifts it; the matching negative padding stops it claiming
        // the height it no longer occupies, which is what actually closes the
        // gap — offset alone moves the picture and leaves the space behind.
        .offset(y: -52)
        .padding(.bottom, -52)
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
                    .font(LK.Typography.caps)
                    .textCase(.uppercase)
                    .tracking(0.3)
                    .foregroundStyle(tier == .unconfirmed ? LK.Palette.inkTertiary : LK.Palette.heatInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 6) {
                Text(model.result.displayName)
                    .font(LK.Typography.screenTitle)
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

            // Measured from the browsing origin, not from `distanceM`.
            //
            // A result reached from the map carries a distance the server
            // measured from the *map's centre*, because that is what the map
            // queried around. `MapView` already knows this and renders
            // `distanceLabel(from:)`; this screen did not, so the same kitchen
            // read 8.1 mi on the map sheet and 6.4 mi here, one tap apart.
            //
            // Of the two, this was the wrong one — and on the worse screen,
            // since this is where somebody decides whether to drive.
            Text("\(model.result.neighborhood) · \(model.result.travelTime(from: RootView.origin.coordinate).label)")
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
            Text("\(firstName) said they were cooking this morning and hasn't opened the app since. That usually means they're busy — sometimes it means they're done. Ask before you drive.")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkQuiet)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LK.Palette.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    /// The cook's own words, and their story under it.
    ///
    /// These were two tinted cards stacked above a third — a quote box, a story
    /// box and the permit card, three rounded rectangles in a column with small
    /// caps headers, differing only in tint. They are different *kinds* of
    /// thing and rendering them identically flattened all three.
    ///
    /// The quote is now set as a quote: italic against a heat rule, with the
    /// story as a quiet line beneath it and no card of its own. That leaves the
    /// permit as the only card object on the page, which is what "the main
    /// trust signal" should actually look like.
    @ViewBuilder
    private var voiceBlock: some View {
        let note = model.cook?.servingNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let story = model.cook?.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !note.isEmpty || !story.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                // The one place a rule of heat is right: this is the cook
                // speaking about service happening now.
                Rectangle()
                    .fill(LK.Palette.heat)
                    .frame(width: 2)

                VStack(alignment: .leading, spacing: 6) {
                    if !note.isEmpty {
                        Text("\u{201C}\(note)\u{201D}")
                            .font(LK.Typography.fieldValue)
                            .italic()
                            .foregroundStyle(LK.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !story.isEmpty {
                        Text(story)
                            .font(LK.Typography.meta)
                            .foregroundStyle(LK.Palette.inkTertiary)
                            .lineSpacing(2)
                            .lineLimit(storyExpanded ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)

                        if !storyExpanded, story.count > 180 {
                            Button("Read more") {
                                withAnimation(.easeInOut(duration: 0.22)) { storyExpanded = true }
                            }
                            .font(LK.Typography.bodyEmphasis)
                            .tint(LK.Palette.action)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(LK.Typography.ui(14, weight: .semibold))
                Text(model.result.isVerified
                     ? "Made in a Home Kitchen · permit \(model.result.permitNumber ?? "—")"
                     : "Not yet verified")
                    .font(LK.Typography.ui(14, weight: .bold))
            }
            .foregroundStyle(model.result.isVerified ? LK.Palette.action : LK.Palette.inkTertiary)

            Text(model.result.isVerified
                 ? "\(model.result.agencyName) · cooked and picked up the same day"
                 : "This cook hasn't shown us a permit yet.")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            // Was a Button with an empty action — a control that looked
            // tappable and did nothing. The disclosure screen behind it was
            // never built, and its wording depends on the IFSI classification,
            // so shipping the button ahead of the screen promised something we
            // could not yet say. The fact it carried is stated plainly instead.
            Text("We take no payment and charge no fees. You pay \(firstName) directly.")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(LK.Palette.chip, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
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
                     : "Tell me when they're cooking")
                    .font(LK.Typography.navBarEmphasis)
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
                        .font(LK.Typography.bodyEmphasis)
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
                    .font(LK.Typography.ui(12))
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
        .opacity(item.isAvailable ? 1 : 0.6)
    }

    /// Minimum and photo count, folded into one line.
    ///
    /// Seven fields became five. These were separate rows of chrome answering
    /// small questions; as one grey line they answer the same ones and the eye
    /// skips them unless it cares. Allergens are *not* folded in — they are a
    /// safety surface and keep their own row.
    private var secondaryLine: String? {
        var parts: [String] = []
        if item.price.minQuantity > 1 { parts.append("min \(item.price.minQuantity)") }
        if item.photos.count > 1 { parts.append("\(item.photos.count) photos") }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private var textAndPrice: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName())
                    .font(LK.Typography.dishNameRow)
                    .foregroundStyle(item.isAvailable ? LK.Palette.ink : LK.Palette.inkQuiet)

                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let meta = secondaryLine {
                    Text(meta)
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                }

                if !item.allergens.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(item.allergens, id: \.self) { allergen in
                            Text(allergen)
                                .font(LK.Typography.ui(13.5))
                                .foregroundStyle(LK.Palette.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(LK.Palette.chip, in: Capsule())
                        }
                    }
                    .padding(.top, 1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.price.figure)
                    .font(LK.Typography.dishNameRow)
                    .monospacedDigit()
                    .foregroundStyle(item.isAvailable ? LK.Palette.ink : LK.Palette.inkTertiary)
                Text(item.price.unitLabel)
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                if !item.isAvailable {
                    Text("Sold out")
                        .font(LK.Typography.ui(12, weight: .semibold))
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(LK.Palette.chip, in: Capsule())
                        .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .opacity(item.isAvailable ? 1 : 0.5)
    }
}
