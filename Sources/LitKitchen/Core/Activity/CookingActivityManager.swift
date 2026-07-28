// @preconcurrency: ActivityKit's `Activity` and `ActivityContent` carry no
// Sendable annotations in the current SDK, so Swift 6 strict concurrency flags
// every `await activity.update(...)` as a potential data race. This is the
// documented escape for a not-yet-audited framework — not a workaround for our
// own unsafety. Revisit when ActivityKit ships Sendable conformances.
@preconcurrency import ActivityKit
import Foundation
import os

/// Starts, updates, and ends the Live Activity for an active claim.
///
/// Three constraints this wraps, all of which are easy to get wrong silently:
///
/// 1. **`NSSupportsLiveActivities` must be in the app's Info.plist.** Without
///    it `Activity.request` throws and nothing appears — no error visible to
///    the user, no activity.
/// 2. **ActivityKit push uses its own APNs push type** (`liveactivity`), on a
///    per-activity token that differs from the device token. Sending a normal
///    alert push to it does nothing.
/// 3. **The activity must be ended explicitly.** There is no pickup window to
///    expire against, so it will otherwise sit on the Lock Screen until
///    iOS's own stale timeout — which for a handoff card is a bad look.
/// `@MainActor` because `tokenTask` is mutable shared state and Swift 6 strict
/// concurrency correctly refuses a bare singleton over it. Activity lifecycle
/// is driven from the UI anyway, so the main actor is the honest home for it
/// rather than a lock or an `nonisolated(unsafe)` escape hatch.
@available(iOS 16.2, *)
@MainActor
public final class CookingActivityManager {
    public static let shared = CookingActivityManager()

    private let log = Logger(subsystem: "com.litkitchen.app", category: "LiveActivity")
    private var tokenTask: Task<Void, Never>?

    private init() {}

    public enum StartError: Error, CustomStringConvertible {
        case notEnabled
        case failed(String)

        public var description: String {
            switch self {
            case .notEnabled:
                "Live Activities are disabled for this app. The user can turn them off in Settings, and Focus modes suppress them — always handle this rather than assuming success."
            case .failed(let message):
                "Could not start the Live Activity: \(message)"
            }
        }
    }

    public var areEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    public enum StartMode: String, Sendable {
        /// Server can push updates. Requires the push entitlement.
        case pushUpdatable
        /// App-driven updates only. Works with no entitlement and no signing.
        case localOnly
    }

    public private(set) var lastStartMode: StartMode?

    /// Attempts a push-updatable activity and falls back to local-only.
    ///
    /// **The fallback is not defensive padding — it's a real deployment mode.**
    /// `pushType: .token` requires the push entitlement (`aps-environment`),
    /// which requires a signing team. Without one, `Activity.request` fails
    /// with `SessionCore.PermissionsError Code=3` and *no activity appears at
    /// all* — so an unsigned build would show nothing rather than degrade.
    ///
    /// Falling back means the Live Activity still works during development and
    /// for any user whose push registration failed; it just won't reflect the
    /// cook's decay-ladder changes until the app is foregrounded.
    @discardableResult
    public func start(
        attributes: CookingActivityAttributes,
        state: CookingActivityAttributes.ContentState,
        staleDate: Date? = nil
    ) throws -> Activity<CookingActivityAttributes> {
        guard areEnabled else { throw StartError.notEnabled }

        let content = ActivityContent(state: state, staleDate: staleDate)

        do {
            let activity = try Activity.request(
                attributes: attributes, content: content, pushType: .token
            )
            lastStartMode = .pushUpdatable
            log.info("started (push) \(activity.id, privacy: .public)")
            observeTokens(for: activity)
            return activity
        } catch {
            log.warning("push-updatable start failed, falling back to local: \(String(describing: error), privacy: .public)")
            do {
                let activity = try Activity.request(
                    attributes: attributes, content: content, pushType: nil
                )
                lastStartMode = .localOnly
                log.info("started (local) \(activity.id, privacy: .public)")
                return activity
            } catch {
                throw StartError.failed(String(describing: error))
            }
        }
    }

    /// The per-activity push token. **Not** the device token, and it can be
    /// reissued during the activity's life, so this observes rather than
    /// reading once.
    private func observeTokens(for activity: Activity<CookingActivityAttributes>) {
        tokenTask?.cancel()
        tokenTask = Task { [log, onToken] in
            // `pushTokenUpdates` is a stream, not a one-shot: ActivityKit
            // reissues the token during the activity's life, and a stale one
            // silently stops delivering. Every value has to be sent on.
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                log.info("push token for \(activity.attributes.threadID, privacy: .public): \(token, privacy: .private)")
                await onToken?(activity.attributes.threadID, token, activity.id)
            }
        }
    }

    /// Called with every token ActivityKit issues. Set by the app at launch;
    /// left as a closure so this stays free of any networking dependency.
    public var onToken: (@MainActor (String, String, String) async -> Void)?

    public func update(
        _ activity: Activity<CookingActivityAttributes>,
        to state: CookingActivityAttributes.ContentState,
        staleDate: Date? = nil
    ) async {
        await activity.update(.init(state: state, staleDate: staleDate))
    }

    /// Called when the claim completes or is cancelled — **not** on a timer.
    /// There is no pickup window to expire against, so nothing ends this card
    /// but us; left alone it sits on the Lock Screen until iOS's own stale
    /// timeout, which for a handoff card reads as the app forgetting about you.
    ///
    /// Passes `nil` content deliberately: with `.immediate` the final state is
    /// never rendered, so supplying one is both pointless and — because
    /// `ActivityContent` is not `Sendable` — a strict-concurrency error.
    public func end(_ activity: Activity<CookingActivityAttributes>) async {
        await activity.end(nil, dismissalPolicy: .immediate)
        tokenTask?.cancel()
    }

    /// Activities survive app termination, so on launch we adopt whatever is
    /// still running rather than orphaning it.
    public func adoptExisting() -> [Activity<CookingActivityAttributes>] {
        let existing = Activity<CookingActivityAttributes>.activities
        for activity in existing { observeTokens(for: activity) }
        return existing
    }

    public func activity(forThread threadID: String) -> Activity<CookingActivityAttributes>? {
        Activity<CookingActivityAttributes>.activities
            .first { $0.attributes.threadID == threadID }
    }

    /// Starts the activity if this claim has none, otherwise moves the existing
    /// one to `state`. Callers care about "the card should say this now", not
    /// about which of the two calls that requires.
    ///
    /// Returns the failure rather than throwing, because no caller can
    /// meaningfully recover — but every caller should be able to *log* it. The
    /// previous `try?` at the call site meant a card that never appeared left
    /// no trace anywhere.
    @discardableResult
    public func sync(
        attributes: CookingActivityAttributes,
        state: CookingActivityAttributes.ContentState,
        staleDate: Date? = nil
    ) async -> StartError? {
        if let existing = activity(forThread: attributes.threadID) {
            // Also re-push when only the stale date moved, or a card that was
            // started before the cook confirmed would never acquire one.
            let sameStaleDate = existing.content.staleDate == staleDate
            guard existing.content.state != state || !sameStaleDate else { return nil }
            await update(existing, to: state, staleDate: staleDate)
            return nil
        }
        do {
            _ = try start(attributes: attributes, state: state, staleDate: staleDate)
            return nil
        } catch let error as StartError {
            log.error("sync failed: \(error.description, privacy: .public)")
            return error
        } catch {
            let wrapped = StartError.failed(String(describing: error))
            log.error("sync failed: \(wrapped.description, privacy: .public)")
            return wrapped
        }
    }
}
