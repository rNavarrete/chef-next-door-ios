import SwiftUI

/// Tab order from the design handoff. Cooking is the landing tab: most people
/// arrive with a *when* in mind, not a *where* (`DESIGN_BRIEF.md` §11 — still
/// open, and worth revisiting once the launch cluster is dense enough that the
/// map is useful on its own).
enum RootTab: String, CaseIterable, Identifiable {
    // Search folded into Cooking: the results *are* the feed, so a whole tab
    // held a text field and split "who's cooking" from "who's cooking tamales"
    // into two places.
    case cooking, map, messages, account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cooking: "Cooking"
        case .map: "Map"
        case .messages: "Messages"
        case .account: "Account"
        }
    }

    var systemImage: String {
        switch self {
        case .cooking: "flame"
        case .map: "mappin.and.ellipse"
        // The tab already opened on the inbox — its default segment is
        // Messages — so a heart was describing the two segments behind it
        // rather than the screen you land on.
        case .messages: "message"
        // A person, not a stove. The tab is an account first: most people
        // signing in are never going to cook, and a stove promised otherwise.
        case .account: "person.crop.circle"
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
    /// Where the app is looking — see `BrowsingOrigin`.
    ///
    /// Not `@State`: it has to be the *same* object the view models were built
    /// with, and a `@State` default would construct a second one. `@Observable`
    /// tracks reads from `body` regardless of how the reference is held.
    private var browsing: BrowsingOrigin { Self.origin }
    @State private var discoverModel = CookingNowViewModel(repository: Self.discovery, browsing: Self.origin)
    @State private var searchModel = SearchViewModel(repository: Self.discovery, browsing: Self.origin)
    @State private var mapModel = MapViewModel(repository: Self.discovery, browsing: Self.origin)
    @State private var savedModel = SavedViewModel(store: Self.follows, browsing: Self.origin)

    /// One instance, shared by the `@State` initialisers above and by the
    /// `browsing` property they cannot reference from their own default values.
    @MainActor static let origin = BrowsingOrigin()

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
                    case .cooking: CookingNowView(model: discoverModel, searchModel: searchModel, browsing: browsing)
                    case .map: MapKitchenView(model: mapModel, browsing: browsing)
                    case .messages: SavedView(model: savedModel, browsing: browsing)
                    case .account: accountTab
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

    /// Account first, kitchen second.
    ///
    /// Four states, and the third is the one that was missing. `needsCookOnboarding`
    /// is `userID != nil && !isAnonymous && cookID == nil` — *every* signed-in
    /// person without a kitchen — and this went straight from it into
    /// `CookOnboardingView`. Its old comment claimed to protect against exactly
    /// that, but the guard only excluded **anonymous** browsers: a buyer who
    /// signed in, which is what the messaging gate asks them to do, landed in a
    /// permit form.
    ///
    /// Being a cook is owning a `cooks` row. That is an upgrade on an account,
    /// so it comes after one, offered rather than assumed.
    @ViewBuilder
    private var accountTab: some View {
        if let session = Self.session {
            if let cookID = session.cookID {
                CookHomeView(session: session, cookID: cookID)
            } else if session.isAnonymous || session.userID == nil {
                AccountView(session: session)
            } else {
                AccountHomeView(session: session)
            }
        } else {
            ScaffoldPlaceholder(tab: .account)
        }
    }
}

/// M0 placeholder. Each tab is replaced by its real feature in M1–M3;
/// this exists so the scaffold builds, runs, and can be screenshotted.
private struct ScaffoldPlaceholder: View {
    let tab: RootTab

    var body: some View {
        ZStack {
            LK.Palette.ground.ignoresSafeArea()
            // The Saved tab hosts the M0 spike harness so the Live Activity
            // can be driven by hand. Replaced by the real screen in M5.
            if tab == .messages, #available(iOS 16.2, *) {
                SpikeHarness()
            } else {
                VStack(spacing: LK.Metrics.blockSpacing) {
                    Image(systemName: tab.systemImage)
                        .font(LK.Typography.screenTitle)
                        .foregroundStyle(LK.Palette.inkTertiary)
                    Text(tab.title)
                        .font(LK.Typography.titleSecondary)
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
