import SwiftUI

/// Where a cook writes their story.
///
/// `cooks.bio` has existed since migration 002 and has never had an editor —
/// the column, the grant and the Swift property were all in place and nothing
/// could write it. This is that missing screen.
///
/// The prompts are deliberate. "Tell buyers about yourself" produces an empty
/// box and an empty box produces nothing; naming the things worth saying —
/// who taught you, what you make, why — is what gets a story written at all.
struct CookStorySheet: View {
    let cookID: UUID
    /// Pre-filled with whatever is already saved.
    @State var story: String

    var onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Matches the `cooks_bio_length` CHECK in migration 058. The client should
    /// refuse before the server has to.
    private let limit = 2000

    private var trimmed: String {
        story.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Why do you cook?")
                        .font(LK.Typography.titleSecondary)
                        .foregroundStyle(LK.Palette.ink)

                    Text("Buyers can see your permit and your prices. This is the only place they can meet *you* — who taught you to cook, the recipe you're proudest of, what feeding this neighbourhood means to you.")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: $story)
                        .font(LK.Typography.fieldValue)
                        .foregroundStyle(LK.Palette.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 220)
                        .padding(10)
                        .background(
                            LK.Palette.surface,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(focused ? LK.Palette.action : LK.Palette.hairline,
                                              lineWidth: focused ? 2 : 1)
                        }
                        .overlay(alignment: .topLeading) {
                            // TextEditor has no placeholder of its own.
                            if story.isEmpty {
                                Text("My mother sold tamales on this same street…")
                                    .font(LK.Typography.fieldValue)
                                    .foregroundStyle(LK.Palette.inkTertiary.opacity(0.6))
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                        }
                        .focused($focused)

                    HStack {
                        // Only once it is close enough to matter. A counter
                        // from character zero reads as a limit to respect
                        // rather than as room to write.
                        if trimmed.count > limit - 300 {
                            Text("\(limit - trimmed.count) left")
                                .font(LK.Typography.ui(12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(
                                    trimmed.count > limit ? LK.Palette.ink : LK.Palette.inkTertiary
                                )
                        }
                        Spacer()
                        Text("Shown on your profile")
                            .font(LK.Typography.ui(12))
                            .foregroundStyle(LK.Palette.inkTertiary)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(LK.Typography.meta)
                            .foregroundStyle(LK.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(LK.Metrics.screenPadding)
            }
            .background(LK.Palette.ground)
            .navigationTitle("Your story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(isSaving || trimmed.count > limit)
                }
            }
        }
        .tint(LK.Palette.action)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            // Empty clears it rather than storing "". A cook removing their
            // story should leave no trace, not an empty section.
            try await CookProfileWriter().setStory(trimmed.isEmpty ? nil : trimmed, for: cookID)
            onSaved(trimmed)
            dismiss()
        } catch {
            errorMessage = UserFacingError.message(
                for: error, fallback: "Couldn't save your story. Check your connection and try again."
            )
        }
    }
}
