import CoreImage.CIFilterBuiltins
import SwiftUI

/// A cook's own link and QR code, for bringing their buyers with them.
///
/// The people this app needs are already selling on Facebook Marketplace, and
/// what they have there is not a listing — it is forty people who message them
/// when they post. There is no API that moves those people, and no API that
/// moves the listings either: Marketplace has no public per-seller endpoint,
/// and Messenger's is for Pages, not personal profiles. So the migration path
/// is not integration. It is giving a cook something to paste into the places
/// their buyers already are.
///
/// ## The limit, said out loud
///
/// `litkitchen://cook/<id>` opens for somebody who already has the app and does
/// nothing visible for somebody who does not. That makes this genuinely useful
/// in person — show the QR at a pickup, put it on a card in the bag — and only
/// half useful in a Facebook post, where most readers have never heard of us.
///
/// Fixing that needs a domain and a Universal Link, at which point the copy
/// here changes and nothing else does: every share ever generated came from
/// `DeepLink.kitchenURL`, so they all upgrade together.
struct ShareKitchenSheet: View {
    let cookID: UUID
    let displayName: String
    @Environment(\.dismiss) private var dismiss

    private var url: URL { DeepLink.kitchenURL(cookID: cookID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LK.Metrics.blockSpacing) {
                    Text("Anyone who scans this opens your kitchen — your menu, whether you're cooking, and a way to message you.")
                        .font(LK.Typography.body)
                        .foregroundStyle(LK.Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    qrCard

                    VStack(spacing: 10) {
                        ShareLink(item: url) {
                            Label("Share my kitchen", systemImage: "square.and.arrow.up")
                                .font(LK.Typography.navBarEmphasis)
                                .foregroundStyle(LK.Palette.inkOnAction)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(
                                    LK.Palette.action,
                                    in: RoundedRectangle(cornerRadius: LK.Metrics.radiusButton, style: .continuous)
                                )
                        }

                        Button {
                            UIPasteboard.general.string = url.absoluteString
                        } label: {
                            Text("Copy link")
                                .font(LK.Typography.navBarEmphasis)
                                .foregroundStyle(LK.Palette.action)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: LK.Metrics.radiusButton, style: .continuous)
                                        .strokeBorder(LK.Palette.action.opacity(0.35), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    // Stated rather than discovered. A cook who posts this to
                    // Facebook and hears nothing back deserves to know why
                    // before they conclude the app is broken.
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Works for people who have the app", systemImage: "info.circle")
                            .font(LK.Typography.bodyEmphasis)
                            .foregroundStyle(LK.Palette.ink)
                        Text("Right now this link opens Chef Next Door for anyone who already has it installed. It's best face to face — show the code at a pickup, or put it in the bag. A version that works for everyone is coming.")
                            .font(LK.Typography.meta)
                            .foregroundStyle(LK.Palette.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LK.Palette.chip, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusInner, style: .continuous))
                }
                .padding(LK.Metrics.screenPadding)
            }
            .background(LK.Palette.ground)
            .navigationTitle("Share your kitchen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// The code, on a card sized to be photographed off someone's screen.
    private var qrCard: some View {
        VStack(spacing: 12) {
            if let image = qr {
                Image(uiImage: image)
                    .interpolation(.none)          // keep the modules crisp
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Text(displayName)
                .font(LK.Typography.bodyEmphasis)
                .foregroundStyle(LK.Palette.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(LK.Palette.surface, in: RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LK.Metrics.radiusCard, style: .continuous)
                .strokeBorder(LK.Palette.hairline, lineWidth: 0.5)
        }
    }

    /// CoreImage, so no dependency and no network round trip — a cook standing
    /// at a farmers' market with one bar of signal still gets their code.
    ///
    /// Rendered at native size then scaled up 10×, because the generator emits
    /// roughly a 25pt image and letting SwiftUI resample that produces a blurry
    /// code that scanners refuse.
    private var qr: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        // Medium correction: survives a thumb over one corner, without the
        // density that makes a code hard to scan off a screen.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
