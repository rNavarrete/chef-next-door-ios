import SwiftUI

/// The cook's home once signed in: burner, menu, and the claim inbox.
struct CookHomeView: View {
    @Bindable var session: SessionController
    let cookID: UUID

    @State private var selection = 0

    @State private var confirmingDelete = false
    @State private var deleteFailure: String?
    @State private var messagesModel: ConversationsViewModel? = {
        guard let repo = RootView.messageRepository else { return nil }
        return ConversationsViewModel(repository: repo, profiles: RootView.profileRepository)
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Claims retired with 043 — a cook's orders arrive as messages
                // now, so the inbox and the conversation list were the same
                // thing wearing two labels.
                Picker("", selection: $selection) {
                    Text("Kitchen").tag(0)
                    Text(messagesLabel).tag(2)
                }
                .pickerStyle(.segmented)

                // A cook has to be able to get out. Also the only way to switch
                // between the buyer and cook sides on one device, which matters
                // for testing and for the many cooks who are also buyers.
                // A menu rather than a button: account deletion is required
                // to be reachable in-app (5.1.1(v)) and there is no room for a
                // second control in this header.
                Menu {
                    Button("Sign out") { Task { await session.signOut() } }
                    Button("Delete my account", role: .destructive) {
                        confirmingDelete = true
                    }
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(LK.Typography.bodyEmphasis)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Account")
            }
            .padding(.horizontal, LK.Metrics.feedGutter)
            .padding(.top, 8)

            if selection == 0 {
                KitchenView(model: KitchenViewModel(
                    repository: SupabaseCookRepository(cookID: cookID),
                    cookID: cookID
                ))
            } else if selection == 2 {
                // Wrapped in its own stack: CookHomeView is a tab root, not a
                // pushed screen, so a thread has nowhere to go without one.
                NavigationStack {
                    if let messagesModel {
                        ConversationsView(model: messagesModel, session: session)
                    }
                }
            }
        }
        .background(LK.Palette.ground)
        .task { await messagesModel?.load() }
        .deleteAccountConfirmation(isPresented: $confirmingDelete, session: session) {
            deleteFailure = $0
        }
        .alert("Couldn't delete", isPresented: .constant(deleteFailure != nil)) {
            Button("OK") { deleteFailure = nil }
        } message: {
            Text(deleteFailure ?? "")
        }
    }

    private var messagesLabel: String {
        let unread = messagesModel?.totalUnread ?? 0
        return unread > 0 ? "Messages (\(unread))" : "Messages"
    }
}
