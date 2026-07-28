import SwiftUI

/// Signed in, no kitchen. The great majority of accounts will live here.
///
/// This screen exists because the routing had no state for it. `cookTab` went
/// straight from "signed in" to `CookOnboardingView`, on the strength of
/// `needsCookOnboarding` — which is `userID != nil && !isAnonymous && cookID ==
/// nil`, i.e. *every* signed-in person without a kitchen.
///
/// Its comment claimed to guard against "every buyer who taps Kitchen out of
/// curiosity lands in a cook registration form", but the guard only excluded
/// **anonymous** browsers. A buyer who actually signed in — which is what the
/// messaging gate asks them to do — was dropped into "register your kitchen"
/// with a permit form. Most people using this app are never going to cook.
///
/// Starting a kitchen is offered here, once, as a choice.
struct AccountHomeView: View {
    @Bindable var session: SessionController

    @State private var showingProfile = false
    @State private var showingOnboarding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LK.Metrics.blockSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your account")
                        .font(LK.Typography.screenTitle)
                        .foregroundStyle(LK.Palette.ink)
                    if let email = session.email, !email.isEmpty {
                        Text(email)
                            .font(LK.Typography.meta)
                            .foregroundStyle(LK.Palette.inkTertiary)
                    }
                }
                .padding(.top, 4)

                GroupedCard {
                    row("Profile", detail: "Your name and photo") { showingProfile = true }
                }

                // The one place becoming a cook is offered, and it is framed as
                // a decision rather than as the next step in signing up.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cooking for your neighbours?")
                        .font(LK.Typography.bodyEmphasis)
                        .foregroundStyle(LK.Palette.ink)
                    Text("Set up a kitchen, build a menu, and turn your light on when you're cooking. You'll need a MEHKO permit from your county.")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        showingOnboarding = true
                    } label: {
                        Text("Start a kitchen")
                            .font(LK.Typography.navBarEmphasis)
                            .foregroundStyle(LK.Palette.action)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(
                                RoundedRectangle(cornerRadius: LK.Metrics.radiusButton, style: .continuous)
                                    .strokeBorder(LK.Palette.action.opacity(0.35), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 18) {
                    Button("Sign out") { Task { await session.signOut() } }
                        .font(LK.Typography.body)
                        .foregroundStyle(LK.Palette.inkTertiary)

                    DeleteAccountButton(session: session)
                }
                .padding(.top, 8)
            }
            .padding(LK.Metrics.screenPadding)
        }
        .background(LK.Palette.ground)
        .sheet(isPresented: $showingProfile) {
            if let profiles = RootView.profileRepository {
                ProfileView(session: session, profiles: profiles)
            }
        }
        .sheet(isPresented: $showingOnboarding) {
            CookOnboardingView(session: session)
        }
        // Re-reads cook status on return: finishing onboarding in a sheet has
        // to move this tab to the kitchen, and nothing else would notice.
        .task(id: showingOnboarding) {
            guard !showingOnboarding else { return }
            await session.refreshAfterRegistration()
        }
    }

    private func row(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(LK.Typography.navBar)
                        .foregroundStyle(LK.Palette.ink)
                    Text(detail)
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }
}
