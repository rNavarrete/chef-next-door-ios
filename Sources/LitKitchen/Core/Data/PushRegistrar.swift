import Foundation
import UIKit
import UserNotifications
import os

/// Asks for notification permission and keeps the device token on the server.
///
/// **When to ask matters more than how.** iOS gives an app exactly one shot at
/// the system prompt; a "Don't Allow" is effectively permanent, recoverable only
/// through Settings. So this deliberately does *not* fire on launch, when a
/// person has no idea what they'd be agreeing to. It is called the first time
/// someone sends a message or places an order — the moment a reply is something
/// they are actually waiting for, and the one moment the request explains
/// itself.
///
/// Separate from the Live Activity token (`live_activity_tokens`): that is one
/// token per card, issued by ActivityKit. This is one per device, issued by
/// APNs, and it is what makes a cook's phone ring when an order lands.
@MainActor
public final class PushRegistrar: NSObject {
    public static let shared = PushRegistrar()

    private let log = Logger(subsystem: "com.litkitchen.app", category: "push")
    private var repository: (any MessageRepository)?
    /// The last APNs token, **persisted**.
    ///
    /// Kept so sign-out can retire it. The token belongs to the device, but the
    /// *routing* belongs to the account that registered it — leaving it behind
    /// means the next person to use this handset gets someone else's orders.
    ///
    /// APNs hands the token to the app delegate once per launch. Holding it
    /// only in memory meant that after a relaunch this was nil, so a sign-out
    /// deleted nothing and the handset stayed registered to an account that had
    /// left it — see migration 059, where one token was found live on three
    /// accounts at once.
    private var lastToken: String? {
        get { UserDefaults.standard.string(forKey: Self.tokenKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.tokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.tokenKey)
            }
        }
    }

    private static let tokenKey = "litkitchen.lastAPNsToken"
    private let presenter = PushPresentationDelegate()

    public func configure(repository: (any MessageRepository)?) {
        self.repository = repository
        UNUserNotificationCenter.current().delegate = presenter
    }

    /// Asks, if we have never asked. Safe to call on every send.
    public func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge]))
                ?? false
            log.info("notification permission granted: \(granted, privacy: .public)")
            guard granted else { return }
        case .denied:
            // Nothing to do and nothing to nag about. A person who said no is
            // entitled to have that stay answered.
            return
        default:
            break
        }

        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Called from the app delegate once APNs issues a token.
    public func store(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        lastToken = token
        Task { [repository, log] in
            do {
                try await repository?.registerDeviceToken(token)
                log.info("device token registered")
            } catch {
                // Best-effort: a token that fails to register costs
                // notifications, not messages, and APNs reissues on next launch.
                log.error("device token registration failed: \(error, privacy: .public)")
            }
        }
    }

    public func forgetToken() async {
        guard let lastToken else { return }
        try? await repository?.forgetDeviceToken(lastToken)
        // Cleared only after the server call. If it failed, the next sign-out
        // — or the next `register_device_token`, which now claims the token
        // away from other accounts — still gets a chance to clean up.
        self.lastToken = nil
    }
}

/// The delegate is deliberately a separate, non-isolated object.
///
/// `UNUserNotificationCenterDelegate` is called from an arbitrary context with
/// non-`Sendable` arguments, so conforming `PushRegistrar` — which is
/// `@MainActor` — is a Swift 6 error rather than a warning. Splitting it keeps
/// the isolation honest instead of papering over it with `nonisolated(unsafe)`.
final class PushPresentationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    /// Show the banner even with the app open. A cook with the app in front of
    /// them is usually looking at their menu, not their inbox — suppressing it
    /// is how an order gets missed by someone who is *using the app*.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
