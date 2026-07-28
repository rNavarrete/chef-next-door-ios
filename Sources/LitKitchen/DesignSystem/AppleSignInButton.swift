import AuthenticationServices
import SwiftUI
import os

/// Apple's sign-in button, wired to the session.
///
/// Uses `SignInWithAppleButton` rather than a custom control on purpose —
/// Apple's Human Interface Guidelines require their button for this flow, and a
/// look-alike is grounds for review rejection. It is the one place in this app
/// where the design system defers entirely to the platform.
struct AppleSignInButton: View {
    @Bindable var session: SessionController
    /// Called only on success, so callers can dismiss or move on.
    var onSuccess: () -> Void = {}

    @State private var coordinator = AppleSignInCoordinator()
    @State private var isWorking = false
    private let log = Logger(subsystem: "com.litkitchen.app", category: "applesignin")

    var body: some View {
        Button {
            guard !isWorking else { return }
            isWorking = true
            // A new attempt starts clean. Without this the previous failure's
            // banner stayed on screen through a successful sign-in, which is
            // how a working flow came to look broken.
            session.reportAppleFailure(nil)
            Task {
                defer { isWorking = false }
                do {
                    let credential = try await coordinator.requestCredential()
                    log.info("apple: credential in hand, exchanging with GoTrue")
                    let result = await session.continueWithApple(credential)
                    log.info("apple: result=\(String(describing: result), privacy: .public) userID=\(session.userID != nil, privacy: .public) anon=\(session.isAnonymous, privacy: .public) cook=\(session.cookID != nil, privacy: .public) onboarding=\(session.needsCookOnboarding, privacy: .public)")
                    if case .upgraded = result { onSuccess() }
                } catch AppleSignInError.cancelled {
                    // Nothing to report.
                } catch {
                    session.reportAppleFailure(
                        (error as? LocalizedError)?.errorDescription
                            ?? "Couldn't finish signing in with Apple."
                    )
                }
            }
        } label: {
            ZStack {
                // The real button, non-interactive: it renders Apple's exact
                // asset and localised wording, while the Button above owns the
                // tap. SignInWithAppleButton's own handler can't await our
                // coordinator without duplicating the nonce plumbing.
                SignInWithAppleButton(.continue) { _ in } onCompletion: { _ in }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .allowsHitTesting(false)

                if isWorking {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.black.opacity(0.55))
                    ProgressView().tint(.white)
                }
            }
            .frame(height: 50)
            // Without this the button is **not tappable at all**.
            //
            // The label's only real content is `SignInWithAppleButton` with
            // `.allowsHitTesting(false)` — needed so the outer `Button` owns
            // the tap rather than Apple's own control. But opting the sole
            // child out of hit testing leaves `.buttonStyle(.plain)` with no
            // hittable shape to derive, so taps fell straight through and the
            // action never ran: no request, no spinner, no error.
            //
            // Verified in the log stream — the tap dispatched a UIEvent and
            // produced no AuthenticationServices activity whatsoever. For a
            // buyer this was the only route to an account, and it was dead.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue with Apple")
    }
}
