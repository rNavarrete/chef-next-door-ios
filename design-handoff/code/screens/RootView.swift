import SwiftUI

/// Tab order from the design handoff. Cooking is the landing tab: most people
/// arrive with a *when* in mind, not a *where* (`DESIGN_BRIEF.md` §11 — still
/// open, and worth revisiting once the launch cluster is dense enough that the
/// map is useful on its own).
enum RootTab: String, CaseIterable, Identifiable {
    // Search folded into Cooking: the results *are* the feed, so a whole tab
    // held a text field and split "who's cooking" from "who's cooking tamales"
    // into two places.
    case cooking, map, saved, kitchen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cooking: "Cooking"
        case .map: "Map"
        case .saved: "Saved"
        case .kitchen: "Kitchen"
        }
    }

    var systemImage: String {
        switch self {
        case .cooking: "flame"
        case .map: "mappin.and.ellipse"
        case .saved: "heart"
        case .kitchen: "flame.circle"
        }
    }
}

extension Notification.Name {
    /// Fired when a push token has been stored. DEBUG readout only.
    static let litKitchenTokenRegistered = Notification.Name("litKitchenTokenRegistered")
}

struct RootView: View {
    @State private var selection: RootTab = .cooking
    /// A thread arrived at from outside the app — today, the Live Activity.
    @State private var deepLink: ThreadLink?
    // Reads live from the Supabase RPCs. Falls back to the in-memory double
    // when credentials are absent, so a fresh clone still runs.
    @State private var discoverModel = CookingNowViewModel(repository: Self.discovery)
    @State private var searchModel = SearchViewModel(repository: Self.discovery)
    @State private var mapModel = MapViewModel(repository: Self.discovery)
    @State private var savedModel = SavedViewModel(store: Self.follows)

    private static let isConfigured =
        (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String)?.isEmpty == false

    private static let discovery: any DiscoveryRepository =
        isConfigured ? SupabaseDiscoveryRepository() : InMemoryDiscoveryRepository()

    /// Exposed so detail screens pushed from a feed can build their own model
    /// without threading the repository through every view.
    static var discoveryRepository: any DiscoveryRepository { discovery }

    /// Device-local until Sign in with Apple lands; the rows still come from
    /// the server so followed cooks show real availability.
    static let follows: any FollowStore =
        LocalFollowStore(client: isConfigured ? SupabaseEnvironment.shared : nil)

    /// Identity is established lazily, at the first claim — browsing needs no
    /// account. See SessionController.
    @MainActor static let session: SessionController? =
        isConfigured ? SessionController() : nil


    /// Messaging exists only against a real backend. The in-memory double is
    /// for previews and tests — falling back to it here would give a buyer a
    /// composer that silently writes to nothing.
    static let messageRepository: (any MessageRepository)? =
        isConfigured ? SupabaseMessageRepository() : nil

    @MainActor static let profileRepository: (any ProfileRepository)? =
        isConfigured ? SupabaseProfileRepository() : nil

    var body: some View {
        TabView(selection: $selection) {
            ForEach(RootTab.allCases) { tab in
                Group {
                    switch tab {
                    case .cooking: CookingNowView(model: discoverModel, searchModel: searchModel)
                    case .map: MapKitchenView(model: mapModel)
                    case .saved: SavedView(model: savedModel)
                    case .kitchen: cookTab
                    }
                }
                .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                .tag(tab)
            }
        }
        .tint(LK.Palette.action)
        // The Live Activity's whole point is getting back to the conversation.
        .onOpenURL { url in
            if let id = DeepLink.threadID(from: url) {
                deepLink = ThreadLink(id: id)
            }
        }
        .sheet(item: $deepLink) { link in
            ThreadDeepLinkView(threadID: link.id)
        }
        .task {
            await Self.session?.restore()
            Self.wireActivityTokens()
            // Wires the delegate only. The permission prompt is deliberately
            // NOT fired here — see PushRegistrar.
            PushRegistrar.shared.configure(repository: Self.messageRepository)
        }
    }

    /// Sends every ActivityKit push token to the backend as it is issued.
    ///
    /// Wired here rather than inside the activity manager so that manager stays
    /// free of any networking dependency — it knows about ActivityKit and
    /// nothing else. Tokens are reissued mid-activity, so this is a stream, not
    /// a one-time handshake.
    @MainActor
    private static func wireActivityTokens() {
        guard #available(iOS 16.2, *), let repo = messageRepository else { return }
        CookingActivityManager.shared.onToken = { threadID, token, activityID in
            guard let uuid = UUID(uuidString: threadID) else { return }
            // Best-effort: a token that fails to register costs a card update,
            // not the order, and it will be reissued.
            try? await repo.registerActivityToken(
                threadID: uuid, token: token, activityID: activityID
            )
            NotificationCenter.default.post(name: .litKitchenTokenRegistered, object: nil)
        }
    }

    /// Cook surfaces exist only for a signed-in cook. There's no role flag —
    /// being a cook is owning a `cooks` row, which the session resolves.
    ///
    /// Three states, and the middle one is easy to get wrong: an **anonymous**
    /// buyer also has a session with no `cooks` row, so "signed in without a
    /// kitchen" cannot be the test for resuming onboarding. It has to be a
    /// permanent account without a kitchen — otherwise every buyer who taps
    /// Kitchen out of curiosity lands in a cook registration form.
    @ViewBuilder
    private var cookTab: some View {
        if let session = Self.session {
            if let cookID = session.cookID {
                CookHomeView(session: session, cookID: cookID)
            } else if session.needsCookOnboarding {
                CookOnboardingView(session: session)
            } else {
                CookSignInView(session: session)
            }
        } else {
            ScaffoldPlaceholder(tab: .kitchen)
        }
    }
}

/// M0 placeholder. Each tab is replaced by its real feature in M1–M3;
/// this exists so the scaffold builds, runs, and can be screenshotted.
private struct ScaffoldPlaceholder: View {
    let tab: RootTab

    var body: some View {
        ZStack {
            LK.Palette.paper.ignoresSafeArea()
            // The Saved tab hosts the M0 spike harness so the Live Activity
            // can be driven by hand. Replaced by the real screen in M5.
            if tab == .saved, #available(iOS 16.2, *) {
                SpikeHarness()
            } else {
                VStack(spacing: LK.Metrics.blockSpacing) {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(LK.Palette.inkTertiary)
                    Text(tab.title)
                        .font(LK.Typography.screenTitleSecondary)
                        .foregroundStyle(LK.Palette.ink)
                    Text("M0 scaffold")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                }
            }
        }
    }
}

#Preview {
    RootView()
}
