import SwiftUI

/// Deleting your account, from inside the app.
///
/// Required by App Store guideline 5.1.1(v), and there was no way to do it —
/// not a hidden way, not a support-email way. None.
///
/// Split into a modifier and a button because the two account surfaces present
/// it differently: the buyer's screen has room for a plain text button under
/// "Sign out", while the cook's is a header icon with no space for a second
/// control. Both must say exactly the same thing about what is being destroyed,
/// so the copy and the work live here once.
extension View {
    func deleteAccountConfirmation(
        isPresented: Binding<Bool>,
        session: SessionController,
        onFailure: @escaping (String) -> Void = { _ in }
    ) -> some View {
        modifier(DeleteAccountConfirmation(
            isPresented: isPresented, session: session, onFailure: onFailure
        ))
    }
}

private struct DeleteAccountConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let session: SessionController
    let onFailure: (String) -> Void

    func body(content: Content) -> some View {
        // Spells out what goes, rather than asking "are you sure?" about an
        // unnamed thing. A cook is told about the kitchen explicitly, because
        // that is the part they may not have connected to the word "account".
        content.confirmationDialog(
            "Delete your account?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) {
                Task {
                    do {
                        try await session.deleteAccount()
                        // Nothing to dismiss — the account is gone, so RootView
                        // routes back to the signed-out surface on its own.
                    } catch {
                        onFailure((error as? LocalizedError)?.errorDescription
                            ?? "We couldn't delete your account just now. Try again in a moment.")
                    }
                }
            }
            Button("Keep my account", role: .cancel) {}
        } message: {
            Text(session.isCook
                 ? "This removes your kitchen, your menu, your photos and your conversations, for good. Buyers who follow you will lose the link. This cannot be undone."
                 : "This removes your account, your saved cooks and your conversations, for good. This cannot be undone.")
        }
    }
}

/// The buyer-side control: plain text, under "Sign out".
struct DeleteAccountButton: View {
    @Bindable var session: SessionController

    @State private var confirming = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Delete my account") { confirming = true }
                .font(LK.Typography.body)
                // Not styled as a primary action. A real option, offered
                // plainly — not something to hit while reaching for
                // something else.
                .foregroundStyle(LK.Palette.inkTertiary)
                .buttonStyle(.plain)

            if let failure {
                Text(failure)
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .deleteAccountConfirmation(isPresented: $confirming, session: session) {
            failure = $0
        }
    }
}
