import CoreLocation
import SwiftUI

/// Setting up a kitchen, once there's an account to attach it to.
///
/// Deliberately one scrolling form rather than a wizard. A cook doing this is
/// sitting down to it once; splitting five short sections across five screens
/// would hide how little is actually being asked and make the permit question
/// feel like a gate rather than an aside.
struct CookOnboardingView: View {
    @Bindable var session: SessionController

    @State private var form = CookRegistration()
    @State private var service = CookRegistrationService()
    @State private var rules: AgencyRules?
    /// The city `rules` was fetched for. Rendering is gated on this matching
    /// the field, which is the only check immune to the snapshot staleness
    /// described at the lookup site.
    @State private var rulesCity = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var lookupTask: Task<Void, Never>?
    @State private var avatarURL: String?
    @State private var permitResult: PermitCheckResult?
    /// The county check run *before* registration. This is what gates the
    /// button; `permitResult` is the authoritative one that runs after.
    @State private var preflight: PermitCheckResult?
    @State private var permitTask: Task<Void, Never>?
    @State private var isCheckingPermit = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                aboutYou
                whereYouCook
                if let rules, rulesCity == form.city.trimmed { agencyNotice(rules) }
                permit
                submitButton
                submitBlockedNote

                if let errorMessage {
                    Text(errorMessage)
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Your street address is never shown on the map. Buyers see an approximate area, and get the address only when you choose to share it.")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(LK.Metrics.screenPadding)
        }
        .background(LK.Palette.ground)
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Set up your kitchen")
                .font(LK.Typography.screenTitle)
                .foregroundStyle(LK.Palette.ink)
            Text("Once this is done you can build your menu and open when you're cooking.")
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var aboutYou: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("About you")

            HStack(spacing: 14) {
                PhotoPickerTile(
                    photoURL: $avatarURL, kind: .avatar,
                    size: 76, isCircular: true, emptyLabel: "Add photo"
                )
                Text("A photo of you or your kitchen. Neighbors are deciding whether to knock on a stranger's door — a face makes that easier.")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 2)

            GroupedCard {
                LabeledField(
                    label: "Name", text: $form.displayName,
                    placeholder: "Yolanda C.",
                    capitalization: .words
                )
                Divider().overlay(LK.Palette.hairline)
                // How buyers reach you — we hand off the conversation, we
                // don't host it, so this is the whole contact model.
                HStack(spacing: 12) {
                    Text("Reach you")
                        .font(LK.Typography.body)
                        .foregroundStyle(LK.Palette.ink)
                        .frame(width: 96, alignment: .leading)
                    Picker("", selection: $form.contactMethod) {
                        ForEach(ContactMethod.allCases, id: \.self) { method in
                            Text(method.label).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Divider().overlay(LK.Palette.hairline)
                LabeledField(
                    label: form.contactMethod == .instagram ? "Handle" : "Number",
                    text: $form.contactValue,
                    placeholder: form.contactMethod.placeholder,
                    capitalization: .never,
                    keyboard: form.contactMethod == .instagram ? .default : .phonePad
                )
            }
        }
    }

    private var whereYouCook: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Where you cook")
            GroupedCard {
                LabeledField(
                    label: "Street", text: $form.street,
                    placeholder: "1148 N Puente Ave",
                    capitalization: .words
                )
                Divider().overlay(LK.Palette.hairline)
                LabeledField(
                    label: "City", text: $form.city,
                    placeholder: "Covina",
                    capitalization: .words
                )
                Divider().overlay(LK.Palette.hairline)
                LabeledField(
                    label: "ZIP", text: $form.postalCode,
                    placeholder: "91722",
                    capitalization: .never, keyboard: .numberPad
                )
            }
        }
        // The city determines the enforcement agency, and the agency determines
        // whether meals are even legal here. Asked as soon as it's answerable.
        .onChange(of: form.city) { _, city in
            lookupTask?.cancel()
            // Cleared immediately, and the result is re-checked against the
            // field below. Relying on task cancellation alone was not enough:
            // typing "Pasadena" fires a lookup for the intermediate "Pas",
            // which matches no city department and falls back to LA County —
            // and that answer raced ahead of the real one. The screen then told
            // a Pasadena cook that hot meals were allowed, which is exactly
            // backwards and exactly the mistake this notice exists to prevent.
            rules = nil
            guard city.trimmed.count >= 3 else { return }
            lookupTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                let found = await service.rules(forCity: city)
                guard !Task.isCancelled else { return }
                // Recorded with the city it answers for. The comparison happens
                // at render time, not here: this closure captures a snapshot of
                // the view taken at the last render, so `form.city` read from
                // inside it lags the field by a keystroke or more and is not a
                // sound thing to compare against.
                rules = found
                rulesCity = city.trimmed
            }
        }
    }

    /// What this city actually allows.
    ///
    /// This is the single most useful thing onboarding can tell a cook, and
    /// the one most likely to be wrong if they guess: two cooks a couple of
    /// miles apart can be under different regimes, because MEHKO is opt-in per
    /// enforcement agency and three LA County cities run their own.
    private func agencyNotice(_ rules: AgencyRules) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: rules.mehkoOptedIn ? "checkmark.seal" : "info.circle")
                    .font(LK.Typography.ui(14, weight: .semibold))
                Text(rules.mehkoOptedIn ? "Meals are allowed here" : "Baked goods only here")
                    .font(LK.Typography.bodyEmphasis)
            }
            .foregroundStyle(rules.mehkoOptedIn ? LK.Palette.action : LK.Palette.ink)

            Text(rules.mehkoOptedIn
                 ? "\(rules.name) enforces home kitchens in \(form.city.trimmed) and has opted into MEHKO, so hot meals are permitted with a MEHKO permit."
                 : "\(rules.name) enforces home kitchens in \(form.city.trimmed) and hasn't opted into MEHKO. Cottage food — baked goods, jams, things that don't need refrigeration — is still allowed.")
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkQuiet)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (rules.mehkoOptedIn ? LK.Palette.chip : LK.Palette.chip),
            in: RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous)
        )
    }

    private var permit: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Permit")

            // Nothing here blocks the account. A cook who is mid-application —
            // which is most new cooks — can finish signup, build a menu and
            // start cooking; only the badge waits.
            VStack(spacing: 0) {
                ForEach([PermitStage.have, .applying, .later], id: \.self) { stage in
                    if stage != .have { Divider().overlay(LK.Palette.hairline).padding(.leading, 14) }
                    Button {
                        form.permitStage = stage
                        if stage != .have { form.permitNumber = "" }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: form.permitStage == stage
                                  ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(form.permitStage == stage
                                                 ? LK.Palette.action : LK.Palette.inkTertiary)
                            Text(stage.label)
                                .font(LK.Typography.body)
                                .foregroundStyle(LK.Palette.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous)
                    .strokeBorder(LK.Palette.hairline, lineWidth: 0.5)
            }

            if form.permitStage == .have {
                FlowLayout(spacing: 7) {
                    ForEach(PermitKind.allCases, id: \.self) { kind in
                        let isSelected = form.permitKind == kind
                        Button {
                            form.permitKind = isSelected ? nil : kind
                        } label: {
                            Text(kind.label)
                                .font(LK.Typography.ui(13.5, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : LK.Palette.inkQuiet)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(isSelected ? LK.Palette.ink : LK.Palette.chip, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                GroupedCard {
                    LabeledField(
                        label: "Number", text: $form.permitNumber,
                        placeholder: "PR0366690",
                        capitalization: .characters
                    )
                }

                // Shape first, register second. A missing digit and a permit
                // that isn't on the county list are different problems, and
                // saying "not on the list" to someone who simply mistyped
                // reads as an accusation.
                if !form.permitNumber.trimmed.isEmpty, !form.permitNumberIsWellFormed {
                    permitNote(
                        icon: "exclamationmark.circle",
                        "County permit numbers are PR followed by seven digits, like PR0366690."
                    )
                } else if isCheckingPermit {
                    permitNote(icon: "clock", "Checking the county register…")
                }

                Text("We check this against the county's published list before you finish — no documents, no waiting on us. Permit numbers are public record and shown on your kitchen page.")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

            } else if form.permitStage == .applying {
                Text("That's fine — set everything up now. We re-check the county list every day, and the badge appears on your kitchen by itself once your permit is published.")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkQuiet)
                    .fixedSize(horizontal: false, vertical: true)

            } else if form.permitStage == .later {
                Text("You can add it any time from your kitchen. Until then your listing just won't carry a permit badge.")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkQuiet)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let rules, rulesCity == form.city.trimmed,
               let kind = form.permitKind, kind.allowsMeals, !rules.mehkoOptedIn {
                Text("Heads up: \(rules.name) hasn't opted into MEHKO, so a MEHKO permit won't apply in \(form.city.trimmed).")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The post-registration result wins once it exists: it is the one
            // that actually set `permit_status`.
            if let shown = permitResult ?? preflight { permitOutcome(shown) }
        }
        // Re-checked whenever the number or the address it is corroborated
        // against changes. Both matter: the same number is `verified` in one
        // city and `wrong_area` in the next, so a cook who fixes their ZIP
        // after a failed check must not stay blocked on the stale answer.
        .onChange(of: form.permitNumber) { _, _ in schedulePermitCheck() }
        .onChange(of: form.city) { _, _ in schedulePermitCheck() }
        .onChange(of: form.postalCode) { _, _ in schedulePermitCheck() }
        .onChange(of: form.permitStage) { _, stage in
            // Leaving the "I have it" path drops the check with the claim.
            if stage != .have {
                permitTask?.cancel()
                preflight = nil
                isCheckingPermit = false
            } else {
                schedulePermitCheck()
            }
        }
    }

    private func permitNote(icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: icon).font(LK.Typography.ui(13, weight: .semibold))
            Text(text)
                .font(LK.Typography.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(LK.Palette.inkQuiet)
    }

    /// Debounced county check, on the same 400ms as the agency lookup.
    ///
    /// `preflight` is cleared synchronously rather than left showing while a
    /// new check runs. Otherwise a cook who corrected a rejected number would
    /// see the old "we couldn't match it" sitting under the field for as long
    /// as the round trip took, and the button would still be enabled off the
    /// *previous* answer if they had corrected it in the other direction.
    private func schedulePermitCheck() {
        permitTask?.cancel()
        preflight = nil
        isCheckingPermit = false

        guard form.permitStage == .have,
              form.permitNumberIsWellFormed,
              form.city.trimmed.count >= 3
        else { return }

        let number = form.normalizedPermitNumber
        let city = form.city.trimmed
        let zip = form.postalCode.trimmed
        isCheckingPermit = true

        permitTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let result = await service.preflightPermit(number, city: city, postalCode: zip)
            guard !Task.isCancelled else { return }
            // Compared against the live fields, not the captured ones: this
            // closure holds a snapshot from the last render, so the same
            // staleness that bit the agency lookup applies here.
            guard number == form.normalizedPermitNumber,
                  city == form.city.trimmed else { return }
            preflight = result
            isCheckingPermit = false
        }
    }

    /// What the check actually found.
    ///
    /// Each case says what is true rather than pass/fail. "Not on the list"
    /// is not an accusation — the county publishes daily and a permit issued
    /// this week may simply not be there yet — and a cook in Pasadena can
    /// never be checked at all, which is a fact about our data, not about them.
    @ViewBuilder
    private func permitOutcome(_ result: PermitCheckResult) -> some View {
        let verified = result.outcome.isVerified
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: verified ? "checkmark.seal.fill" : "clock")
                    .font(LK.Typography.ui(14, weight: .semibold))
                Text(verified ? "Matched the county register" : "We couldn't match it yet")
                    .font(LK.Typography.bodyEmphasis)
            }
            .foregroundStyle(verified ? LK.Palette.action : LK.Palette.inkQuiet)

            Text(explanation(for: result))
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkQuiet)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            verified ? LK.Palette.chip : LK.Palette.chip,
            in: RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous)
        )
    }

    private func explanation(for result: PermitCheckResult) -> String {
        switch result.outcome {
        case .verified:
            let name = result.registeredName.map { " — listed as “\($0)”" } ?? ""
            return "\(result.agencyName ?? "The county") lists this permit at your address\(name). Your kitchen shows a permit badge. If that name isn't yours, check the number."
        case .notFound:
            return "That number isn't on the county's published list. New permits take a few days to appear, so if you've just been approved this is normal — we re-check daily and the badge appears on its own. Double-check the digits otherwise."
        case .wrongArea:
            return "That permit is on the county list, but registered to a different city. Check the number — badges only apply to the address you cook at."
        case .alreadyClaimed:
            return "Another kitchen here already uses that permit number. If it's yours, get in touch and we'll sort it out."
        case .agencyNotCovered:
            return "\(result.agencyName ?? "Your city") runs its own health department, so its permits aren't in the county's published list and we can't check automatically. You can still cook — your kitchen just won't carry a badge."
        }
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            Group {
                if isSubmitting { ProgressView().tint(.white) }
                else { Text("Open my kitchen").font(LK.Typography.navBarEmphasis) }
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

    @ViewBuilder
    private var submitBlockedNote: some View {
        if let submitBlockedReason {
            Text(submitBlockedReason)
                .font(LK.Typography.meta)
                .foregroundStyle(LK.Palette.inkQuiet)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var canSubmit: Bool { form.isComplete && !isSubmitting && permitCleared }

    /// A cook claiming a permit has to have cleared the register first.
    ///
    /// Only the `.have` path is gated. `.applying` and `.later` are honest
    /// statements about where someone is and open a kitchen without a badge,
    /// exactly as before — see `CookRegistration.isComplete`.
    private var permitCleared: Bool {
        guard form.permitStage == .have else { return true }
        guard let preflight else { return false }
        return !preflight.outcome.blocksRegistration
    }

    /// Why the button is off, when the reason isn't just "keep typing".
    ///
    /// A disabled control with no explanation is the worst version of this
    /// gate: the cook has filled everything in, the button is grey, and
    /// nothing on screen connects that to the permit field. The outcome card
    /// above says what the register found; this says what it means for them.
    private var submitBlockedReason: String? {
        guard form.permitStage == .have, !isSubmitting else { return nil }
        guard form.permitNumberIsWellFormed else { return nil }   // the field says it
        if isCheckingPermit { return nil }                        // the spinner says it
        guard let preflight else { return nil }
        guard preflight.outcome.blocksRegistration else { return nil }
        return "You can open your kitchen without a permit number — choose “I've applied” or “I'll sort this out later” above. What we can't do is show a permit badge we couldn't match."
    }

    private func submit() {
        isSubmitting = true
        errorMessage = nil
        Task {
            defer { isSubmitting = false }
            do {
                let coordinate = try await service.coordinate(for: form)
                try await service.register(form, at: coordinate)
                // After registration, not before: the photo is already in
                // storage under this user's folder, but `set_cook_avatar`
                // updates a `cooks` row that doesn't exist until now.
                if let avatarURL {
                    try? await PhotoUploader().setAvatar(url: avatarURL)
                }
                // Checked against the county's published register, right here.
                // No document, no reviewer, no waiting — the cook types a
                // number they already have and finds out immediately.
                if !form.permitNumber.trimmed.isEmpty {
                    permitResult = await service.checkPermit(form.permitNumber)
                }
                // Flips the Kitchen tab over to the real cook surfaces.
                await session.refreshAfterRegistration()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't set up your kitchen. Try again in a moment."
            }
        }
    }
}
