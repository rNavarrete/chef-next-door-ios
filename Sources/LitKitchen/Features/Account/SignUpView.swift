import SwiftUI

/// Creating an account. Any account.
///
/// It always was one — the body calls `session.signUp`, plain GoTrue, with no
/// cook registration anywhere in it — but the copy said "Cooking for your
/// neighbours? Make an account and we'll set up your kitchen next", which
/// promised a kitchen to everyone who signed up. Starting a kitchen is a
/// separate, optional step offered from `AccountHomeView`.
///
/// Kept separate from `CookOnboardingView` because it can end in a state that
/// is neither success nor failure: with email confirmations on, GoTrue creates
/// the user and returns **no session**, so the account exists but can't do
/// anything yet. The Account tab routes on what the session *is*, not on where
/// someone left off, so it recovers on its own once they confirm.
struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: SessionController

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var pendingConfirmationEmail: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("An account lets you message a kitchen and keep your orders. It takes one tap with Apple, or an email and password.")
                        .font(LK.Typography.body)
                        .foregroundStyle(LK.Palette.inkQuiet)
                        .fixedSize(horizontal: false, vertical: true)

                    AppleSignInButton(session: session) { dismiss() }

                    HStack(spacing: 10) {
                        Rectangle().fill(LK.Palette.hairline).frame(height: 0.5)
                        Text("or use an email")
                            .font(LK.Typography.meta)
                            .foregroundStyle(LK.Palette.inkTertiary)
                            .fixedSize()
                        Rectangle().fill(LK.Palette.hairline).frame(height: 0.5)
                    }
                    .padding(.vertical, 2)

                    GroupedCard {
                        LabeledField(
                            label: "Email", text: $email,
                            placeholder: "you@example.com",
                            capitalization: .never, keyboard: .emailAddress
                        )
                        Divider().overlay(LK.Palette.hairline)
                        HStack(spacing: 12) {
                            Text("Password")
                                .font(LK.Typography.body)
                                .foregroundStyle(LK.Palette.ink)
                                .frame(width: 96, alignment: .leading)
                            SecureField("At least 6 characters", text: $password)
                                .font(LK.Typography.body)
                                .textContentType(.password)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }

                    if let pending = pendingConfirmationEmail {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Check your email")
                                .font(LK.Typography.bodyEmphasis)
                                .foregroundStyle(LK.Palette.ink)
                            Text("We sent a confirmation link to \(pending). Tap it, then sign in here and we'll pick up where you left off.")
                                .font(LK.Typography.meta)
                                .foregroundStyle(LK.Palette.inkQuiet)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if let error = session.signInError {
                        Text(error)
                            .font(LK.Typography.meta)
                            .foregroundStyle(LK.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        isWorking = true
                        Task {
                            let result = await session.signUp(email: email, password: password)
                            isWorking = false
                            switch result {
                            case .upgraded:
                                dismiss()
                            case .needsEmailConfirmation(let address):
                                pendingConfirmationEmail = address
                            case .failed:
                                pendingConfirmationEmail = nil
                            }
                        }
                    } label: {
                        Group {
                            if isWorking { ProgressView().tint(.white) }
                            else { Text("Create account").font(LK.Typography.navBarEmphasis) }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            canSubmit ? LK.Palette.action : LK.Palette.inkTertiary.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)

                    // Was "You'll need a permit to sell prepared food. We'll ask
                    // for it next" — under a heading that had just said an
                    // account is for messaging and orders. A buyer signing up to
                    // order dinner was being told they need a health permit.
                    Text("Browsing is anonymous. An account only matters when you want to talk to a cook.")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(LK.Metrics.screenPadding)
            }
            .background(LK.Palette.ground)
            .navigationTitle("Create account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
    }

    private var canSubmit: Bool {
        !email.trimmed.isEmpty && password.count >= 6 && !isWorking
    }
}
