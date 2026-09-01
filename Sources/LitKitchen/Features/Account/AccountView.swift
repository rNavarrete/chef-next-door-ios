import SwiftUI

/// Sign in, or make an account. Nothing about kitchens.
///
/// This replaces `CookSignInView`, which was the app's only full sign-in — with
/// email *and* password — and was framed entirely as "Your kitchen: sign in to
/// turn your light on, manage your menu". Two things were wrong with that.
///
/// **An account is a buyer thing first.** Being a cook is owning a `cooks` row,
/// which is an upgrade on top of an account, not a parallel identity. Asking
/// somebody to declare themselves a cook before they can sign in inverts the
/// model.
///
/// **It stranded people.** Anyone who made an account with an email — through
/// "Use an email instead" in the profile sheet — and later signed out had to go
/// to a tab marked with a stove to get back in, because the profile sheet only
/// offers Apple. There was no neutral way back into an existing account.
struct AccountView: View {
    @Bindable var session: SessionController
    /// Called once a sign-in actually succeeds.
    ///
    /// This screen is both the Account tab's root *and* a sheet pushed from the
    /// messaging gate. As the tab root, success needs no callback — `RootView`
    /// re-evaluates and swaps in the signed-in view. As a sheet, nothing was
    /// listening: the credentials were accepted, the session changed, and the
    /// form stayed exactly where it was, so signing in looked like it had done
    /// nothing at all.
    var onSignedIn: () -> Void = {}

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var showingSignUp = false
    /// Guideline 1.2: agreed before registering or logging in, not after.
    @State private var hasAgreed = TermsAgreement.isAccepted

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && !isWorking && hasAgreed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LK.Metrics.blockSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your account")
                        .font(LK.Typography.screenTitle)
                        .foregroundStyle(LK.Palette.ink)
                    Text("Sign in to message kitchens, keep your orders, and save the cooks you like.")
                        .font(LK.Typography.body)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)

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
                        SecureField("••••••••", text: $password)
                            .font(LK.Typography.body)
                            .textContentType(.password)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                if let error = session.signInError, !error.isEmpty {
                    Text(error)
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    isWorking = true
                    Task {
                        await session.signIn(email: email, password: password)
                        isWorking = false
                        // `signInError` is the only success signal this call
                        // gives — it returns Void and sets the error to nil on
                        // the way through.
                        if session.signInError == nil, session.userID != nil {
                            onSignedIn()
                        }
                    }
                } label: {
                    Group {
                        if isWorking {
                            ProgressView().tint(LK.Palette.inkOnAction)
                        } else {
                            Text("Sign in").font(LK.Typography.navBarEmphasis)
                        }
                    }
                    .foregroundStyle(LK.Palette.inkOnAction)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        canSubmit ? LK.Palette.action : LK.Palette.chip,
                        in: RoundedRectangle(cornerRadius: LK.Metrics.radiusButton, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)

                AppleSignInButton(session: session)
                    .disabled(!hasAgreed)
                    .opacity(hasAgreed ? 1 : 0.4)

                // Above the divider, so it sits in front of *all three* ways in
                // — password, Apple, and Create an account — rather than in
                // front of whichever one happens to be nearest.
                AgreementGate(isAccepted: $hasAgreed)

                Divider().overlay(LK.Palette.hairline).padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("New here?")
                        .font(LK.Typography.bodyEmphasis)
                        .foregroundStyle(LK.Palette.ink)
                    Text("Create an account to order from a kitchen. You can start cooking yourself later — that's a separate step, and it's optional.")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        showingSignUp = true
                    } label: {
                        Text("Create an account")
                            .font(LK.Typography.navBarEmphasis)
                            .foregroundStyle(LK.Palette.action)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(
                                RoundedRectangle(cornerRadius: LK.Metrics.radiusButton, style: .continuous)
                                    .strokeBorder(LK.Palette.action.opacity(0.35), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasAgreed)
                    .opacity(hasAgreed ? 1 : 0.4)
                }
            }
            .padding(LK.Metrics.screenPadding)
        }
        .background(LK.Palette.ground)
        // The sign-up sheet's failure was still on screen behind it after it
        // closed — "That email address isn't accepted" sitting under a sign-in
        // form that had never been submitted. An error belongs to the attempt
        // that produced it, not to the screen it happened to be shown on.
        .onAppear { session.reportAppleFailure(nil) }
        .sheet(isPresented: $showingSignUp) {
            SignUpView(session: session)
        }
        .onChange(of: showingSignUp) { _, showing in
            if !showing { session.reportAppleFailure(nil) }
        }
    }

}
