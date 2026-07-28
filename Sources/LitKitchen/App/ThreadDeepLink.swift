import SwiftUI

/// `litkitchen://` URLs. Two shapes: a thread, and a cook's kitchen.
///
/// The Live Activity has emitted `litkitchen://thread/<uuid>` from four places
/// since it was written, and nothing in the app ever parsed it. Worse, the
/// scheme itself was unregistered, so the failure was invisible: tapping
/// "Message Fatima H." foregrounded the app on whatever screen it had been left
/// on, which looks like a working button with a lazy destination rather than a
/// link that was never wired.
enum DeepLink {
    /// The conversation id in `litkitchen://thread/<uuid>`, or nil.
    ///
    /// Returns nil rather than trapping on anything unexpected — the spike
    /// harness starts activities with the id `spike-thread-0001`, which is a
    /// perfectly reasonable thing for a test fixture to do and must not crash
    /// the app when someone taps its card.
    static func threadID(from url: URL) -> UUID? {
        guard url.scheme == "litkitchen", url.host == "thread" else { return nil }
        return url.pathComponents
            .last { $0 != "/" }
            .flatMap(UUID.init(uuidString:))
    }

    /// The cook id in `litkitchen://cook/<uuid>`, or nil.
    ///
    /// What a cook's shareable link points at. They paste it into the Facebook
    /// post or Messenger thread where their buyers already are, and it opens
    /// their kitchen here.
    static func cookID(from url: URL) -> UUID? {
        guard url.scheme == "litkitchen", url.host == "cook" else { return nil }
        return url.pathComponents
            .last { $0 != "/" }
            .flatMap(UUID.init(uuidString:))
    }

    /// The link a cook shares.
    ///
    /// A custom scheme, which means it only opens for somebody who already has
    /// the app — tapping it without the app installed does nothing visible.
    /// That is a real limit and the reason this is one function: when a domain
    /// exists, this becomes an https:// Universal Link and every share already
    /// in the wild keeps working, because they all came from here.
    ///
    /// Universal Links additionally need an apple-app-site-association file
    /// served from that domain, and the associated-domains entitlement.
    static func kitchenURL(cookID: UUID) -> URL {
        URL(string: "litkitchen://cook/\(cookID.uuidString.lowercased())")!
    }
}

/// Wraps a cook id so it can drive `.sheet(item:)`.
struct KitchenLink: Identifiable {
    let id: UUID
}

/// Wraps a thread id so it can drive `.sheet(item:)`.
struct ThreadLink: Identifiable {
    let id: UUID
}

/// Resolves a thread id into a live `ThreadView`.
///
/// Presented modally rather than pushed. The inbox lives inside the Saved tab's
/// segmented control and pushes its threads with a plain `NavigationLink`, so
/// there is no path to drive programmatically — arriving there would mean
/// switching tab, switching segment, then synthesising a push, and leaving the
/// user somewhere they didn't ask to be. A card tapped from the Lock Screen
/// wants the conversation and a way back out, which is what a sheet is.
struct ThreadDeepLinkView: View {
    let threadID: UUID

    @State private var model = ConversationsViewModel(
        repository: RootView.messageRepository ?? InMemoryMessageRepository(),
        profiles: RootView.profileRepository
    )
    @State private var resolved: ThreadViewModel?
    @State private var failure: Failure?
    @Environment(\.dismiss) private var dismiss

    /// Two different failures that must not share a sentence.
    ///
    /// The inbox's own fallback — "Check your connection and pull to refresh" —
    /// is written for a list that *has* pull-to-refresh. Reusing it here told
    /// the user to perform a gesture this sheet does not support.
    private enum Failure {
        /// The inbox wouldn't load. Retrying is the useful thing to offer.
        case couldNotLoad
        /// The inbox loaded and this thread isn't in it. Retrying is pointless.
        case notInInbox
    }

    var body: some View {
        NavigationStack {
            Group {
                if let resolved {
                    ThreadView(
                        model: resolved,
                        session: RootView.session,
                        profiles: model.profiles
                    )
                } else if let failure {
                    ContentUnavailableView {
                        Label(
                            failure == .couldNotLoad
                                ? "Couldn't load your messages"
                                : "That conversation is gone",
                            systemImage: "bubble.left"
                        )
                    } description: {
                        Text(failure == .couldNotLoad
                             ? "Check your connection and try again."
                             : "It isn't in your inbox any more.")
                    } actions: {
                        // Only where it can help. Retrying a thread that has
                        // genuinely left the inbox just fails again, slower.
                        if failure == .couldNotLoad {
                            Button("Try again") { Task { await resolve() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(LK.Palette.ground)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await resolve() }
    }

    /// Resolved through the inbox rather than fetched by id, so the title,
    /// avatar and — critically — `iAmTheCook` come from the same place they do
    /// everywhere else. A thread rendered from the wrong side shows the wrong
    /// controls.
    private func resolve() async {
        failure = nil
        await model.load()

        if let conversation = model.threads.first(where: { $0.id == threadID }) {
            resolved = model.thread(for: conversation)
        } else {
            // A non-empty `errorMessage` means the fetch itself failed, so the
            // thread's absence proves nothing about the thread.
            failure = model.errorMessage.isEmpty ? .notInInbox : .couldNotLoad
        }
    }
}
