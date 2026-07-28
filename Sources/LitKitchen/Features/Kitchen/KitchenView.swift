import Observation
import SwiftUI

@Observable
@MainActor
final class KitchenViewModel {
    private let repository: any CookRepository
    let cookID: UUID

    var session: ServingSession?
    var items: [MenuItem] = []
    var errorMessage: String?

    init(repository: any CookRepository, cookID: UUID) {
        self.repository = repository
        self.cookID = cookID
    }

    var isOpen: Bool { session?.isOpen == true }

    /// Whether this kitchen has ever served. Distinguishes "closed for the day"
    /// from "brand new" — the same state in `currentSession()`, which returns
    /// nil for both, and wanting very different words.
    ///
    /// Loaded separately for exactly that reason: deriving it from `session`
    /// made it a synonym for `isOpen`, so every cook who closed up was greeted
    /// as a newcomer over their own menu.
    var hasEverOpened = false

    /// The cook's own story. Loaded here so the Kitchen tab can show whether
    /// one has been written without a second round trip when the sheet opens.
    var story: String = ""
    /// The cook's own serving note, from the same fetch as the story.
    var servingNote: String?
    /// The kitchen's cover photo. Nil means the profile falls back to the
    /// headline dish.
    var coverURL: String?

    var sinceLabel: String? {
        guard let session, session.isOpen else { return nil }
        return "since " + ServingSession.clockFormatter.string(from: session.openedAt).lowercased()
    }

    /// Advisory only, and labelled as partial wherever it appears. We can only
    /// count what came through the app; DM orders are invisible to us, so
    /// presenting this as a total would tell a cook they have headroom they
    /// may not have (`PRD.md` §8).
    var claimedToday: Int { 0 }

    func load() async {
        do {
            session = try await repository.currentSession()
            hasEverOpened = (try? await repository.hasEverServed()) ?? (session != nil)
            items = try await repository.menuItems()
            // Non-fatal and non-blocking: a kitchen with no story is the
            // normal case on day one, and failing to read it must not report
            // the kitchen as unreachable.
            let profile = try? await RootView.discoveryRepository.cook(cookID)
            story = profile?.bio ?? ""
            servingNote = profile?.servingNote
            coverURL = profile?.coverURL
            if let name = profile?.displayName, !name.isEmpty { shareName = name }
        } catch {
            errorMessage = UserFacingError.message(for: error, fallback: "Couldn't reach your kitchen. Try again in a moment.")
        }
    }

    func openKitchen() async {
        do { session = try await repository.openKitchen(note: nil) }
        catch { errorMessage = UserFacingError.message(for: error, fallback: "Couldn't reach your kitchen. Try again in a moment.") }
    }

    func closeKitchen() async {
        do {
            try await repository.closeKitchen(reason: "cook")
            session = try await repository.currentSession()
        } catch { errorMessage = UserFacingError.message(for: error, fallback: "Couldn't reach your kitchen. Try again in a moment.") }
    }

    func setAvailability(_ available: Bool, for item: MenuItem) async {
        do {
            try await repository.setAvailability(available, for: item.id)
            items = try await repository.menuItems()
            session = try await repository.currentSession()
        } catch { errorMessage = UserFacingError.message(for: error, fallback: "Couldn't reach your kitchen. Try again in a moment.") }
    }

    /// Promotes a dish to the top of the menu — and therefore to the feed
    /// card. Reloads because the server renumbers every row, not just this one.
    func makeHeadline(_ item: MenuItem) async {
        do {
            try await repository.setHeadline(item.id)
            items = try await repository.menuItems()
        } catch { errorMessage = UserFacingError.message(for: error, fallback: "Couldn't reach your kitchen. Try again in a moment.") }
    }

    func setCover(_ url: String?) async {
        do {
            try await CookProfileWriter().setCover(url)
            coverURL = url
        } catch {
            errorMessage = UserFacingError.message(
                for: error, fallback: "Couldn't save that photo. Try again in a moment."
            )
        }
    }

    /// What to print under the QR code — the cook's own name, from the same
    /// profile fetch as the story. Falls back to something that still reads as
    /// a kitchen rather than leaving the card blank.
    var shareName: String = "Your kitchen"

    func add(_ item: MenuItem) async {
        do {
            try await repository.save(item)
            items = try await repository.menuItems()
        } catch { errorMessage = UserFacingError.message(for: error, fallback: "Couldn't reach your kitchen. Try again in a moment.") }
    }

    /// Removes a dish for good.
    ///
    /// Reloads the whole list rather than dropping the row locally: deleting
    /// the headline promotes whatever was second to the feed card, and the
    /// cook should watch that happen rather than find out from a buyer.
    func delete(_ item: MenuItem) async {
        do {
            try await repository.delete(item.id)
            items = try await repository.menuItems()
        } catch { errorMessage = UserFacingError.message(for: error, fallback: "Couldn't remove that dish. Try again in a moment.") }
    }
}

struct KitchenView: View {
    @State var model: KitchenViewModel
    @State private var showingMenuBuilder = false
    /// Non-nil while editing an existing dish.
    @State private var editingItem: MenuItem?
    /// The data travels *with* the presentation rather than alongside it.
    /// `.sheet(isPresented:)` captures the view's state at the moment it
    /// presents, so setting the claims and the flag in the same update showed
    /// a sheet that said "0 claims are still open" while four were.
    @State private var closeOut: CloseOutPrompt?
    @State private var showingStory = false
    /// Non-nil while confirming a deletion.
    @State private var deletingItem: MenuItem?
    @State private var showingShare = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                burnerBlock
                if model.isOpen { whatTheySeeCard }
                menuBlock
                coverBlock
                storyBlock
                shareBlock
                footer
            }
            .padding(LK.Metrics.screenPadding)
        }
        // The floating tab bar overlays the scroll view, so the last row and
        // the footer sat underneath it at rest. Verified in the simulator:
        // "we turn the burner off" was unreachable without scrolling
        // past the end.
        .contentMargins(.bottom, 28, for: .scrollContent)
        .background(model.isOpen ? LK.Palette.ground : LK.Palette.ground)
        .task { await model.load() }
        .sheet(isPresented: $showingMenuBuilder) {
            MenuBuilderView(cookID: model.cookID) { item in
                Task { await model.add(item) }
            }
        }
        .sheet(item: $closeOut) { prompt in
            CloseOutSheet(orders: prompt.orders) { order, pickedUp in
                guard pickedUp, let repo = RootView.messageRepository else { return }
                // Only a pickup is recorded. "Didn't come" deliberately writes
                // nothing: a no-show is the cook's word against an absent
                // buyer, and there is no appeal from a mark on a stranger's
                // record. It closes the row here and nowhere else.
                Task { try? await repo.markPickedUp(in: order.conversationID) }
            }
        }
        // Deliberately steers to the reversible option. Most of the time a cook
        // reaching for "delete" has run out for the day, and sold-out is one
        // tap away on the row itself.
        .confirmationDialog(
            "Delete this dish?",
            isPresented: Binding(
                get: { deletingItem != nil },
                set: { if !$0 { deletingItem = nil } }
            ),
            presenting: deletingItem
        ) { item in
            Button("Delete \(item.displayName())", role: .destructive) {
                Task { await model.delete(item) }
                deletingItem = nil
            }
            Button("Keep it", role: .cancel) { deletingItem = nil }
        } message: { _ in
            Text("This takes it off your menu for good. If you're just out today, mark it sold out instead.")
        }
        .sheet(isPresented: $showingShare) {
            ShareKitchenSheet(cookID: model.cookID, displayName: model.shareName)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingStory) {
            CookStorySheet(cookID: model.cookID, story: model.story) { saved in
                model.story = saved
            }
        }
        .sheet(item: $editingItem) { item in
            MenuBuilderView(cookID: model.cookID, editing: item) { updated in
                Task { await model.add(updated) }
            }
        }
    }

    /// Asked at close of service, not on a timer. A cook who has just turned
    /// their light off is finished and looking at the phone — every other
    /// moment is an interruption.
    private func askAboutOpenOrders() async {
        guard let repo = RootView.messageRepository,
              let open = try? await repo.openOrders(), !open.isEmpty else { return }
        closeOut = CloseOutPrompt(orders: open)
    }

    /// The kitchen's cover photo.
    ///
    /// Sits beside the story because they are the same kind of thing — the two
    /// places a cook says who they are rather than what is for sale. Both are
    /// set once and then left alone, which is why neither gets prime space
    /// above the burner.
    private var coverBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PhotoPickerTile(
                    photoURL: Binding(
                        get: { model.coverURL },
                        // Named, not `$0`: inside the `Task` the shorthand
                        // binds to the task's own closure, not the setter's.
                        set: { newURL in Task { await model.setCover(newURL) } }
                    ),
                    kind: .dish,
                    size: 84,
                    cornerRadius: 18,
                    emptyLabel: "Add cover"
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Your kitchen photo")
                        .font(LK.Typography.ui(16, weight: .semibold))
                        .foregroundStyle(LK.Palette.ink)
                    Text(model.coverURL == nil
                         ? "The top of your page. Your counter mid-service, the whole spread, a pot going — not a dish, and not a logo."
                         : "Shown at the top of your kitchen page.")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    if model.coverURL != nil {
                        Button("Use my first dish instead") {
                            Task { await model.setCover(nil) }
                        }
                        .font(LK.Typography.ui(13.5, weight: .semibold))
                        .tint(LK.Palette.action)
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous)
                    .strokeBorder(LK.Palette.hairline, lineWidth: 1)
            }
        }
    }

    /// The story, as a row rather than an always-open text field.
    ///
    /// A cook opens this screen to turn their light on and mark things sold
    /// out — both several times a day. Writing a story happens once. Giving it
    /// an editor inline would put the rarest action in the most valuable
    /// space; a row states it exists, shows whether it's done, and gets out of
    /// the way.
    private var storyBlock: some View {
        Button { showingStory = true } label: {
            HStack(spacing: 12) {
                Image(systemName: model.story.isEmpty ? "book.closed" : "book")
                    .font(LK.Typography.navBar)
                    .foregroundStyle(LK.Palette.heatInk)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Your story")
                        .font(LK.Typography.ui(16, weight: .semibold))
                        .foregroundStyle(LK.Palette.ink)
                    Text(model.story.isEmpty
                         ? "Tell buyers why you cook — it's the only thing here that isn't a permit number."
                         : model.story)
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(LK.Typography.ui(13.5, weight: .semibold))
                    .foregroundStyle(LK.Palette.inkTertiary)
            }
            .padding(14)
            .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous)
                    .strokeBorder(LK.Palette.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var burnerBlock: some View {
        VStack(spacing: 14) {
            BurnerDial(
                isOn: model.isOpen,
                hasEverOpened: model.hasEverOpened,
                sinceLabel: model.sinceLabel,
                onToggle: {
                    Task {
                        if model.isOpen {
                            await model.closeKitchen()
                            // Still asked, and now doing double duty: it is
                            // also the receipt for a close that is only one tap
                            // away from happening by accident.
                            await askAboutOpenOrders()
                        } else {
                            await model.openKitchen()
                        }
                    }
                }
            )
            .padding(.top, 24)

            if model.isOpen {
                Text("You're cooking")
                    .font(LK.Typography.screenTitle)
                    .foregroundStyle(LK.Palette.ink)
                Text("Neighbours can see your light · tap the dial to close")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
            } else if model.hasEverOpened {
                // Closing is the most useful thing a cook does here, so the
                // empty state thanks them for it rather than nagging them back.
                Text("Your light's off. Thanks for turning it off.")
                    .font(LK.Typography.titleSecondary)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LK.Palette.ink)
                Text("Closing on time is the most useful thing you do here — nobody drove over for nothing.")
                    .font(LK.Typography.meta)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .padding(.horizontal, 8)
            } else {
                // A kitchen that has never opened. Thanking someone for turning
                // off a light they never turned on reads as a form letter, and
                // it wastes the one screen a new cook is definitely looking at.
                Text("Your kitchen is ready")
                    .font(LK.Typography.titleSecondary)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LK.Palette.ink)
                Text("Add what you make, then tap the dial when you're cooking. Neighbours only see you while your light is on.")
                    .font(LK.Typography.meta)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .padding(.horizontal, 8)
            }
        }
    }

    /// The cook's own note, as buyers see it.
    ///
    /// This was the *same* hardcoded sentence as the buyer-side card — the bug
    /// existed twice, on both sides of the same field, which is why three
    /// different cooks showing one Spanish line about eight dozen looked like
    /// seed data rather than a defect.
    @ViewBuilder
    private var whatTheySeeCard: some View {
        if let note = model.servingNote?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader("What they see")
                Text("“\(note)”")
                    .font(LK.Typography.body)
                    .italic()
                    .foregroundStyle(LK.Palette.inkQuiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous))
        }
    }

    private var menuBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(model.isOpen ? "Today's menu" : "Your menu")
                Spacer()
                Button {
                    showingMenuBuilder = true
                } label: {
                    // No `+` glyph — the label is the affordance, and the
                    // glyph only repeated it at half the legibility.
                    Text("Add dish")
                        .font(LK.Typography.bodyEmphasis)
                }
                .tint(LK.Palette.action)
            }

            if model.items.isEmpty {
                Text("No dishes yet. Add what you make — you only do this once.")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                GroupedCard {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(LK.Palette.hairline).padding(.leading, 14) }
                        MenuRow(
                            item: item,
                            kitchenIsOpen: model.isOpen,
                            // The first row is what buyers see on the feed card.
                            // Saying so here is the only place a cook can learn
                            // it, and the only place they can change it.
                            isHeadline: index == 0,
                            onEdit: { editingItem = item },
                            onMakeHeadline: { Task { await model.makeHeadline(item) } },
                            onDelete: { deletingItem = item }
                        ) { available in
                            Task { await model.setAvailability(available, for: item) }
                        }
                    }
                }
            }
        }
    }

    /// Where a cook gets something to paste where their buyers already are.
    /// Placed with the menu rather than buried in settings: it is a growth
    /// action, and it belongs next to the thing being shared.
    private var shareBlock: some View {
        Button {
            showingShare = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "qrcode")
                    .font(LK.Typography.bodyEmphasis)
                    .foregroundStyle(LK.Palette.action)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share your kitchen")
                        .font(LK.Typography.navBar)
                        .foregroundStyle(LK.Palette.ink)
                    Text("A link and a QR code for your buyers")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
            }
            .padding(14)
            .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        Text(model.isOpen
             ? "Serve as late as you like. If you go quiet for ten hours, we turn it off for you."
             : "Your dishes and prices stay saved. Just tap the dial next time you cook.")
            .font(LK.Typography.meta)
            .foregroundStyle(LK.Palette.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MenuRow: View {
    let item: MenuItem
    /// Whether the burner is on. An available dish is only *cooking* if the
    /// kitchen is.
    var kitchenIsOpen: Bool = true
    var isHeadline: Bool = false

    /// Amber only when the dish is genuinely on a lit burner.
    private var isHot: Bool { item.isAvailable && kitchenIsOpen }

    private var badgeLabel: String {
        if !item.isAvailable { return "Sold out" }
        // Closed but available: it's on the menu for next time, not cooking now.
        return kitchenIsOpen ? "Cooking" : "On the menu"
    }

    var onEdit: () -> Void = {}
    var onMakeHeadline: () -> Void = {}
    var onDelete: () -> Void = {}
    let onAvailabilityChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // The dish's own photo, so a cook can see at a glance which ones
            // still need one.
            DishPhoto(urlString: item.photoURL, size: 52, isLit: item.isAvailable)

            VStack(alignment: .leading, spacing: 5) {
                if isHeadline {
                    Text("Shown first")
                        .font(LK.Typography.ui(10.5, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .foregroundStyle(LK.Palette.inkTertiary)
                }
                Text(item.displayName())
                    .font(LK.Typography.dishNameRow)
                    .foregroundStyle(item.isAvailable ? LK.Palette.ink : LK.Palette.inkTertiary)

                if !item.allergens.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(item.allergens, id: \.self) { allergen in
                            Text(allergen)
                                .font(LK.Typography.ui(12, weight: .semibold))
                                .foregroundStyle(LK.Palette.ink)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(LK.Palette.chip, in: Capsule())
                        }
                    }
                }

                Text(item.price.displayWithMinimum)
                    .font(LK.Typography.ui(14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(LK.Palette.inkQuiet)
            }

            Spacer(minLength: 8)

            // Per-item sold-out: a cook runs out of tamales but keeps selling
            // champurrado without closing the whole kitchen.
            Button {
                onAvailabilityChange(!item.isAvailable)
            } label: {
                // Three states, not two. The badge used to read `isAvailable`
                // alone, so a closed kitchen showed amber "Cooking" chips
                // directly under "Your light's off" — the screen contradicting
                // itself, and amber asserting heat with the burner dark.
                //
                // Availability is still a real and separate fact when closed:
                // it is what the dish will be when the light next goes on, and
                // the cook can still set it. So the sold-out state is unchanged
                // and only the affirmative label stands down.
                // A neutral chip with a marigold dot, not an amber fill. The
                // fill made a badge look like a light source; the dot says
                // "live" without the chip itself claiming to be heat.
                HStack(spacing: 5) {
                    if isHot {
                        Circle()
                            .fill(LK.Palette.heat)
                            .frame(width: 6, height: 6)
                    }
                    Text(badgeLabel)
                        .font(LK.Typography.ui(12, weight: .semibold))
                        .foregroundStyle(isHot ? LK.Palette.ink : LK.Palette.inkTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(LK.Palette.chip, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .opacity(item.isAvailable ? 1 : 0.55)
        .contentShape(Rectangle())
        // Tap the row to edit. The sold-out chip is a Button, so it keeps its
        // own hit area and this doesn't swallow it.
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("Edit dish", systemImage: "pencil", action: onEdit)
            if !isHeadline {
                Button("Show this one first", systemImage: "arrow.up.to.line", action: onMakeHeadline)
            }
            // Last, and separated by role, because the chip beside it already
            // covers the thing cooks actually want most of the time: "not
            // today" is sold-out, not deletion.
            Button("Delete dish", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to edit this dish")
    }
}
