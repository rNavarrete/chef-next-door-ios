import AppKit
import CoreGraphics
import Foundation

// Lit Kitchen app icon.
//
//     swift Tools/MakeIcon.swift Sources/LitKitchen/Assets.xcassets/AppIcon.appiconset/icon-1024.png
//
// The same burger as the splash (`SplashView.swift`), recut for the size it is
// actually seen at. An icon is a ~40–60pt object, so everything that survives on
// a 190pt splash but not on a home screen is removed or fattened:
//
//   · three sesame seeds became two, and larger
//   · five lettuce scallops became four
//   · the eye highlights are gone — at 60pt they close up into the pupil
//
// Ground is `heat`. The icon is the app's own light, on — and it is the one
// place a marigold *background* does not break the rule, because there is no
// interface on it for the colour to compete with.

let S: CGFloat = 1024

// Deeper and more orange than `heat` itself. The ground cannot *be* marigold
// here: the cheese is marigold, and at the burger's edge the two merged into
// one field with the slice disappearing into the background. Pushing the ground
// toward orange keeps it unmistakably the brand colour while letting the
// yellow of the cheese separate from it.
let heat      = CGColor(red: 0xE8/255, green: 0x99/255, blue: 0x1E/255, alpha: 1)
let heatDeep  = CGColor(red: 0xC9/255, green: 0x7A/255, blue: 0x0C/255, alpha: 1)
let bunTop    = CGColor(red: 0xF5/255, green: 0xC5/255, blue: 0x7A/255, alpha: 1)
let bunBase   = CGColor(red: 0xF0/255, green: 0xB9/255, blue: 0x6A/255, alpha: 1)
let cheese    = CGColor(red: 0xF7/255, green: 0xC0/255, blue: 0x2E/255, alpha: 1)
let patty     = CGColor(red: 0x9A/255, green: 0x5B/255, blue: 0x33/255, alpha: 1)
let lettuce   = CGColor(red: 0x86/255, green: 0xBE/255, blue: 0x5F/255, alpha: 1)
let seedColor = CGColor(red: 0xFB/255, green: 0xEF/255, blue: 0xD4/255, alpha: 1)
let ink       = CGColor(red: 0x2E/255, green: 0x22/255, blue: 0x16/255, alpha: 1)
let blush     = CGColor(red: 0xFF/255, green: 0x9E/255, blue: 0x8A/255, alpha: 1)

guard let ctx = CGContext(
    data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue   // opaque: the store requires it
) else { fatalError("context") }

// Flip to a top-left origin so the geometry reads the same as the SwiftUI shapes.
ctx.translateBy(x: 0, y: S)
ctx.scaleBy(x: 1, y: -1)

// MARK: Ground
let sky = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                     colors: [heat, heatDeep] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: S), options: [])

// MARK: Layout
// Fractions mirror the splash so the two stay the same animal:
//   bun 0…0.38 · cheese 0.38…0.47 · patty 0.47…0.60
//   lettuce 0.60…0.66 (+ scallops) · bottom bun 0.66…0.90
//
// Fillings share one width and buns share another, so their side walls stack
// into a single silhouette edge instead of a row of stray stubs.
let bw = S * 0.78, bh = S * 0.64
let ox = (S - bw) / 2, oy = S * 0.18
let bunW = bw * 0.88, fillW = bw * 0.92
let line = S * 0.034

func bx(_ f: CGFloat) -> CGFloat { ox + bw * f }
func by(_ f: CGFloat) -> CGFloat { oy + bh * f }

/// A layer's rect, centred horizontally on the burger.
func band(width: CGFloat, top: CGFloat, height: CGFloat) -> CGRect {
    CGRect(x: ox + (bw - width) / 2, y: by(top), width: width, height: bh * height)
}

func stroke(_ path: CGPath) {
    ctx.addPath(path); ctx.setStrokeColor(ink)
    ctx.setLineWidth(line); ctx.setLineJoin(.round); ctx.setLineCap(.round)
    ctx.strokePath()
}
func fill(_ path: CGPath, _ color: CGColor) {
    ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath()
}

// MARK: Bottom bun — drawn first; every layer above overlaps it
let bbRect = band(width: bunW, top: 0.66, height: 0.24)
let bottomBun = CGMutablePath()
bottomBun.move(to: CGPoint(x: bbRect.minX, y: bbRect.minY))
bottomBun.addLine(to: CGPoint(x: bbRect.maxX, y: bbRect.minY))
// Controls at 1.33× the rect: a cubic's midpoint is (p0 + 3c1 + 3c2 + p3) / 8,
// so this lands the belly exactly on the rect's bottom edge.
bottomBun.addCurve(
    to: CGPoint(x: bbRect.minX, y: bbRect.minY),
    control1: CGPoint(x: bbRect.maxX + bbRect.width * 0.04, y: bbRect.minY + bbRect.height * 1.33),
    control2: CGPoint(x: bbRect.minX - bbRect.width * 0.04, y: bbRect.minY + bbRect.height * 1.33)
)
bottomBun.closeSubpath()
fill(bottomBun, bunBase); stroke(bottomBun)

// MARK: Lettuce — four scallops, not five
let ltRect = band(width: fillW, top: 0.60, height: 0.14)
let lettucePath = CGMutablePath()
lettucePath.move(to: CGPoint(x: ltRect.minX, y: ltRect.minY))
lettucePath.addLine(to: CGPoint(x: ltRect.maxX, y: ltRect.minY))
lettucePath.addLine(to: CGPoint(x: ltRect.maxX, y: ltRect.minY + ltRect.height * 0.45))
let scallops = 4
let sStep = ltRect.width / CGFloat(scallops)
for i in 0..<scallops {
    let x = ltRect.maxX - sStep * CGFloat(i)
    lettucePath.addQuadCurve(
        to: CGPoint(x: x - sStep, y: ltRect.minY + ltRect.height * 0.45),
        control: CGPoint(x: x - sStep / 2, y: ltRect.minY + ltRect.height * 1.25)
    )
}
lettucePath.closeSubpath()
fill(lettucePath, lettuce); stroke(lettucePath)

// MARK: Patty
let ptRect = band(width: fillW, top: 0.47, height: 0.14)
let pattyPath = CGPath(roundedRect: ptRect,
                       cornerWidth: ptRect.height / 2, cornerHeight: ptRect.height / 2,
                       transform: nil)
fill(pattyPath, patty); stroke(pattyPath)

// MARK: Cheese — drawn over the patty so the drips drape onto it
//
// The slice's flat edge must land at or below the patty's top. Abutting leaves
// a band of bare background showing between the drips, and the cheese reads as
// hovering with nothing under it.
let chRect = band(width: fillW, top: 0.35, height: 0.26)
let flat = chRect.minY + chRect.height * 0.50
let cheesePath = CGMutablePath()
cheesePath.move(to: CGPoint(x: chRect.minX, y: chRect.minY))
cheesePath.addLine(to: CGPoint(x: chRect.maxX, y: chRect.minY))
cheesePath.addLine(to: CGPoint(x: chRect.maxX, y: flat))
cheesePath.addQuadCurve(to: CGPoint(x: chRect.minX + chRect.width * 0.70, y: flat),
                        control: CGPoint(x: chRect.minX + chRect.width * 0.85,
                                         y: chRect.minY + chRect.height * 1.30))
cheesePath.addLine(to: CGPoint(x: chRect.minX + chRect.width * 0.46, y: flat))
// Shorter than the right one — matching drips read as a pennant.
cheesePath.addQuadCurve(to: CGPoint(x: chRect.minX + chRect.width * 0.22, y: flat),
                        control: CGPoint(x: chRect.minX + chRect.width * 0.34,
                                         y: chRect.minY + chRect.height * 1.05))
cheesePath.addLine(to: CGPoint(x: chRect.minX, y: flat))
cheesePath.closeSubpath()
fill(cheesePath, cheese); stroke(cheesePath)

// MARK: Top bun
let tbRect = band(width: bunW, top: 0.00, height: 0.38)
let topBun = CGMutablePath()
topBun.move(to: CGPoint(x: tbRect.minX, y: tbRect.maxY))
topBun.addCurve(
    to: CGPoint(x: tbRect.maxX, y: tbRect.maxY),
    control1: CGPoint(x: tbRect.minX - tbRect.width * 0.02, y: tbRect.minY - tbRect.height * 0.33),
    control2: CGPoint(x: tbRect.maxX + tbRect.width * 0.02, y: tbRect.minY - tbRect.height * 0.33)
)
topBun.closeSubpath()
fill(topBun, bunTop); stroke(topBun)

// MARK: Sesame — two, and fat. Three at this size crowd the brow.
for (dx, dy, rot) in [(-0.17, 0.09, -14.0), (0.16, 0.06, 10.0)] as [(CGFloat, CGFloat, Double)] {
    ctx.saveGState()
    ctx.translateBy(x: bx(0.5) + bw * dx, y: by(dy))
    ctx.rotate(by: CGFloat(rot) * .pi / 180)
    let r = CGRect(x: -S * 0.030, y: -S * 0.011, width: S * 0.060, height: S * 0.022)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: S * 0.011, cornerHeight: S * 0.011,
                       transform: nil))
    ctx.setFillColor(seedColor); ctx.fillPath()
    ctx.restoreGState()
}

// MARK: Face
let faceY = by(0.21)
let eyeDX = bw * 0.145
let eyeW = S * 0.058, eyeH = S * 0.090

for sign in [-1.0, 1.0] as [CGFloat] {
    let cx = bx(0.5) + sign * eyeDX
    let r = CGRect(x: cx - eyeW / 2, y: faceY - eyeH / 2, width: eyeW, height: eyeH)
    fill(CGPath(roundedRect: r, cornerWidth: eyeW / 2, cornerHeight: eyeW / 2, transform: nil), ink)
}

// Blush, flat and hard-edged. A soft edge at this size reads as a compression
// artefact rather than as a cheek.
for sign in [-1.0, 1.0] as [CGFloat] {
    let cx = bx(0.5) + sign * (eyeDX + bw * 0.105)
    let r = CGRect(x: cx - S * 0.042, y: faceY + S * 0.010, width: S * 0.084, height: S * 0.044)
    ctx.addEllipse(in: r); ctx.setFillColor(blush); ctx.fillPath()
}

let mouth = CGMutablePath()
let mw = S * 0.080
mouth.move(to: CGPoint(x: bx(0.5) - mw / 2, y: faceY + S * 0.054))
mouth.addQuadCurve(to: CGPoint(x: bx(0.5) + mw / 2, y: faceY + S * 0.054),
                   control: CGPoint(x: bx(0.5), y: faceY + S * 0.110))
ctx.addPath(mouth)
ctx.setStrokeColor(ink); ctx.setLineWidth(S * 0.021); ctx.setLineCap(.round)
ctx.strokePath()

// MARK: Write
guard let image = ctx.makeImage() else { fatalError("image") }
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try data.write(to: out)
print("wrote \(out.path)")
