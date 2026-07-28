import SwiftUI

/// Turning an anonymous identity into a permanent account with email and
/// password.
///
/// Lifted out of `MyClaimsView` when the claim screens were retired
/// (`migrations/043`). It was only ever *filed* there — it is about identity,
/// not claims, and deleting it with the rest would have taken the whole
/// email/password upgrade path with it, leaving Sign in with Apple as the only
/// way to get an account. Cooks who signed up on the web need this one.

struct UpgradeAccountView: View {
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
                    Text("This account lives on this phone only. An email keeps your orders and messages if you switch phones — or if you ever sign in as a cook.")
                        .font(LK.Typography.body)
                        .foregroundStyle(LK.Palette.inkQuiet)
                        .fixedSize(horizontal: false, vertical: true)

                    // First, and not merely for convenience: Apple links to the
                    // *existing* anonymous user and needs no email round-trip,
                    // so it is the only upgrade path that completes in one go.
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
                        // Not a success and not a failure. Saying "done" here
                        // would be a lie — the claims are still anonymous until
                        // the link is clicked — so the sheet stays put and says
                        // exactly what is outstanding.
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Check your email")
                                .font(LK.Typography.bodyEmphasis)
                                .foregroundStyle(LK.Palette.ink)
                            Text("We sent a confirmation link to \(pending). Your account is saved once you tap it.")
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
                            let result = await session.upgradeToAccount(email: email, password: password)
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
                            else { Text("Save my account").font(LK.Typography.navBarEmphasis) }
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
                }
                .padding(LK.Metrics.screenPadding)
            }
            .background(LK.Palette.ground)
            .navigationTitle("Keep your account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
        .tint(LK.Palette.action)
    }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 && !isWorking
    }
}
