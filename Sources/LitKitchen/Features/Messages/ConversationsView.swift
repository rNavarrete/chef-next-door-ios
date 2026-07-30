import Observation
import SwiftUI

@Observable
@MainActor
final class ConversationsViewModel {
    private let repository: any MessageRepository
    let profiles: (any ProfileRepository)?

    var threads: [Conversation] = []
    var blocked: [BlockedBuyer] = []
    var isLoading = false
    var errorMessage = ""
    var myID: UUID?

    init(
        repository: any MessageRepository,
        profiles: (any ProfileRepository)? = nil,
        myID: UUID? = nil
    ) {
        self.repository = repository
        self.profiles = profiles
        self.myID = myID
    }

    var totalUnread: Int { threads.reduce(0) { $0 + $1.unread } }

    /// Clears a conversation from this person's list.
    ///
    /// Removed locally first so the row goes on the tap rather than after a
    /// round trip — this is a tidying gesture and any lag reads as a dead
    /// control. On failure the reload puts it back, which is the honest
    /// outcome: nothing was destroyed, so nothing needs recovering.
    func hide(_ thread: Conversation) async {
        threads.removeAll { $0.id == thread.id }
        do {
            try await repository.hideConversation(thread.id)
        } catch {
            errorMessage = UserFacingError.message(
                for: error, fallback: "Couldn't remove that conversation."
            )
            await load()
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            threads = try await repository.conversations()
            errorMessage = ""
            // Free — the per-thread counts are already here, so the badge costs
            // no round trip on the screen most likely to be looked at.
            await PushRegistrar.shared.setBadge(totalUnread)
        } catch {
            // The fallback is a *reason*, not a restatement. It renders under
            // a heading that already says "Couldn't load your messages", and
            // passing the same sentence twice printed it twice.
            errorMessage = UserFacingError.message(
                for: error, fallback: "Check your connection and pull to refresh."
            )
        }
        // Separate and non-fatal: a cook with no blocks is the normal case, and
        // failing to load an empty list must not report the inbox as broken.
        blocked = (try? await repository.blockedBuyers()) ?? []
    }

    /// Live inbox. Held so leaving the tab closes the socket.
    private var liveTask: Task<Void, Never>?

    func startListening() {
        guard liveTask == nil else { return }
        let stream = repository.liveConversations()
        liveTask = Task { [weak self] in
            for await _ in stream {
                guard !Task.isCancelled else { return }
                await self?.load()
            }
        }
    }

    func stopListening() {
        liveTask?.cancel()
        liveTask = nil
    }

    func unblock(_ buyer: BlockedBuyer) async {
        try? await repository.unblockBuyer(buyer.buyerID)
        await load()
    }

    func thread(for conversation: Conversation) -> ThreadViewModel {
        let model = ThreadViewModel(
            repository: repository,
            profiles: profiles,
            subject: .thread(conversation.id),
            title: conversation.otherName,
            avatar: conversation.otherAvatar,
            // A buyer's avatar is a private storage path; a cook's is a public
            // URL. Which one this is depends on which side you're reading from.
            avatarNeedsSigning: conversation.iAmTheCook,
            myID: myID,
            iAmTheCook: conversation.iAmTheCook
        )
        // The thread is already open, so the cook isn't in `subject`. Ordering
        // again from inside an existing thread needs it.
        model.cookIDForOrdering = conversation.iAmTheCook ? nil : conversation.cookID
        return model
    }

    func signAvatar(_ path: String) async -> URL? {
        try? await profiles?.avatarURL(for: path)
    }
}

/// Every conversation, both sides, newest first.
///
/// One screen for cooks and buyers because `my_conversations()` returns one
/// list — a cook messaging another cook is a buyer in that thread, and giving
/// each role its own inbox would mean two views rendering identical rows with
/// the labels swapped.
struct ConversationsView: View {
    @State var model: ConversationsViewModel
    var session: SessionController?

    @State private var showingGate = false
    @Environment(\.scenePhase) private var scenePhase

    /// No account, or an anonymous one. Both mean there is nothing to show and
    /// nothing wrong — messaging requires a permanent account (`migrations/040`).
    private var needsAccount: Bool {
        session == nil || session?.userID == nil || session?.isAnonymous == true
    }

    var body: some View {
        Group {
            // Checked before the error branch. 052 revoked `my_conversations`
            // from `anon`, which turned "you have no messages" into a 401 — so
            // a signed-out browser was shown "Couldn't load your messages",
            // the app accusing itself of breaking when nothing had.
            if needsAccount {
                signedOut
            } else {
            // Order matters. Checking `threads.isEmpty` first renders "No
            // messages yet" over a *failed* load — the list is empty either
            // way, and a person who has been messaging a cook all week would
            // be told the conversation never happened. A failure has to
            // outrank emptiness.
            if !model.errorMessage.isEmpty && model.threads.isEmpty {
                failed
            } else if model.threads.isEmpty && !model.isLoading {
                empty
            } else {
                list
            }
            }
        }
        .background(LK.Palette.ground)
        // `onAppear`, not `task`. A `.task` does not re-run when a pushed
        // thread is popped, so reading a conversation left the unread count in
        // the segment label — "Messages (1)" — sitting there after the cook had
        // just read it. `onAppear` fires on the way back too.
        .onAppear {
            guard !needsAccount else { return }   // nothing to load, nothing to subscribe to
            model.myID = session?.userID ?? model.myID
            Task { await model.load() }
            model.startListening()
        }
        .sheet(isPresented: $showingGate) {
            if let session, let profiles = RootView.profileRepository {
                MessagingGateSheet(session: session, profiles: profiles) {
                    Task { await model.load() }
                }
            }
        }
        .onDisappear { model.stopListening() }
        // The inbox has the same hole the thread did: `onAppear` does not fire
        // on foreground, so an app resumed on this screen showed the list as it
        // was before it was suspended. Worse here than in a thread, because the
        // inbox is where someone looks to find out whether anything happened —
        // an unread badge on the app icon over a list with no new row.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                guard !needsAccount else { return }
                model.stopListening()
                Task { await model.load() }
                model.startListening()
            case .background:
                model.stopListening()
            default:
                break
            }
        }
        .refreshable { await model.load() }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !model.errorMessage.isEmpty {
                    Text(model.errorMessage)
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(LK.Metrics.feedGutter)
                }

                ForEach(model.threads) { thread in
                    NavigationLink {
                        ThreadView(
                            model: model.thread(for: thread),
                            session: session,
                            profiles: model.profiles
                        )
                    } label: {
                        ConversationRow(
                            thread: thread,
                            sign: { await model.signAvatar($0) }
                        )
                    }
                    .buttonStyle(.plain)
                    // No confirmation: nothing is destroyed. The other party
                    // keeps their copy and a new message brings this back, so
                    // an "are you sure?" would overstate what just happened.
                    .contextMenu {
                        Button("Delete conversation", systemImage: "trash", role: .destructive) {
                            Task { await model.hide(thread) }
                        }
                    }

                    Rectangle()
                        .fill(LK.Palette.hairline)
                        .frame(height: 1)
                        .padding(.leading, 70)
                }

                blockedLink
            }
        }
    }

    /// The way back from a block. 028 made the same call for kitchens: without
    /// a list, a blocked thread is simply gone and "you can undo this any time"
    /// stops being true.
    @ViewBuilder
    private var blockedLink: some View {
        if !model.blocked.isEmpty {
            NavigationLink {
                BlockedBuyersView(model: model)
            } label: {
                HStack {
                    Text("Blocked buyers")
                        .font(LK.Typography.body)
                        .foregroundStyle(LK.Palette.inkQuiet)
                    Spacer()
                    Text("\(model.blocked.count)")
                        .font(LK.Typography.body)
                        .foregroundStyle(LK.Palette.inkTertiary)
                    Image(systemName: "chevron.right")
                        .font(LK.Typography.ui(13.5, weight: .semibold))
                        .foregroundStyle(LK.Palette.inkTertiary)
                }
                .padding(.horizontal, LK.Metrics.feedGutter)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var signedOut: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(LK.Typography.screenTitle)
                .foregroundStyle(LK.Palette.inkTertiary)
            Text("Messages need an account")
                .font(LK.Typography.titleSecondary)
                .foregroundStyle(LK.Palette.ink)
            Text("Browsing doesn't. Sign in when you want to ask a cook something or place an order.")
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.inkQuiet)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Sign in") { showingGate = true }
                .font(LK.Typography.bodyEmphasis)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    private var failed: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                .font(LK.Typography.screenTitle)
                .foregroundStyle(LK.Palette.inkTertiary)
            Text("Couldn't load your messages")
                .font(LK.Typography.titleSecondary)
                .foregroundStyle(LK.Palette.ink)
            Text(model.errorMessage)
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.inkQuiet)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Try again") { Task { await model.load() } }
                .font(LK.Typography.bodyEmphasis)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(LK.Typography.screenTitle)
                .foregroundStyle(LK.Palette.inkTertiary)
            Text("No messages yet")
                .font(LK.Typography.titleSecondary)
                .foregroundStyle(LK.Palette.ink)
            Text("Message a kitchen to ask what's left, or when to come by.")
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.inkQuiet)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }
}

private struct BlockedBuyersView: View {
    @State var model: ConversationsViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.blocked) { buyer in
                    HStack(spacing: 12) {
                        ProfileAvatar(
                            name: buyer.displayName, source: buyer.avatarPath,
                            needsSigning: true, size: 40,
                            sign: { await model.signAvatar($0) }
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(buyer.displayName)
                                .font(LK.Typography.ui(16, weight: .semibold))
                                .foregroundStyle(LK.Palette.ink)
                            Text("Blocked \(buyer.blockedAt.formatted(.dateTime.day().month(.abbreviated)))")
                                .font(LK.Typography.meta)
                                .foregroundStyle(LK.Palette.inkTertiary)
                        }
                        Spacer(minLength: 0)
                        Button("Unblock") { Task { await model.unblock(buyer) } }
                            .font(LK.Typography.bodyEmphasis)
                    }
                    .padding(.horizontal, LK.Metrics.feedGutter)
                    .padding(.vertical, 11)

                    Rectangle().fill(LK.Palette.hairline)
                        .frame(height: 1).padding(.leading, 68)
                }

                Text("A blocked buyer can't message you or order from your kitchen, and your kitchen doesn't appear for them. They were never told.")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(LK.Metrics.feedGutter)
            }
        }
        .background(LK.Palette.ground)
        .navigationTitle("Blocked")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ConversationRow: View {
    let thread: Conversation
    let sign: (String) async -> URL?

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(
                name: thread.otherName,
                source: thread.otherAvatar,
                needsSigning: thread.iAmTheCook,
                size: 46,
                sign: sign
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(thread.otherName)
                        .font(.system(size: 16, weight: thread.unread > 0 ? .bold : .semibold))
                        .foregroundStyle(LK.Palette.ink)
                        .lineLimit(1)

                    // Which hat you're wearing in this thread isn't obvious
                    // from a name alone once a cook also buys.
                    if thread.iAmTheCook {
                        Text("BUYER")
                            .font(LK.Typography.ui(10.5, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(LK.Palette.heatInk)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(LK.Palette.chip, in: Capsule())
                    }

                    Spacer(minLength: 4)

                    Text(thread.lastAt.relativeShort)
                        .font(LK.Typography.ui(12))
                        .foregroundStyle(LK.Palette.inkTertiary)
                }

                HStack(spacing: 6) {
                    Text(thread.preview())
                        .font(.system(size: 14, weight: thread.unread > 0 ? .semibold : .regular))
                        .foregroundStyle(
                            thread.unread > 0 ? LK.Palette.ink : LK.Palette.inkQuiet
                        )
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if thread.unread > 0 {
                        Text("\(thread.unread)")
                            .font(LK.Typography.ui(12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .padding(.horizontal, 4)
                            .background(LK.Palette.action, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, LK.Metrics.feedGutter)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

extension Date {
    /// "4m", "3h", "Tue", "12 Mar" — an inbox timestamp, not a full date.
    var relativeShort: String {
        let seconds = Date.now.timeIntervalSince(self)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        if seconds < 604_800 { return formatted(.dateTime.weekday(.abbreviated)) }
        return formatted(.dateTime.day().month(.abbreviated))
    }
}
