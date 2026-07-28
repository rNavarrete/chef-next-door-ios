import SwiftUI
import UIKit

/// APNs hands the device token to the app delegate and nowhere else — there is
/// no SwiftUI equivalent — so the app keeps one purely to receive it.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in PushRegistrar.shared.store(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Expected on the simulator, which has no APNs. Not worth surfacing:
        // notifications are the only thing lost, and the app still works.
        print("remote notification registration failed: \(error)")
    }
}

@main
struct LitKitchenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Splash, then the app. Held in the scene rather than inside `RootView`
    /// so the tab bar and its four view models are not built behind the splash
    /// — the point is to cover the launch, not to race it.
    @State private var showingSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showingSplash {
                    SplashView()
                        .transition(.opacity)
                        // Above the app during the crossfade, so the tab bar
                        // never shows through the fade.
                        .zIndex(1)
                } else {
                    RootView()
                }
            }
            .task {
                // Long enough for the character to land and be read, short
                // enough that a cook checking their inbox doesn't resent it.
                // A splash that outstays its welcome is worse than none.
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.easeOut(duration: 0.42)) { showingSplash = false }
            }
        }
    }
}
