import AppKit
import CoreGraphics
import Foundation

// Avatars for the seeded kitchens.
//
//     swift Tools/MakeAvatars.swift <output-dir>
//
// There are no photographs of people in this repo and there should not be —
// inventing headshots for thirty-five cooks who do not exist would be a worse
// kind of fake than an obviously generated mark. So: initials on a flat ground,
// in the app's own palette, which reads as a deliberate placeholder rather than
// as a broken image.
//
// Each slug gets a stable colour derived from its own characters, so the same
// cook is the same colour on every regeneration, and adjacent cooks in the feed
// are very unlikely to collide.

let slugs: [(String, String)] = [
    ("chuy", "DC"),
    ("kim", "KS"),
    ("lupita", "LS"),
    ("beto", "BR"),
    ("priya", "PN"),
    ("ana", "AP"),
    ("marisol", "MT"),
    ("danny", "CD"),
    ("rosa", "RM"),
    ("yolanda", "YV"),
    ("mei", "ML"),
    ("armen", "AK"),
    ("nena", "NG"),
    ("tuan", "TP"),
    ("sofia", "SC"),
    ("ricardo", "RB"),
    ("grace", "GO"),
    ("hassan", "HA"),
    ("jasmine", "JW"),
    ("paolo", "PR"),
    ("fatima", "FZ"),
    ("diego", "DM"),
    ("linh", "LT"),
    ("carmen", "CD"),
    ("ben", "BS"),
    ("aiko", "AN"),
    ("miguel", "MA"),
    ("ruth", "RE"),
    ("javier", "JO"),
    ("hana", "HK"),
    ("oscar", "OV"),
    ("sunny", "SP"),
    ("delia", "DF"),
    ("marco", "MT"),
    ("estela", "ER"),
    ("marisav", "MV"),
    ("tranh", "TH"),
    ("kenji", "KS"),
    ("rocio", "RA"),
    ("nadia", "NF"),
    ("samo", "SO"),
    ("lorena", "LP"),
    ("devi", "DR"),
    ("bao", "BN"),
    ("elena", "EM"),
    ("ahmad", "AB"),
    ("kail", "KL"),
    ("gloria", "GE"),
    ("yusuf", "YD"),
    ("priscila", "PT"),
    ("ravi", "RK"),
    ("camila", "CS"),
    ("mateo", "MJ"),
    ("aisha", "AM"),
    ("hugo", "HC"),
    ("simone", "SW"),
    ("ivan", "IP"),
    ("luciaf", "LF"),
    ("omar", "OS"),
    ("bianca", "BR"),
    ("terrence", "TH"),
    ("jiwoo", "JC"),
    ("fernanda", "FL"),
    ("noor", "NH"),
    ("marisolq", "MQ"),
    ("davida", "DA"),
    ("rosalinda", "RG"),
    ("nina", "NB"),
    ("tomas", "TE"),
    ("kalani", "KM"),
    ("anasofia", "AD"),
    ("hyunj", "HJ"),
    ("beatriz", "BN"),
    ("efrain", "EV"),
    ("malia", "MK"),
    ("ines", "IR"),
    ("zaid", "ZA"),
    ("paloma", "PS"),
    ("tenzin", "TD"),
    ("consuelo", "CB"),
    ("andresm", "AM"),
    ("sunisa", "SP"),
    ("georgi", "GV"),
    ("rosaelena", "RT"),
    ("weic", "WC"),
    ("farah", "FQ"),
    ("julio", "JE"),
    ("amara", "AO"),
    ("lidia", "LH"),
    ("nasrin", "NK"),
]

// Drawn from the app's palette — marigolds, terracottas, herb greens. Muted
// enough that a grid of them does not read as a colour test card.
let grounds: [(CGFloat, CGFloat, CGFloat)] = [
    (0xE8, 0x99, 0x1E), (0xC9, 0x5A, 0x2C), (0x8A, 0x9A, 0x4B), (0xB4, 0x5A, 0x4A),
    (0x6E, 0x8B, 0x74), (0xD4, 0x8C, 0x3A), (0xA5, 0x6A, 0x54), (0x7C, 0x8C, 0x6B),
    (0xCB, 0x7A, 0x35), (0x9A, 0x5B, 0x33), (0x5F, 0x7A, 0x6A), (0xD9, 0xA0, 0x4E),
]

let size: CGFloat = 512
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(
    atPath: outDir, withIntermediateDirectories: true)

for (slug, initials) in slugs {
    // Stable per slug: same cook, same colour, every run.
    let hash = slug.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
    let (r, g, b) = grounds[hash % grounds.count]

    guard let ctx = CGContext(
        data: nil, width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { continue }

    ctx.setFillColor(CGColor(red: r/255, green: g/255, blue: b/255, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

    // A soft highlight, so a circle crop does not look like a flat swatch.
    ctx.saveGState()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.fillEllipse(in: CGRect(x: -size * 0.2, y: size * 0.35,
                               width: size * 1.1, height: size * 1.1))
    ctx.restoreGState()

    let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsctx

    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size * 0.34, weight: .semibold),
        .foregroundColor: NSColor(white: 1, alpha: 0.94),
        .paragraphStyle: style,
    ]
    let text = initials as NSString
    let bounds = text.boundingRect(
        with: CGSize(width: size, height: size),
        options: .usesLineFragmentOrigin, attributes: attrs)
    text.draw(in: CGRect(x: 0, y: (size - bounds.height) / 2,
                         width: size, height: bounds.height),
              withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()

    guard let image = ctx.makeImage() else { continue }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(
        using: .jpeg, properties: [.compressionFactor: 0.9]) else { continue }
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(slug).jpg"))
}

print("wrote \(slugs.count) avatars to \(outDir)")
