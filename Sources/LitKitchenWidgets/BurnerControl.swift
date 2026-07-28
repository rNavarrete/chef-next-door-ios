import AppIntents
import SwiftUI
import WidgetKit

/// Shared state between the app and the control. A real implementation writes
/// through to `open_kitchen()` / `close_kitchen()`; the App Group is the local
/// mirror so the control renders correctly before the network round-trip.
enum BurnerState {
    static let suiteName = "group.com.litkitchen.app"
    static let key = "burner.isOn"

    static var isOn: Bool {
        get { UserDefaults(suiteName: suiteName)?.bool(forKey: key) ?? false }
        set { UserDefaults(suiteName: suiteName)?.set(newValue, forKey: key) }
    }
}

/// Toggling the burner from Control Center or the Lock Screen.
///
/// The cook's most-used control in the entire product — they flip it every time
/// they cook, often one-handed with flour on their hands. Cutting it from ~6
/// taps to one is the point (`PRD.md` §6).
struct ToggleBurnerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Burner"
    static let description = IntentDescription("Turn your kitchen's light on or off.")

    @Parameter(title: "Cooking")
    var value: Bool

    init() {}
    init(value: Bool) { self.value = value }

    func perform() async throws -> some IntentResult {
        // Spike scope: local state only. Wiring to open_kitchen() /
        // close_kitchen() is M1 — and note the asymmetry the design requires:
        // one tap to open, HOLD to close, so it can't happen in a pocket.
        // A Control Center toggle cannot express hold-to-close, which is a
        // real constraint worth designing around rather than ignoring.
        BurnerState.isOn = value
        return .result()
    }
}

/// iOS 18+. This is the single strongest native-vs-web argument in the product:
/// a web competitor cannot put a control on the Lock Screen at all.
@available(iOS 18.0, *)
struct BurnerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.litkitchen.app.burner") {
            ControlWidgetToggle(
                "Burner",
                isOn: BurnerState.isOn,
                action: ToggleBurnerIntent()
            ) { isOn in
                Label(
                    isOn ? "Cooking" : "Light's off",
                    systemImage: isOn ? "flame.fill" : "flame"
                )
            }
            .tint(Color(red: 0.961, green: 0.647, blue: 0.141))   // lamp — this IS the heat
        }
        .displayName("Burner")
        .description("Turn your kitchen's light on when you're cooking.")
    }
}
