import PhotosUI
import SwiftUI

/// The registration gate, as a screen.
///
/// Browsing, claiming, following and reviewing all work anonymously. Messaging
/// does not, and this sheet is where that difference is explained rather than
/// merely enforced. Two reasons a person can act on, and no third:
///
///   * The cook sees who they're talking to. A name is not decoration here —
///     the thing on the other end is a stranger arriving at someone's home.
///   * An anonymous identity costs nothing to make, so rate-limiting one is
///     theatre. A real account is what makes a block mean anything.
///
/// **One sheet, both steps.** The server has two gates (`P0002` no account,
/// `P0003` no name) but a person experiences one interruption, so the name
/// field appears in place the moment Apple returns — no dismissal, no second
/// sheet. Apple usually fills it in on first authorization, in which case this
/// collapses to a single tap.
struct MessagingGateSheet: View {
    @Bindable var session: SessionController
    let profiles: any ProfileRepository
    /// Called once the account *and* the name both exist.
    var onReady: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var photo: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isSaving = false
    @State private var error = ""
    /// Nil until checked, so the sheet doesn't flash the wrong step.
    @State private var step: MessagingGate?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LK.Metrics.blockSpacing) {
                    header

                    switch step {
                    case .needsAccount: accountStep
                    case .needsProfile: nameStep
                    case nil:           ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    }

                    if !error.isEmpty {
                        Text(error)
                            .font(LK.Typography.meta)
                            .foregroundStyle(LK.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(LK.Metrics.screenPadding)
            }
            .background(LK.Palette.ground)
            // No navigation title. It said "Message a kitchen" directly above a
            // heading that says "Messages need an account" — the same sentence
            // twice, and on iOS 26 the toolbar button crowded it off centre.
            // The body heading is the title.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
        .task { await refreshStep() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step == .needsProfile ? "What should cooks call you?"
                                       : "Messages need an account")
                .font(LK.Typography.titleSecondary)
                .foregroundStyle(LK.Palette.ink)

            Text(step == .needsProfile
                 ? "This is the name a cook sees on your messages and your orders. A photo is optional."
                 : "You can browse without one. Messaging is different — a cook should know who's writing to them.")
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.inkQuiet)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accountStep: some View {
        VStack(spacing: 10) {
            AppleSignInButton(session: session) {
                Task { await refreshStep() }
            }
            if let signInError = session.signInError, !signInError.isEmpty {
                Text(signInError)
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Only true when there is an anonymous identity to upgrade. Fully
            // signed out, Apple creates a *new* account and nothing carries
            // over — promising otherwise is a promise the sign-in cannot keep.
            if session.userID != nil, session.isAnonymous {
                Text("Your saved kitchens and history carry over — this upgrades the identity you already have rather than starting a new one.")
                    .font(LK.Typography.meta)
                    .foregroundStyle(LK.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var nameStep: some View {
        VStack(spacing: LK.Metrics.blockSpacing) {
            HStack(spacing: 14) {
                PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                    ZStack {
                        ProfileAvatar(name: name.isEmpty ? "?" : name, source: nil, size: 64)
                        if let photoData, let image = UIImage(data: photoData) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                        }
                        Circle()
                            .strokeBorder(LK.Palette.action, lineWidth: photoData == nil ? 0 : 2)
                            .frame(width: 64, height: 64)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(LK.Typography.ui(10.5, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(LK.Palette.action, in: Circle())
                    }
                }
                .buttonStyle(.plain)

                GroupedCard {
                    LabeledField(
                        label: "Name", text: $name, placeholder: "Marisol",
                        capitalization: .words
                    )
                }
            }

            Button {
                Task { await save() }
            } label: {
                ZStack {
                    Text("Start messaging")
                        .font(LK.Typography.navBarEmphasis)
                        .foregroundStyle(.white)
                        .opacity(isSaving ? 0 : 1)
                    if isSaving { ProgressView().tint(.white) }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    name.trimmingCharacters(in: .whitespaces).isEmpty
                        ? LK.Palette.inkTertiary : LK.Palette.action,
                    in: RoundedRectangle(cornerRadius: LK.Metrics.radiusButton, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                photoData = try? await item.loadTransferable(type: Data.self)
            }
        }
    }

    private func refreshStep() async {
        // Asking the server rather than reading `session.isAnonymous`: the
        // profile half of the gate isn't visible from the client's session at
        // all, and a stale local guess would show the wrong step.
        let repo = SupabaseMessageRepository()
        step = (try? await repo.gate()) ?? (session.isAnonymous ? .needsAccount : .needsProfile)

        if step == .needsProfile, name.isEmpty {
            // Apple usually seeded this on first authorization; prefill so the
            // common path is one tap rather than retyping a name we have.
            name = (try? await profiles.myProfile())?.displayName ?? ""
        }
        if step == nil { onReady(); dismiss() }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        error = ""
        do {
            var path: String?
            if let photoData {
                path = try await profiles.uploadAvatar(photoData)
            }
            try await profiles.saveProfile(name: name, avatarPath: path)
            onReady()
            dismiss()
        } catch {
            self.error = UserFacingError.message(
                for: error, fallback: "Couldn't save that. Try again in a moment."
            )
        }
    }
}
