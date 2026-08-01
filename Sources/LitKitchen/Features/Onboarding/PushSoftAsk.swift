import SwiftUI
import UserNotifications

/// Our own screen, shown before Apple's.
///
/// iOS grants exactly one notification prompt per install. A "Don't Allow" is
/// permanent and recoverable only through Settings, which nobody does — so the
/// prompt is a one-shot resource and firing it cold wastes it. Priming lifts
/// opt-in by two to three times, and the gap is worth having: iOS opt-in sits
/// around 54%, and a cold up-front prompt lands at 40–45%.
///
/// ## The rule this type exists to enforce
///
/// **"Not now" must never reach `requestAuthorization`.** Declining *this*
/// sheet costs nothing and can be asked again at the other trigger; declining
/// Apple's costs the account forever. That asymmetry is the whole reason for
/// the extra screen, and it is easy to lose by wiring both buttons to the same
/// call.
///
/// ## Why there are two triggers and not one
///
/// `requestAuthorizationIfNeeded()` was called from exactly one place — sending
/// a message. A cook who set up a kitchen and waited for buyers was never
/// asked, so the first message they ever received arrived silently, on the one
/// screen the app cannot show them. See `docs/ONBOARDING.md`.
struct PushSoftAsk: View {
    let title: String
    /// Named `message`, not `body` — that one belongs to `View`.
    let message: String
    /// Called after the system prompt resolves, whichever way it went, so the
    /// caller can record that this trigger has now been used.
    var onDecided: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var isAsking = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 14) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(LK.Palette.action)

                Text(title)
                    .font(LK.Typography.screenTitle)
                    .foregroundStyle(LK.Palette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(LK.Typography.body)
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, LK.Metrics.screenPadding)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    Task {
                        isAsking = true
                        // The only path that spends the one prompt.
                        await PushRegistrar.shared.requestAuthorizationIfNeeded()
                        isAsking = false
                        onDecided()
                        dismiss()
                    }
                } label: {
                    Group {
                        if isAsking {
                            ProgressView().tint(LK.Palette.inkOnAction)
                        } else {
                            Text("Yes, tell me")
                                .font(LK.Typography.navBarEmphasis)
                                .foregroundStyle(LK.Palette.inkOnAction)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        LK.Palette.action,
                        in: RoundedRectangle(cornerRadius: LK.Metrics.radiusButton, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isAsking)

                Button("Not now") {
                    // Deliberately does not ask. See the type comment.
                    onDecided()
                    dismiss()
                }
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.inkTertiary)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, LK.Metrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(LK.Palette.ground)
        .presentationDetents([.height(380)])
        .interactiveDismissDisabled(isAsking)
    }
}

/// Whether a one-time prompt has already been shown.
///
/// A plain `UserDefaults` flag rather than anything cleverer: these are
/// per-install nudges, and being wiped by a reinstall is the correct behaviour
/// — a fresh install has a fresh notification permission too.
enum OnboardingFlag {
    case welcome, pushCook, pushBuyer, dialTip

    private var key: String {
        switch self {
        case .welcome:    "litkitchen.hasSeenWelcome"
        case .pushCook:   "litkitchen.askedPushCook"
        case .pushBuyer:  "litkitchen.askedPushBuyer"
        case .dialTip:    "litkitchen.seenDialTip"
        }
    }

    var isSet: Bool { UserDefaults.standard.bool(forKey: key) }
    func set() { UserDefaults.standard.set(true, forKey: key) }

    /// True exactly once, and marks itself used. Checking and recording are one
    /// operation so a caller cannot show a prompt and forget to remember it.
    var claim: Bool {
        guard !isSet else { return false }
        set()
        return true
    }

    /// Pointless to prompt when the answer is already recorded by iOS — asking
    /// somebody who has granted, or who has already refused Apple's dialog,
    /// achieves nothing in the first case and is a dead end in the second.
    static func shouldAsk(_ flag: OnboardingFlag) async -> Bool {
        guard !flag.isSet else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .notDetermined
    }
}
