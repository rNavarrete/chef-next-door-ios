import PhotosUI
import SwiftUI

/// Your own account: who you are, how you got in, and how to leave.
///
/// The app had no such screen. Every piece of it existed server-side —
/// `my_profile()`, `upsert_my_profile`, the private avatars bucket — and there
/// was no way to look at any of it, edit a name after the gate sheet captured
/// one, or even find out which account you were signed in as. **Buyers had no
/// sign-out at all**; only the cook tab offered one, so a buyer who signed in
/// with the wrong Apple ID was simply stuck.
///
/// Kept deliberately short. This is not a settings screen: notification
/// preferences live per-cook on the follow, and blocked kitchens live in Saved
/// where the thing being undone is visible.
/// `@MainActor` on the type, not just `body`. SwiftUI isolates `body` alone, so
/// a stored `any ProfileRepository` — itself `@MainActor` and not `Sendable` —
/// cannot be captured by the escaping async closure the avatar needs without
/// the whole view being isolated too.
@MainActor
struct ProfileView: View {
    @Bindable var session: SessionController
    let profiles: any ProfileRepository

    @Environment(\.dismiss) private var dismiss

    @State private var profile: Profile?
    @State private var name = ""
    @State private var bio = ""
    @State private var photo: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var avatarURL: URL?
    @State private var isSaving = false
    @State private var isLoading = true
    @State private var error = ""
    @State private var showingSignOutConfirm = false
    @State private var showingEmailUpgrade = false

    private var isDirty: Bool {
        photoData != nil ||
        name.trimmingCharacters(in: .whitespaces) != (profile?.displayName ?? "") ||
        bio.trimmingCharacters(in: .whitespaces) != (profile?.bio ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LK.Metrics.blockSpacing) {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                    } else if session.isAnonymous {
                        anonymous
                    } else {
                        identity
                        bioField
                        details
                        signOut
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
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if isDirty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                            .fontWeight(.semibold)
                            .disabled(isSaving)
                    }
                }
            }
        }
        .sheet(isPresented: $showingEmailUpgrade, onDismiss: { Task { await load() } }) {
            UpgradeAccountView(session: session)
        }
        .task { await load() }
    }

    // MARK: - Signed in

    /// Its own row, under the avatar and the name — not beside them. It went
    /// in as a third column of that `HStack` first, which squeezed the field to
    /// a sliver reading "I work night…" next to a name box.
    ///
    /// Prompted with an example rather than the word "Bio". Asked cold, people
    /// write nothing or write a joke; asked "when do you usually collect", they
    /// write the one fact a cook actually needs.
    private var bioField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(
                "I work nights — usually collecting after 10.",
                text: $bio, axis: .vertical
            )
            .lineLimit(2...5)
            .font(LK.Typography.body)
            .foregroundStyle(LK.Palette.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous)
                    .strokeBorder(LK.Palette.hairline, lineWidth: 1)
            }

            HStack {
                Text("Cooks you message can see this.")
                Spacer()
                // Only once it is close enough to matter.
                if bio.count > 240 {
                    Text("\(280 - bio.count)")
                        .monospacedDigit()
                        .foregroundStyle(bio.count > 280 ? LK.Palette.heatInk : LK.Palette.inkTertiary)
                }
            }
            .font(LK.Typography.meta)
            .foregroundStyle(LK.Palette.inkTertiary)
        }
    }

    private var identity: some View {
        HStack(spacing: 14) {
            PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    // The signed URL is resolved once in `load()` rather than
                    // handed over as a closure: this view knows whose avatar it
                    // is, and passing a `@MainActor` repository into an escaping
                    // async closure crosses an isolation boundary for no gain.
                    ProfileAvatar(name: name.isEmpty ? "?" : name, source: nil, size: 72)
                    if let avatarURL, photoData == nil {
                        AsyncImage(url: avatarURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: { Color.clear }
                        .frame(width: 72, height: 72).clipShape(Circle())
                    }
                    if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image)
                            .resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 72).clipShape(Circle())
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(LK.Typography.ui(10.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(LK.Palette.action, in: Circle())
                }
            }
            .buttonStyle(.plain)

            GroupedCard {
                LabeledField(
                    label: "Name", text: $name, placeholder: "Your name",
                    capitalization: .words
                )
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { photoData = try? await item.loadTransferable(type: Data.self) }
        }
    }

    private var details: some View {
        VStack(spacing: 0) {
            row("Signed in as", session.email ?? "Apple ID (email hidden)")
            Rectangle().fill(LK.Palette.hairline).frame(height: 1)
            row("Member since", profile.map {
                $0.createdAt.formatted(.dateTime.month(.wide).year())
            } ?? "—")
            if session.isCook {
                Rectangle().fill(LK.Palette.hairline).frame(height: 1)
                // Worth stating: the name above is the *person*, and a kitchen
                // can be called something else entirely. Without this line the
                // two look like the same field failing to update.
                row("Kitchen", "Managed in the Kitchen tab")
            }
        }
        .background(LK.Palette.surface,
                    in: RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.inkQuiet)
            Spacer(minLength: 12)
            Text(value)
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var signOut: some View {
        Button(role: .destructive) {
            showingSignOutConfirm = true
        } label: {
            Text("Sign out")
                .font(LK.Typography.ui(16, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LK.Palette.ink)
        .confirmationDialog("Sign out?", isPresented: $showingSignOutConfirm,
                            titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task { await session.signOut(); dismiss() }
            }
        } message: {
            Text("Your orders and messages stay on your account — signing back in brings them with you.")
        }
    }

    // MARK: - Not signed in

    private var anonymous: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You're browsing without an account")
                .font(LK.Typography.titleSecondary)
                .foregroundStyle(LK.Palette.ink)
            Text("That's fine for looking around. You'll need one to message a kitchen or place an order, and it takes one tap.")
                .font(LK.Typography.body)
                .foregroundStyle(LK.Palette.inkQuiet)
                .fixedSize(horizontal: false, vertical: true)
            AppleSignInButton(session: session) { Task { await load() } }
                .padding(.top, 4)
            // Not everyone has a usable Apple ID — a managed device, or someone
            // who declined. Without this there was no other way in, and
            // `UpgradeAccountView` sat unreachable in the tree.
            Button("Use an email instead") { showingEmailUpgrade = true }
                .font(LK.Typography.bodyEmphasis)
                .foregroundStyle(LK.Palette.action)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Work

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        profile = try? await profiles.myProfile()
        name = profile?.displayName ?? ""
        bio = profile?.bio ?? ""
        avatarURL = try? await profiles.avatarURL(for: profile?.avatarPath)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        error = ""
        do {
            var path: String?
            if let photoData { path = try await profiles.uploadAvatar(photoData) }
            try await profiles.saveProfile(name: name, avatarPath: path, bio: bio)
            photoData = nil
            photo = nil
            await load()
        } catch {
            self.error = UserFacingError.message(
                for: error, fallback: "Couldn't save that. Try again in a moment."
            )
        }
    }
}
