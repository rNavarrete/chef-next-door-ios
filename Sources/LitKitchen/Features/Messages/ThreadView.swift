import Observation
import SwiftUI

@Observable
@MainActor
final class ThreadViewModel {
    private let repository: any MessageRepository
    private let profiles: (any ProfileRepository)?

    /// Either an existing thread, or a cook to open one with. A thread doesn't
    /// exist until the first message lands, so "message this cook" and "open
    /// this conversation" are genuinely different starting states.
    enum Subject: Hashable {
        case thread(UUID)
        case cook(UUID)
    }

    var subject: Subject
    let title: String
    let avatar: String?
    let avatarNeedsSigning: Bool
    /// The claim that prompted this, threaded through so a message sent from a
    /// claim screen records what it was about.
    let claimID: UUID?

    /// The person on the other side, whichever side that is. Set from the
    /// conversation, because `subject` only carries a cook — a thread opened
    /// from the inbox by a cook has no id in it for the buyer at all.
    var otherPartyID: UUID?

    /// Where tapping the name should go. A cook is a kitchen with a public
    /// page; a buyer is a person with a history, and only their cook may see
    /// it.
    var otherParty: OtherParty? {
        let cook = state?.iAmTheCook ?? iAmTheCook
        if cook { return otherPartyID.map(OtherParty.buyer) }
        if let id = otherPartyID ?? cookIDForOrdering { return .cook(id) }
        if case .cook(let id) = subject { return .cook(id) }
        return nil
    }

    enum OtherParty: Hashable, Identifiable {
        case cook(UUID)
        case buyer(UUID)
        var id: UUID { switch self { case .cook(let i), .buyer(let i): i } }
    }

    var messages: [Message] = []
    var draft = ""
    var isLoading = false
    var isSending = false
    var errorMessage = ""
    /// Set when the server refuses for a fixable reason; the view presents the
    /// gate sheet rather than an error.
    var gate: MessagingGate?

    var myID: UUID?

    /// Where the thread has got to. Drives the action bar, and it is server
    /// state rather than something inferred from the message list — a client
    /// that decided "address shared" by scanning for a marker would get it
    /// wrong the moment a message failed to load.
    var state: ThreadState?
    var address: RevealedAddress?
    var isWorking = false

    var canOrder: Bool { !(state?.iAmTheCook ?? iAmTheCook) }

    init(
        repository: any MessageRepository,
        profiles: (any ProfileRepository)? = nil,
        subject: Subject,
        title: String,
        avatar: String? = nil,
        avatarNeedsSigning: Bool = false,
        claimID: UUID? = nil,
        myID: UUID? = nil,
        iAmTheCook: Bool = false
    ) {
        self.repository = repository
        self.profiles = profiles
        self.subject = subject
        self.title = title
        self.avatar = avatar
        self.avatarNeedsSigning = avatarNeedsSigning
        self.claimID = claimID
        self.myID = myID
        self.iAmTheCook = iAmTheCook
    }

    var threadID: UUID? {
        if case .thread(let id) = subject { return id }
        return nil
    }

    func load() async {
        guard let threadID else { return }   // nothing to load until it exists
        isLoading = true
        defer { isLoading = false }
        do {
            messages = try await repository.messages(in: threadID)
            try await repository.markRead(threadID)
            // Straight after `markRead`, because a thread opened from a
            // notification is the one path that never touches the inbox — and
            // so the one path where nothing else would ever correct the badge.
            if let total = try? await repository.unreadTotal() {
                await PushRegistrar.shared.setBadge(total)
            }
            state = try await repository.state(of: threadID)
            // Only fetched once actually disclosed — asking earlier would throw
            // 'not authorized' every time and bury a real failure in noise.
            if state?.addressShared == true {
                address = try? await repository.address(in: threadID)
            }
            await syncActivity()
            // Here rather than in the view's `.task`: a thread opened from
            // "Order from Ana" has no id until the first order creates it, so
            // subscribing on appear would silently never happen for exactly the
            // conversation the buyer is waiting on. `startListening` is guarded,
            // so calling it on every load is a no-op after the first.
            startListening()
        } catch {
            errorMessage = UserFacingError.message(
                for: error, fallback: "Couldn't load this conversation."
            )
        }
    }

    /// Puts the order on the buyer's Lock Screen, and takes it off again.
    ///
    /// Nothing called this before: 045 wired the *server* side of the Live
    /// Activity, but the only code that ever started a card was `SpikeHarness`,
    /// so in the real app one was never created — and a card that is never
    /// created doesn't fail, it just silently isn't there.
    ///
    /// Buyer only. A cook has the order in their inbox and does not need a
    /// Lock Screen card about their own kitchen.
    private func syncActivity() async {
        guard #available(iOS 16.2, *), let threadID, let state, !state.iAmTheCook else { return }
        guard let order = messages.last(where: { $0.kind == .order }) else { return }

        let manager = CookingActivityManager.shared

        // Picked up: the card's job is done. Ending it here as well as on push
        // matters because the push only lands if a token was registered, and
        // the buyer may have opened the thread instead of glancing at the card.
        if state.pickedUp {
            if let existing = manager.activity(forThread: threadID.uuidString) {
                await manager.end(existing)
            }
            return
        }

        let items = order.payload?.lines
            .map { "\($0.quantity)× \($0.displayName())" }
            .joined(separator: ", ") ?? order.body
        let total = order.payload.map { String(format: "$%.2f", Double($0.totalCents) / 100) } ?? ""

        await manager.sync(
            attributes: .init(cookName: state.cookName, threadID: threadID.uuidString),
            state: .init(
                stage: state.addressShared ? .confirmed : .waiting,
                cookIsCooking: state.cookIsCooking,
                itemSummary: items,
                priceSummary: total,
                addressLine: address?.singleLine ?? "",
                sinceLabel: Self.sinceLabel(for: state.orderedAt ?? order.createdAt),
                directionsURL: address.flatMap {
                    URL(string: "maps://?daddr=\($0.latitude),\($0.longitude)")
                }
            )
        )
    }

    /// "since 2:15 pm" — absolute clock time, never elapsed. Same rule the
    /// server payload uses, and the reason is the same: a buyer glancing at a
    /// Lock Screen wants to know when, not how long ago.
    private static func sinceLabel(for date: Date) -> String {
        "since " + date.formatted(date: .omitted, time: .shortened).lowercased()
    }

    func placeOrder(_ items: [(MenuItem, Int)], note: String?) async {
        guard !items.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            switch subject {
            case .cook(let cookID):
                _ = try await repository.postOrder(to: cookID, items: items, note: note)
                if let opened = try? await repository.conversations()
                    .first(where: { $0.cookID == cookID }) {
                    subject = .thread(opened.id)
                }
            case .thread:
                guard let cookID = cookIDForOrdering else { return }
                _ = try await repository.postOrder(to: cookID, items: items, note: note)
            }
            await PushRegistrar.shared.requestAuthorizationIfNeeded()
            await load()
        } catch MessageSendError.gate(let which) {
            gate = which
        } catch {
            errorMessage = UserFacingError.message(
                for: error, fallback: "Couldn't send that order. Try again."
            )
        }
    }

    /// The cook on the other end, when this thread is already open.
    var cookIDForOrdering: UUID?
    /// Loaded lazily, only when the buyer opens the order sheet — a thread is
    /// usually opened to read a reply, not to order, and fetching a menu every
    /// time would spend a request on nothing.
    var menu: [MenuItem] = []

    func loadMenuIfNeeded(discovery: (any DiscoveryRepository)?) async {
        guard menu.isEmpty, let cookID = cookIDForOrdering ?? threadCookID else { return }
        menu = (try? await discovery?.menu(for: cookID)) ?? []
    }

    var threadCookID: UUID? {
        if case .cook(let id) = subject { return id }
        return nil
    }

    /// Live delivery. Held so leaving the thread tears the subscription down —
    /// a channel per visited thread, never closed, is how a chat app ends up
    /// holding a dozen sockets open.
    private var liveTask: Task<Void, Never>?

    func startListening() {
        guard let threadID, liveTask == nil else { return }
        let stream = repository.liveMessages(in: threadID)
        liveTask = Task { [weak self] in
            for await _ in stream {
                guard !Task.isCancelled else { return }
                // Reload rather than append. An 'address' or 'pickup' message
                // changes `thread_state` too, and a transcript that moved while
                // the action bar didn't would be worse than a slower update.
                await self?.load()
            }
        }
    }

    func stopListening() {
        liveTask?.cancel()
        liveTask = nil
    }

    /// Who the review is about. The RLS policy pins `cook_id` to the
    /// conversation's actual cook, so a wrong value here is refused rather than
    /// misfiled — but sending the right one keeps the failure out of the way.
    var reviewableCookID: UUID? { cookIDForOrdering ?? threadCookID }

    /// Hands over a menu the caller has already loaded — the cook profile has
    /// one on screen, so refetching it on the way into the thread would be a
    /// round trip to display something the user is already looking at.
    func withMenu(_ items: [MenuItem]) -> ThreadViewModel {
        menu = items
        return self
    }

    func shareAddress() async {
        guard let threadID else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.shareAddress(in: threadID)
            await PushRegistrar.shared.requestAuthorizationIfNeeded()
            await load()
        } catch {
            errorMessage = UserFacingError.message(
                for: error, fallback: "Couldn't share your address. Try again."
            )
        }
    }

    func markPickedUp() async {
        guard let threadID else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.markPickedUp(in: threadID)
            await load()
        } catch {
            errorMessage = UserFacingError.message(
                for: error, fallback: "Couldn't mark that picked up."
            )
        }
    }

    /// Checks the gate *before* the person types, so a refusal never costs
    /// them a message they've already written.
    func checkGate() async {
        gate = try? await repository.gate()
    }

    func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        errorMessage = ""

        do {
            switch subject {
            case .thread(let id):
                _ = try await repository.reply(in: id, body: body)
            case .cook(let cookID):
                _ = try await repository.send(to: cookID, body: body, claimID: claimID)
                // The thread exists now; find it so replies go to the right
                // place and the transcript can load.
                if let opened = try? await repository.conversations()
                    .first(where: { $0.cookID == cookID }) {
                    subject = .thread(opened.id)
                }
            }
            draft = ""
            await PushRegistrar.shared.requestAuthorizationIfNeeded()
            await load()
        } catch MessageSendError.gate(let which) {
            // Not an error banner: a prompt. The draft is deliberately kept.
            gate = which
        } catch MessageSendError.rateLimited {
            errorMessage = "That's a lot of messages at once — try again shortly."
        } catch {
            errorMessage = UserFacingError.message(
                for: error, fallback: "Couldn't send that. Try again."
            )
        }
    }

    func signAvatar(_ path: String) async -> URL? {
        try? await profiles?.avatarURL(for: path)
    }

    /// Cook side only — a buyer blocks a *kitchen* from the cook's profile, not
    /// from here.
    let iAmTheCook: Bool

    func block() async -> Bool {
        guard let threadID else { return false }
        do {
            try await repository.blockBuyer(in: threadID)
            return true
        } catch {
            errorMessage = UserFacingError.message(
                for: error, fallback: "Couldn't block them. Try again."
            )
            return false
        }
    }

    var repositoryForReporting: any MessageRepository { repository }
}

struct ThreadView: View {
    @State var model: ThreadViewModel
    var session: SessionController?
    var profiles: (any ProfileRepository)?

    @State private var showingGate = false
    @State private var showingReport = false
    @State private var showingBlockConfirm = false
    @State private var showingOrder = false
    @State private var showingReview = false
    @State private var openParty: ThreadViewModel.OtherParty?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            transcript
            composer
        }
        .background(LK.Palette.ground)
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The title, made tappable. Put here rather than on the row in the
            // inbox: a name inside a list row is a tap target nested inside the
            // one that opens the conversation, and the two are a few points
            // apart. This is also where the question actually occurs to you —
            // mid-thread, wondering who you are talking to.
            if let party = model.otherParty {
                ToolbarItem(placement: .principal) {
                    Button {
                        openParty = party
                    } label: {
                        HStack(spacing: 4) {
                            Text(model.title)
                                .font(LK.Typography.navBarEmphasis)
                                .foregroundStyle(LK.Palette.ink)
                            Image(systemName: "chevron.right")
                                .font(LK.Typography.ui(11, weight: .semibold))
                                .foregroundStyle(LK.Palette.inkTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("About \(model.title)")
                }
            }
            // Cook side only. A buyer already blocks and reports the *kitchen*
            // from the cook's profile (028); duplicating it here would give
            // them two different-looking routes to the same act.
            if model.iAmTheCook, model.threadID != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Report \(model.title)", systemImage: "flag") {
                            showingReport = true
                        }
                        Button("Block \(model.title)", systemImage: "hand.raised", role: .destructive) {
                            showingBlockConfirm = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .confirmationDialog(
            "Block \(model.title)?",
            isPresented: $showingBlockConfirm, titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                Task { if await model.block() { dismiss() } }
            }
        } message: {
            // States plainly that it is silent. A cook deciding whether to block
            // someone who knows where they live needs to know whether that
            // person will find out.
            Text("They won't be able to message you or order from your kitchen, and your kitchen stops appearing for them. They aren't told, and you can undo this any time.")
        }
        .sheet(isPresented: $showingReport) {
            if let threadID = model.threadID {
                ReportBuyerSheet(
                    threadID: threadID,
                    buyerName: model.title,
                    repository: model.repositoryForReporting
                ) {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingOrder) {
            OrderSheet(cookName: model.title, menu: model.menu) { items, note in
                await model.placeOrder(items, note: note)
            }
        }
        .sheet(isPresented: $showingReview) {
            if let threadID = model.threadID, let cookID = model.reviewableCookID {
                ReviewSheet(
                    conversationID: threadID, cookID: cookID, cookName: model.title
                ) {
                    // Reload so the button disappears — `thread_state.reviewed`
                    // is what decides, and it has just changed.
                    Task { await model.load() }
                }
            }
        }
        .task {
            await model.checkGate()
            await model.load()
            await model.loadMenuIfNeeded(discovery: RootView.discoveryRepository)
        }
        // A cook is the kitchen page every buyer already sees; a buyer is the
        // private history only their cook may read. Same tap, two answers,
        // because the two sides of this app are not symmetric.
        .sheet(item: $openParty) { party in
            switch party {
            case .cook(let id):
                KitchenDeepLinkView(cookID: id)
            case .buyer(let id):
                if let profiles {
                    BuyerProfileView(buyerID: id, profiles: profiles)
                }
            }
        }
        .onDisappear { model.stopListening() }
        // Backgrounding does not fire `onDisappear`, and foregrounding does not
        // fire `task`. So a thread left open while the app was suspended came
        // back holding whatever it had before: iOS had killed the websocket,
        // Postgres Changes only replays from the moment of *subscribe*, and
        // nothing asked the server what had been missed. The push arrived, the
        // person tapped it, and the message the notification was about was not
        // on screen — reported from a real device.
        //
        // `stopListening()` before reloading is the part that matters. The
        // stream ends when the socket dies, which leaves `liveTask` non-nil but
        // finished, and `startListening()` is guarded on `liveTask == nil` — so
        // reloading alone would reconnect nothing and the thread would stay
        // dead for the rest of the session.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.stopListening()
                Task { await model.load() }   // load() starts the listener again
            case .background:
                model.stopListening()
            default:
                break
            }
        }
        // Opens the sheet, never closes it, and never clears the gate.
        //
        // This used to run both directions off one value: `showingGate = gate
        // != nil`, which forced `onDismiss` to null the gate or the sheet
        // reopened on the next redraw. The cost was that dismissing the sheet
        // also erased the fact that this person cannot send — leaving a live
        // composer on a thread that would refuse every message.
        //
        // `gate` is now what it says it is: whether sending is possible. The
        // sheet is a separate question, asked by this and by the button in
        // `gatedComposer`. Nothing reopens on redraw, because `onChange` fires
        // on change and dismissal does not change the gate.
        .onChange(of: model.gate) { _, gate in
            if gate != nil { showingGate = true }
        }
        .sheet(isPresented: $showingGate) {
            if let session, let profiles {
                MessagingGateSheet(session: session, profiles: profiles) {
                    Task {
                        await model.checkGate()
                        // Send what they already typed, rather than making them
                        // write it twice.
                        if model.gate == nil, !model.draft.isEmpty { await model.send() }
                    }
                }
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if model.messages.isEmpty, !model.isLoading {
                        emptyState
                    }
                    ForEach(model.messages) { message in
                        Group {
                            switch message.kind {
                            case .text:
                                MessageBubble(message: message, isMine: message.senderID == model.myID)
                            case .order:
                                OrderCard(message: message, isMine: message.senderID == model.myID)
                            case .address:
                                // The card reads the address from `thread_address`,
                                // not from the message — the marker carries none.
                                AddressCard(address: model.address, isMine: model.state?.iAmTheCook ?? false)
                            case .pickup:
                                SystemNote(text: "Picked up", icon: "checkmark.circle.fill")
                            }
                        }
                        .id(message.id)
                    }
                }
                .padding(.horizontal, LK.Metrics.feedGutter)
                .padding(.vertical, 12)
            }
            .onChange(of: model.messages.count) { _, _ in
                guard let last = model.messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No messages yet")
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.inkQuiet)
            Text("Ask if they're still cooking, or say when you'll arrive.")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    /// The two decisions only a cook makes, and the one thing only a buyer
    /// does. Deliberately above the composer rather than buried in a menu —
    /// sharing an address is the pivotal act of the whole app, and it should
    /// not be two taps deep.
    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 8) {
            // `state` is nil until a thread exists, and a thread does not exist
            // until someone sends something. Gating the whole bar on it meant a
            // buyer arriving from "Order from Ana" had to send a plain message
            // first before the order button appeared — the one path this
            // screen exists to serve.
            if let state = model.state, state.iAmTheCook {
                if !state.addressShared {
                    actionButton("Share my address", filled: true) {
                        Task { await model.shareAddress() }
                    }
                } else if !state.pickedUp {
                    actionButton("Mark picked up", filled: false) {
                        Task { await model.markPickedUp() }
                    }
                }
            } else if let state = model.state, !state.pickedUp, state.addressShared {
                // The buyer's side of close-out, which vanished with
                // `MyClaimsView`. It matters more than a nudge: a review needs
                // a recorded pickup, so before `migrations/051` a cook who
                // forgot to tap the button permanently blocked their own
                // reviews and the buyer had no way to say otherwise.
                actionButton("I picked this up", filled: false) {
                    Task { await model.markPickedUp() }
                }
            } else if let state = model.state, state.pickedUp, !state.reviewed {
                // The buyer's turn. Asked here rather than in a separate list
                // because the thread is where the transaction happened, and
                // because deleting `MyClaimsView` took the only route to
                // `ReviewSheet` with it — reviews were unreachable for a while
                // with the backend perfectly ready to accept them.
                actionButton("Leave a review", filled: true) { showingReview = true }
            } else if model.canOrder, !model.menu.isEmpty {
                // Three labels, because they mean three different things.
                // "Add to the order" after a pickup is wrong — that order is
                // collected and gone; this would be a new one.
                actionButton(
                    model.state?.pickedUp == true ? "Order again"
                      : model.messages.contains(where: { $0.kind == .order })
                        ? "Add to the order" : "Order from the menu",
                    filled: !model.messages.contains(where: { $0.kind == .order })
                ) { showingOrder = true }
            }
        }
        .padding(.horizontal, LK.Metrics.feedGutter)
        .padding(.top, 8)
    }

    private func actionButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(LK.Typography.bodyEmphasis)
                .foregroundStyle(filled ? .white : LK.Palette.action)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    filled ? LK.Palette.action : LK.Palette.chip,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(model.isWorking)
    }

    @ViewBuilder
    private var composer: some View {
        if let gate = model.gate {
            gatedComposer(gate)
        } else {
            sendableComposer
        }
    }

    /// Shown in place of the composer when this person cannot send yet.
    ///
    /// The gate sheet was the only signal, and it is dismissible. "Not now"
    /// dropped someone into a thread with a live text field, an enabled send
    /// button and an order button — none of which could ever work. They typed a
    /// whole message and found out afterwards. A tester reported this as being
    /// able to message a kitchen without an account: nothing was ever sent
    /// (`send_message` refuses an anonymous caller, `migrations/041`), but the
    /// refusal is invisible and arrives too late to be useful.
    ///
    /// So the ask moves in front of the typing. One tap reopens the same sheet,
    /// and `model.draft` is untouched — anything already written survives
    /// signing in.
    private func gatedComposer(_ gate: MessagingGate) -> some View {
        VStack(spacing: 8) {
            Text(gate == .needsAccount
                 ? "Sign in to message \(model.title)"
                 : "Add your name to message \(model.title)")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)
                .multilineTextAlignment(.center)

            Button {
                showingGate = true
            } label: {
                Text(gate == .needsAccount ? "Sign in" : "Add your name")
                    .font(LK.Typography.navBarEmphasis)
                    .foregroundStyle(LK.Palette.inkOnAction)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        LK.Palette.action,
                        in: RoundedRectangle(cornerRadius: LK.Metrics.radiusButton, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LK.Metrics.feedGutter)
        .padding(.vertical, 10)
        .background(LK.Palette.ground)
        .overlay(alignment: .top) {
            Rectangle().fill(LK.Palette.hairline).frame(height: 1)
        }
    }

    private var sendableComposer: some View {
        VStack(spacing: 6) {
            actionBar
            if !model.errorMessage.isEmpty {
                Text(model.errorMessage)
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $model.draft, axis: .vertical)
                    .font(LK.Typography.body)
                    .foregroundStyle(LK.Palette.ink)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        LK.Palette.surface,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(LK.Palette.hairline, lineWidth: 1)
                    }

                Button {
                    Task { await model.send() }
                } label: {
                    ZStack {
                        Circle().fill(canSend ? LK.Palette.action : LK.Palette.inkTertiary)
                        if model.isSending {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(LK.Typography.ui(16, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .disabled(!canSend || model.isSending)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, LK.Metrics.feedGutter)
        .padding(.vertical, 10)
        .background(LK.Palette.ground)
        .overlay(alignment: .top) {
            Rectangle().fill(LK.Palette.hairline).frame(height: 1)
        }
    }

    private var canSend: Bool {
        !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// An order, as it sits in the thread. Itemised because the cook reads this
/// while cooking — a total alone would make them scroll back for the lines.
private struct OrderCard: View {
    let message: Message
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 32) }

            VStack(alignment: .leading, spacing: 7) {
                // Caps header in `inkTertiary`, and the card takes a hairline
                // like every other card. An order is not heat — it is the most
                // consequential object in the app and it was wearing the colour
                // reserved for "a kitchen is live right now".
                Text("ORDER")
                    .font(LK.Typography.caps)
                    .textCase(.uppercase)
                    .tracking(LK.Typography.capsTracking)
                    .foregroundStyle(LK.Palette.inkTertiary)

                if let payload = message.payload {
                    ForEach(Array(payload.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(line.quantity)× \(line.displayName())")
                                .font(LK.Typography.bodyEmphasis)
                                .foregroundStyle(LK.Palette.ink)
                            Spacer(minLength: 8)
                            Text(String(format: "$%.2f", Double(line.unitCents * line.quantity) / 100))
                                .font(LK.Typography.body)
                                .foregroundStyle(LK.Palette.inkQuiet)
                                .monospacedDigit()
                        }
                    }

                    Divider().overlay(LK.Palette.hairline)

                    HStack {
                        Text("Total")
                            .font(LK.Typography.bodyEmphasis)
                            .foregroundStyle(LK.Palette.ink)
                        Spacer()
                        Text(String(format: "$%.2f", Double(payload.totalCents) / 100))
                            .font(LK.Typography.bodyEmphasis)
                            .foregroundStyle(LK.Palette.ink)
                            .monospacedDigit()
                    }

                    if let note = payload.note, !note.isEmpty {
                        Text(note)
                            .font(LK.Typography.meta)
                            .foregroundStyle(LK.Palette.inkQuiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    // Pre-043 rows, or a payload we couldn't decode. The body
                    // always carries a readable summary.
                    Text(message.body)
                        .font(LK.Typography.bodyEmphasis)
                        .foregroundStyle(LK.Palette.ink)
                }

                Text("Pay the cook directly — we take no payment.")
                    .font(LK.Typography.ui(12))
                    .foregroundStyle(LK.Palette.inkTertiary)
            }
            .padding(12)
            .frame(maxWidth: 300, alignment: .leading)
            .background(LK.Palette.surface,
                        in: RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous)
                    .strokeBorder(LK.Palette.hairline, lineWidth: LK.Metrics.cardBorderWidth)
            }

            if !isMine { Spacer(minLength: 32) }
        }
    }
}

/// The address, once shared. Centred and full width because it is the thing
/// the buyer opens the thread to find.
private struct AddressCard: View {
    let address: RevealedAddress?
    let isMine: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(isMine ? "YOU SHARED YOUR ADDRESS" : "PICK UP AT")
                .font(LK.Typography.caps)
                .textCase(.uppercase)
                .tracking(LK.Typography.capsTracking)
                .foregroundStyle(LK.Palette.inkTertiary)

            if let address {
                Text(address.singleLine)
                    .font(LK.Typography.ui(16, weight: .semibold))
                    .foregroundStyle(LK.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                // Buyer only. The heading already switches on `isMine`, but the
                // button did not — so after sharing her address a cook was
                // offered turn-by-turn directions to her own kitchen.
                if !isMine {
                    Button {
                        let url = URL(string: "maps://?daddr=\(address.latitude),\(address.longitude)")
                        if let url { UIApplication.shared.open(url) }
                    } label: {
                        Text("Directions")
                            .font(LK.Typography.ui(14, weight: .bold))
                            .foregroundStyle(LK.Palette.action)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Shared")
                    .font(LK.Typography.body)
                    .foregroundStyle(LK.Palette.inkQuiet)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(LK.Palette.chip,
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct SystemNote: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(LK.Typography.ui(12, weight: .semibold))
            Text(text)
                .font(LK.Typography.ui(12, weight: .semibold))
        }
        .foregroundStyle(LK.Palette.inkTertiary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

private struct MessageBubble: View {
    let message: Message
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 48) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                Text(message.body)
                    .font(LK.Typography.body)
                    .foregroundStyle(isMine ? .white : LK.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        isMine ? LK.Palette.action : LK.Palette.surface,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                    .overlay {
                        if !isMine {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .strokeBorder(LK.Palette.hairline, lineWidth: 1)
                        }
                    }

                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(LK.Typography.ui(12))
                    .foregroundStyle(LK.Palette.inkTertiary)
            }

            if !isMine { Spacer(minLength: 48) }
        }
    }
}
