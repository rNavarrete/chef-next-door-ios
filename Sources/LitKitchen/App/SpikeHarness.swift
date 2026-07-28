import ActivityKit
import SwiftUI

/// M0 spike harness. Exists to prove the Live Activity starts, renders, and
/// ends on a real device and in the simulator. **Delete when M3 builds the
/// real claim flow** — this is scaffolding, not a feature.
@available(iOS 16.2, *)
struct SpikeHarness: View {
    @State private var activity: Activity<CookingActivityAttributes>?
    @State private var message: String = ""
    @State private var isCooking = true
    @State private var stage: CookingActivityAttributes.Stage = .waiting

    private var attributes: CookingActivityAttributes {
        CookingActivityAttributes(
            cookName: "María",
            threadID: "spike-thread-0001"
        )
    }

    private var state: CookingActivityAttributes.ContentState {
        .init(
            stage: stage,
            cookIsCooking: isCooking,
            itemSummary: "6 tamales de puerco",
            priceSummary: "$18 · $3 each",
            addressLine: stage == .confirmed ? "1148 N Puente Ave, Covina" : "",
            sinceLabel: "since 9:40 am",
            directionsURL: stage == .confirmed
                ? URL(string: "maps://?daddr=1148+N+Puente+Ave,Covina,CA")
                : nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live Activity spike")
                .font(LK.Typography.titleSecondary)
                .foregroundStyle(LK.Palette.ink)

            Text("Activities enabled: \(CookingActivityManager.shared.areEnabled ? "yes" : "no")")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkTertiary)

            Button("Start activity") {
                do {
                    activity = try CookingActivityManager.shared.start(
                        attributes: attributes, state: state
                    )
                    let mode = CookingActivityManager.shared.lastStartMode?.rawValue ?? "?"
                    message = "started [\(mode)]: \(activity?.id ?? "—")"
                } catch {
                    message = String(describing: error)
                }
            }
            .buttonStyle(.borderedProminent)

            Button(stage == .waiting ? "Cook says yes → confirmed" : "Back to 'waiting'") {
                stage = stage == .waiting ? .confirmed : .waiting
                guard let activity else { return }
                Task {
                    await CookingActivityManager.shared.update(activity, to: state)
                    message = "updated → stage: \(stage.rawValue)"
                }
            }
            .buttonStyle(.bordered)
            .disabled(activity == nil)

            Button(isCooking ? "Push to 'unconfirmed'" : "Push to 'cooking'") {
                isCooking.toggle()
                guard let activity else { return }
                Task {
                    await CookingActivityManager.shared.update(activity, to: state)
                    message = "updated → cooking: \(isCooking)"
                }
            }
            .buttonStyle(.bordered)
            .disabled(activity == nil)

            Button("End activity") {
                guard let activity else { return }
                Task {
                    await CookingActivityManager.shared.end(activity)
                    self.activity = nil
                    message = "ended"
                }
            }
            .buttonStyle(.bordered)
            .disabled(activity == nil)

            if !message.isEmpty {
                Text(message)
                    .font(LK.Typography.ui(12))
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(LK.Metrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LK.Palette.ground)
        .tint(LK.Palette.action)
    }
}
