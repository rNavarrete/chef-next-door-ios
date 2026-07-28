import SwiftUI

/// The first thing anyone sees.
///
/// Drawn in SwiftUI shapes rather than shipped as a raster. A PNG would need
/// @1x/@2x/@3x, would be fixed in one palette, and would bloat the bundle for
/// an image on screen for a second and a half. Vector geometry is crisp at any
/// size, adapts to light and dark, and costs nothing.
///
/// The character is a dumpling, sitting in the warm light of a kitchen with
/// steam coming off it. Food rather than an icon: the product is about someone
/// cooking something right now, and a plate of food says that faster than a
/// symbol does.
struct SplashView: View {
    /// Drives the whole entrance. One value so the parts can't drift apart.
    @State private var landed = false
    @State private var breathing = false
    @State private var blink = false
    @State private var steamRising = false

    var body: some View {
        ZStack {
            // A warm hearth glow, not flat paper. Same amber the lamps use.
            RadialGradient(
                colors: [
                    LK.Palette.lamp.opacity(0.28),
                    LK.Palette.lamp.opacity(0.06),
                    .clear,
                ],
                center: .init(x: 0.5, y: 0.42),
                startRadius: 8,
                endRadius: 380
            )
            .ignoresSafeArea()

            VStack(spacing: 26) {
                dumplingCharacter
                    .frame(width: 190, height: 190)
                    .scaleEffect(landed ? 1 : 0.62)
                    .opacity(landed ? 1 : 0)

                VStack(spacing: 7) {
                    Text("Lit Kitchen")
                        .font(LK.Typography.display(38, weight: .heavy))
                        .foregroundStyle(LK.Palette.ink)

                    Text("Who's cooking right now")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(LK.Palette.inkTertiary)
                }
                .opacity(landed ? 1 : 0)
                .offset(y: landed ? 0 : 10)
            }
        }
        .background(LK.Palette.paper.ignoresSafeArea())
        .onAppear {
            // Slight overshoot on the way in — the character should feel like
            // it hops into place, not like it fades up.
            withAnimation(.spring(response: 0.62, dampingFraction: 0.58)) {
                landed = true
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                breathing = true
            }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: false)) {
                steamRising = true
            }
            // Offset from the breathing so the two never sync into a pulse.
            withAnimation(.easeInOut(duration: 0.16).delay(1.0).repeatForever(autoreverses: true)) {
                blink = true
            }
        }
        // One element, one label. Without this VoiceOver reads a decorative
        // dumpling, two eyes and a mouth as four separate items.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lit Kitchen. Who's cooking right now.")
    }

    /// The one line colour. Warm near-black rather than pure black — pure
    /// black on cream reads as clip art; this sits in the same family as the
    /// app's ink.
    private let ink = Color(hex: 0x2E2216)

    private var dumplingCharacter: some View {
        ZStack {
            steam
                .offset(y: -76)

            ZStack {
                // Flat, not a gradient. The whole look depends on the fill
                // being one colour and the line carrying all the structure —
                // a gradient under a heavy outline reads as a 3D render with
                // a border drawn on it.
                Dumpling()
                    .fill(Color(hex: 0xFBEFD4))

                // The line. Uniform weight, near-black, round joins, and
                // `strokeBorder` so all 9pt sit *inside* the frame — a centred
                // stroke this heavy would clip against the edges.
                Dumpling()
                    .strokeBorder(ink, style: StrokeStyle(lineWidth: 9, lineJoin: .round))

                // The crimp, in the same ink at a deliberately lighter weight.
                // Equal weight would flatten the drawing: the silhouette has to
                // out-rank the interior detail or the shape stops reading.
                Pleats()
                    .stroke(ink, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

                face.offset(y: 30)
            }
            // Squash and stretch, anchored at the base — it settles like
            // something soft rather than scaling like a graphic.
            .scaleEffect(
                x: breathing ? 1.02 : 0.99,
                y: breathing ? 0.99 : 1.02,
                anchor: .bottom
            )
        }
    }

    /// Two wisps on different phases, so it never reads as a single pulsing
    /// blob. Steam is the only thing here asserting the food is hot.
    private var steam: some View {
        HStack(spacing: 20) {
            wisp(delay: 0)
            wisp(delay: 0.5)
            wisp(delay: 1.0)
        }
    }

    private func wisp(delay: Double) -> some View {
        // A stroked curl in the same ink, so the steam belongs to the drawing
        // rather than sitting behind it as a soft gradient.
        SteamCurl()
            .stroke(ink.opacity(0.55), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .frame(width: 14, height: 26)
            .scaleEffect(y: steamRising ? 1.35 : 0.7, anchor: .bottom)
            .opacity(steamRising ? 0 : 0.9)
            .offset(y: steamRising ? -18 : 6)
            .animation(
                .easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(delay),
                value: steamRising
            )
    }

    private var face: some View {
        VStack(spacing: 9) {
            HStack(spacing: 32) {
                eye
                eye
            }

            // Small mouth, low contrast, well under the eyes. Kawaii faces put
            // almost all their weight in the eyes; a mouth that competes makes
            // the character look startled.
            MouthCurve()
                .stroke(ink, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 22, height: 10)
        }
        .overlay {
            // Blush. The one flourish that does the most work — without it the
            // face reads as a logo with eyes.
            HStack(spacing: 66) {
                blush
                blush
            }
            .offset(y: 9)
        }
    }

    private var eye: some View {
        Capsule()
            .fill(ink)
            // Blinking is the eye getting *shorter*, which is what a blink is.
            .frame(width: 18, height: blink ? 4 : 23)
            .overlay(alignment: .topTrailing) {
                // The highlight is what separates "cute" from "staring". Hidden
                // mid-blink, or it floats over a closed eye.
                Circle()
                    .fill(.white.opacity(blink ? 0 : 0.95))
                    .frame(width: 6, height: 6)
                    .offset(x: -3, y: 4)
            }
    }

    private var blush: some View {
        // Flat and hard-edged. A blurred blush is an airbrush; this style
        // wants a shape.
        Ellipse()
            .fill(Color(hex: 0xFF9E8A))
            .frame(width: 20, height: 12)
    }
}

/// A shallow smile. A quadratic rather than an arc so the corners lift slightly
/// instead of curling.
private struct MouthCurve: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.7)
        )
        return p
    }
}

/// A jiaozi silhouette: a fat crescent belly with a crimped ridge along the
/// top. Wider than tall, because a dumpling that stands upright reads as an egg.
private struct Dumpling: Shape, InsettableShape {
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let w = r.width, h = r.height
        var p = Path()

        // Left tip, then the ridge across the top.
        p.move(to: CGPoint(x: r.minX + w * 0.10, y: r.minY + h * 0.42))
        p.addCurve(
            to: CGPoint(x: r.minX + w * 0.90, y: r.minY + h * 0.42),
            control1: CGPoint(x: r.minX + w * 0.26, y: r.minY + h * 0.12),
            control2: CGPoint(x: r.minX + w * 0.74, y: r.minY + h * 0.12)
        )
        // Right tip down and around the belly — deep and round, which is what
        // makes it read as full rather than as a pasty.
        p.addCurve(
            to: CGPoint(x: r.minX + w * 0.10, y: r.minY + h * 0.42),
            control1: CGPoint(x: r.minX + w * 1.02, y: r.minY + h * 1.02),
            control2: CGPoint(x: r.minX + w * -0.02, y: r.minY + h * 1.02)
        )
        p.closeSubpath()
        return p
    }
}

/// The crimp. Five folds along the top ridge, each a small arc rising from it —
/// the detail that separates a dumpling from a bun.
private struct Pleats: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        let count = 5
        // Spread across the middle of the ridge, leaving the tips clean.
        let startX = w * 0.20, endX = w * 0.80
        let step = (endX - startX) / CGFloat(count)

        for i in 0..<count {
            let x = startX + step * CGFloat(i)
            // The ridge sags toward the tips, so each fold has to start lower
            // as it moves outward or the crimp floats off the dough.
            let t = abs((x + step / 2) - w * 0.5) / (w * 0.3)
            let baseY = h * 0.30 + (t * t) * h * 0.075

            p.move(to: CGPoint(x: x, y: baseY + h * 0.055))
            p.addQuadCurve(
                to: CGPoint(x: x + step, y: baseY + h * 0.055),
                control: CGPoint(x: x + step / 2, y: baseY - h * 0.045)
            )
        }
        return p
    }
}


/// A single S-curl of steam. Two opposed quadratics — a straight line reads as
/// a tally mark, and a full spiral reads as smoke.
private struct SteamCurl: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.5, y: h))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.5),
            control: CGPoint(x: w * 1.1, y: h * 0.76)
        )
        p.addQuadCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control: CGPoint(x: w * -0.1, y: h * 0.24)
        )
        return p
    }
}
