import SwiftUI

/// Leaving a review, once the cook has marked the order picked up.
///
/// Rating is required, words are not. Most people will not write a sentence
/// about a bag of tamales, and a form that insists on one mostly collects
/// nothing at all.
struct ReviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let conversationID: UUID
    let cookID: UUID
    let cookName: String
    var onSaved: () -> Void = {}

    @State private var rating = 0
    @State private var body_ = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let trust = TrustRepository()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("How was it?")
                        .font(LK.Typography.titleSecondary)
                        .foregroundStyle(LK.Palette.ink)

                    stars

                    GroupedCard {
                        // No autocorrect, same as the menu builder: this field
                        // will carry dish names in two languages, and iOS
                        // cheerfully turns "pupusa revuelta" into English.
                        TextField("Anything you'd tell a neighbor? (optional)",
                                  text: $body_, axis: .vertical)
                            .font(LK.Typography.body)
                            .lineLimit(3...6)
                            .autocorrectionDisabled()
                            .padding(14)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(LK.Typography.meta)
                            .foregroundStyle(LK.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Your review is public and shows on \(cookName)'s kitchen page. Only people who ordered and picked up can leave one.")
                        .font(LK.Typography.meta)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(LK.Metrics.screenPadding)
            }
            .background(LK.Palette.ground)
            .navigationTitle("Review \(cookName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { save() }
                        .fontWeight(.semibold)
                        .disabled(rating == 0 || isSaving)
                }
            }
        }
        .tint(LK.Palette.action)
    }

    private var stars: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    rating = value
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .font(LK.Typography.screenTitle)
                        // Amber is the lamp's colour and marks heat, never
                        // affordance — but a star that isn't amber reads as
                        // broken. This is the one deliberate exception, and it
                        // is not a control that changes the cook's state.
                        .foregroundStyle(value <= rating ? LK.Palette.heat : LK.Palette.inkTertiary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                .accessibilityAddTraits(value == rating ? [.isSelected] : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await trust.leaveReview(
                    conversationID: conversationID, cookID: cookID, rating: rating, body: body_
                )
                onSaved()
                dismiss()
            } catch {
                errorMessage = "Couldn't post that review. You can only review a pickup you completed."
            }
        }
    }
}
