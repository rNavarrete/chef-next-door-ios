import SwiftUI

/// The cook's home once signed in: burner, menu, and the claim inbox.
struct CookHomeView: View {
    @Bindable var session: SessionController
    let cookID: UUID

    @State private var selection = 0

    @State private var confirmingDelete = false
    @State private var deleteFailure: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Was `Kitchen | Messages`, and the Messages half listed the
                // same threads in the same order as the Messages tab an inch
                // below it. The unread count that used to live in this label
                // moved to a badge on that tab, which is where iOS users look
                // for it anyway.
                //
                // `You` is what a cook had nowhere else to see: the buying side
                // of their own account. Their kitchen is public and complete;
                // the fact that they also collect from four other kitchens
                // appeared in no screen in the product.
                Picker("", selection: $selection) {
                    Text("Kitchen").tag(0)
                    Text("You").tag(1)
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
            } else if selection == 1 {
                if let profiles = RootView.profileRepository {
                    ScrollView {
                        YouView(session: session, profiles: profiles)
                            .padding(LK.Metrics.screenPadding)
                    }
                }
            }
        }
        .background(LK.Palette.ground)
        .deleteAccountConfirmation(isPresented: $confirmingDelete, session: session) {
            deleteFailure = $0
        }
        .alert("Couldn't delete", isPresented: .constant(deleteFailure != nil)) {
            Button("OK") { deleteFailure = nil }
        } message: {
            Text(deleteFailure ?? "")
        }
    }
}
