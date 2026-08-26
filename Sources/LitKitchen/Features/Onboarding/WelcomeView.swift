import SwiftUI

/// One screen, once, and then never again.
///
/// Not a carousel. NN/g tested the deck-of-cards pattern with 70 users across 4
/// apps: it did not improve task performance and it "makes the interface appear
/// more complicated than it actually is". People skip it, and anything they did
/// read is unavailable at the moment they need it. What the research *does*
/// support is a single screen stating the problem the app solves before any
/// feature is explained.
///
/// ## Why these three sentences and not others
///
/// Three facts about this app cannot be worked out by looking at it, and each
/// one costs a real interaction when someone gets it wrong: they expect a
/// checkout that does not exist, or delivery that is not offered, or they
/// assume the food is a standing menu rather than something being cooked now.
/// Everything else — how to search, what a permit badge means, how to open a
/// kitchen — is explained where it happens.
///
/// ## The button is also the location prime
///
/// Apple's location dialog currently arrives cold on first launch, before
/// anyone knows what the app is for. Behind a button that says "find food near
/// me", it arrives one tap after a sentence explaining why. "Not now" goes
/// straight to the feed and asks for nothing; location can still be granted
/// later from the map.
struct WelcomeView: View {
    /// Called on either path. The caller dismisses and records the flag, so
    /// this view has no opinion about how it is presented.
    let onFinish: (_ wantsLocation: Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image("ChefRunning")
                .resizable()
                .scaledToFit()
                .frame(width: 170, height: 170)
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                Text("Neighbors cooking today")
                    .font(LK.Typography.screenTitle)
                    .foregroundStyle(LK.Palette.ink)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    line("Home cooks near you, making food right now.")
                    line("Message them, arrange a pickup, and pay them directly — we never take a payment or a fee.")
                    line("Everyone here is somebody's neighbor.")
                }
            }
            .padding(.horizontal, LK.Metrics.screenPadding)
            .padding(.top, 20)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    onFinish(true)
                } label: {
                    Text("Find food near me")
                        .font(LK.Typography.navBarEmphasis)
                        .foregroundStyle(LK.Palette.inkOnAction)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            LK.Palette.action,
                            in: RoundedRectangle(cornerRadius: LK.Metrics.radiusButton, style: .continuous)
                        )
                }
                .buttonStyle(.plain)

                Button("Not now") { onFinish(false) }
                    .font(LK.Typography.body)
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, LK.Metrics.screenPadding)
            .padding(.bottom, 28)
        }
        .background(LK.Palette.ground)
        .interactiveDismissDisabled()
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(LK.Typography.body)
            .foregroundStyle(LK.Palette.inkTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }
}
