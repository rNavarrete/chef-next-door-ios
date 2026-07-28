import SwiftUI

/// A round avatar that degrades to initials.
///
/// Two kinds of source land here and they are not interchangeable. A cook's
/// avatar is a plain URL in the public `kitchen-photos` bucket; a buyer's is a
/// *path* in the private `avatars` bucket that has to be signed before it can
/// be fetched. `resolve` is where that split is handled — pass it the closure
/// that knows how to sign, and pass `isSigned: false` for a cook's URL.
///
/// Initials rather than a grey silhouette: a buyer with no photo is the normal
/// case, not a missing one, and a name the cook can read is more use than a
/// generic head.
struct ProfileAvatar: View {
    let name: String
    let source: String?
    /// True when `source` is a private storage path needing a signed URL.
    var needsSigning: Bool = false
    var size: CGFloat = 44
    /// Nil is a circle — the inbox's shape, and the default everywhere a person
    /// appears in a list. A radius squares it off for the Polaroid on a cook's
    /// profile, where the frame around it supplies the character instead.
    var cornerRadius: CGFloat?
    /// Not `@Sendable`: this view is `@MainActor`, so the closure already runs
    /// there, and requiring Sendable only forced callers to smuggle a
    /// `@MainActor` repository across an isolation boundary it never crosses.
    var sign: ((String) async -> URL?)?

    @State private var resolved: URL?

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    /// One definition, so the fill, the clip and the border can never disagree
    /// about what shape this is.
    private var shape: AnyShape {
        if let cornerRadius {
            AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            AnyShape(Circle())
        }
    }

    var body: some View {
        ZStack {
            shape.fill(LK.Palette.chip)

            if let resolved {
                AsyncImage(url: resolved) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill).transition(.opacity)
                    } else {
                        initialsLabel
                    }
                }
            } else {
                initialsLabel
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay { shape.stroke(LK.Palette.hairline, lineWidth: 1) }
        .task(id: source) { await resolve() }
    }

    private var initialsLabel: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(LK.Palette.inkQuiet)
    }

    private func resolve() async {
        guard let source, !source.isEmpty else { resolved = nil; return }
        if needsSigning {
            resolved = await sign?(source)
        } else {
            resolved = URL(string: source)
        }
    }
}
