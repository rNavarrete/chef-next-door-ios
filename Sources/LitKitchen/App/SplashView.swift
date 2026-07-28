import SwiftUI

/// The first thing anyone sees.
///
/// Drawn in SwiftUI shapes rather than shipped as a raster. A PNG would need
/// @1x/@2x/@3x, would be fixed in one palette, and would bloat the bundle for
/// an image on screen for a second and a half. Vector geometry is crisp at any
/// size, adapts to light and dark, and costs nothing.
///
/// The character is a burger, stacked and steaming. Food rather than an icon:
/// the product is about someone cooking something right now, and a plate of
/// food says that faster than a symbol does.
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
                    LK.Palette.heat.opacity(0.28),
                    LK.Palette.heat.opacity(0.06),
                    .clear,
                ],
                center: .init(x: 0.5, y: 0.42),
                startRadius: 8,
                endRadius: 380
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                burgerCharacter
                    .frame(width: 190, height: 190)
                    .scaleEffect(landed ? 1 : 0.62)
                    .opacity(landed ? 1 : 0)

                VStack(spacing: 7) {
                    // Scales rather than wraps. "Lit Kitchen" was eleven
                    // characters and fit anywhere; "Chef Next Door" is fourteen
                    // at 38pt heavy, which wraps to "Chef Next / Door" on a
                    // narrow phone — under a fixed-height burger, so the whole
                    // composition shifts. One line, shrunk if it has to be.
                    Text("Chef Next Door")
                        .font(LK.Typography.display(38, weight: .heavy))
                        .foregroundStyle(LK.Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("Who's cooking right now")
                        .font(LK.Typography.body)
                        .foregroundStyle(LK.Palette.inkTertiary)
                }
                .opacity(landed ? 1 : 0)
                .offset(y: landed ? 0 : 10)
            }
        }
        .background(LK.Palette.ground.ignoresSafeArea())
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
        }
        // A blink is asymmetric: eyes are open almost all the time and shut for
        // about a tenth of a second. `repeatForever(autoreverses:)` gives the
        // opposite — an even toggle with no resting state, so the eyes spend as
        // long closed as open and the character reads as squinting. On a splash
        // that lives 1.6s you happened to catch it mid-close and it never
        // opened again.
        //
        // Driven from a task instead, so "closed" is an interval we choose
        // rather than half of a cycle. Lands just after the entrance spring
        // settles, and always finishes with the eyes open.
        .task {
            try? await Task.sleep(for: .seconds(0.72))
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.07)) { blink = true }
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(.easeInOut(duration: 0.10)) { blink = false }
                // Long enough that a second blink reads as a separate one
                // rather than a flutter.
                try? await Task.sleep(for: .seconds(1.6))
            }
        }
        // One element, one label. Without this VoiceOver reads a decorative
        // dumpling, two eyes and a mouth as four separate items.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chef Next Door. Who's cooking right now.")
    }

    /// The one line colour. Warm near-black rather than pure black — pure
    /// black on cream reads as clip art; this sits in the same family as the
    /// app's ink.
    private let ink = Color(hex: 0x2E2216)

    /// The burger, stacked.
    ///
    /// Same drawing language as everything else in this pass: one flat fill per
    /// part, one uniform ink line, no gradients. The parts are drawn back to
    /// front and overlap by a few points so the stack reads as *pressed
    /// together* rather than as five shapes resting on each other.
    ///
    /// The cheese is `heat` — the app's own marigold, and the one place in the
    /// character where a brand colour lands on something that is genuinely
    /// supposed to look hot.
    private var burgerCharacter: some View {
        // Proportions are fractions of the frame so the whole thing scales as
        // one object; nudging a layer means moving one number.
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let ink = self.ink
            // One weight everywhere. Mixed 6s and 7s read as a drawing that
            // could not decide, not as depth.
            let line: CGFloat = 7

            ZStack(alignment: .top) {
                // Back to front. Each layer covers the top of the one before,
                // so the visible band of every filling is the gap between its
                // own top and the next layer's — laid out here so each gets a
                // clear stripe instead of being buried:
                //
                //   bun 0…0.38 · cheese 0.38…0.50 · patty 0.50…0.60
                //   lettuce 0.60…0.66 (+ scallops) · bottom bun 0.66…0.90
                //
                // Every filling's top edge is hidden behind the layer above, so
                // its stroke is spent where nobody sees it. Three of those in a
                // narrow zone fused into one black band and swallowed the
                // cheese; the bands below are sized to absorb that.
                //
                // Fillings share one width and the buns share another, so their
                // side walls stack into a single silhouette edge. At five
                // different widths each wall was stroked separately and left
                // stray vertical stubs poking out of both sides.
                let bunW = w * 0.88
                // 0.92, not 0.96. The fillings should peek past the bun, not
                // shelf out of it — at 4% a side the overhang plus a 7pt stroke
                // made a hard square shoulder wider than the crown's widest
                // point, and the cheese looked like it belonged to a bigger
                // burger.
                let fillW = w * 0.92

                BottomBun()
                    .fill(Color(hex: 0xF0B96A))
                    .overlay { BottomBun().stroke(ink, lineWidth: line) }
                    .frame(width: bunW, height: h * 0.24)
                    .offset(y: h * 0.66)

                Lettuce()
                    .fill(Color(hex: 0x86BE5F))
                    .overlay { Lettuce().stroke(ink, lineWidth: line) }
                    .frame(width: fillW, height: h * 0.14)
                    .offset(y: h * 0.60)

                Capsule(style: .continuous)
                    .fill(Color(hex: 0x9A5B33))
                    .overlay { Capsule(style: .continuous).stroke(ink, lineWidth: line) }
                    .frame(width: fillW, height: h * 0.14)
                    .offset(y: h * 0.47)

                // `heat`, and drawn *over* the patty so the drips drape onto it.
                //
                // The slice's flat edge has to land at or below the patty's top.
                // At 0.44 against a patty starting at 0.50 there was an 11pt
                // band of bare background showing between and beside the drips,
                // and the cheese read as hovering with nothing under it.
                Cheese()
                    .fill(LK.Palette.heat)
                    .overlay { Cheese().stroke(ink, lineWidth: line) }
                    .frame(width: fillW, height: h * 0.26)
                    .offset(y: h * 0.35)

                TopBun()
                    .fill(Color(hex: 0xF5C57A))
                    .overlay { TopBun().stroke(ink, lineWidth: line) }
                    .overlay {
                        ZStack {
                            seed.offset(x: -w * 0.20, y: -h * 0.055)
                            // Higher than the other two: at -0.06 it landed dead centre
                            // between the eyes and read as a bindi rather than a seed.
                            seed.offset(x: w * 0.03, y: -h * 0.115)
                            seed.offset(x: w * 0.22, y: -h * 0.035)
                        }
                    }
                    // Offset is a fraction of the *whole* frame, but the bun it sits on is
                    // only 0.42 of that — so 0.10 was a quarter of the bun's height
                    // downward and pushed the mouth onto the crown's cut edge.
                    .overlay { face.offset(y: h * 0.02) }
                    .frame(width: bunW, height: h * 0.38)
            }
            // `alignment: .top`, and it matters more than it looks.
            //
            // `.offset` does not participate in layout, so this ZStack sizes
            // itself to its tallest *child* — the 0.38h crown — not to the
            // 0.90h stack the offsets actually draw. Without an alignment the
            // frame then centres that short box, pushing every layer down by
            // (h - 0.38h)/2 and spilling the bottom bun 40pt past the frame,
            // straight through the title underneath.
            .frame(width: w, height: h, alignment: .top)
            // Squash and stretch, anchored at the base — it settles like
            // something soft rather than scaling like a graphic.
            .scaleEffect(
                x: breathing ? 1.02 : 0.99,
                y: breathing ? 0.99 : 1.02,
                anchor: .bottom
            )
            .overlay(alignment: .top) { steam.offset(y: -h * 0.16) }
        }
    }

    private var seed: some View {
        Capsule()
            .fill(Color(hex: 0xFBEFD4))
            .frame(width: 13, height: 8)
            .rotationEffect(.degrees(-12))
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

/// The top bun: a dome on a flat base.
private struct TopBun: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h))
        p.addCurve(
            to: CGPoint(x: w, y: h),
            control1: CGPoint(x: -w * 0.02, y: -h * 0.33),
            control2: CGPoint(x: w * 1.02, y: -h * 0.33)
        )
        p.closeSubpath()
        return p
    }
}

/// The bottom bun: flat on top, rounded underneath. Shallower than the crown —
/// a burger whose halves match looks like a sandwich.
private struct BottomBun: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        // Controls at 1.33h, not 1.9h. A cubic's midpoint is
        // (p0 + 3c1 + 3c2 + p3) / 8, so 1.9 put the belly at 1.42× the rect —
        // the shape drew well outside its own frame and collided with the title
        // underneath it. 1.33 lands the curve exactly on h.
        p.addCurve(
            to: CGPoint(x: 0, y: 0),
            control1: CGPoint(x: w * 1.04, y: h * 1.33),
            control2: CGPoint(x: -w * 0.04, y: h * 1.33)
        )
        p.closeSubpath()
        return p
    }
}

/// Lettuce: straight along the top where it meets the patty, scalloped along
/// the bottom where it hangs out of the bun.
private struct Lettuce: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h * 0.45))

        // Five scallops back along the bottom.
        let count = 5
        let step = w / CGFloat(count)
        for i in 0..<count {
            let x = w - step * CGFloat(i)
            p.addQuadCurve(
                to: CGPoint(x: x - step, y: h * 0.45),
                control: CGPoint(x: x - step / 2, y: h * 1.25)
            )
        }
        p.closeSubpath()
        return p
    }
}

/// A cheese slice with two drips. Without them a yellow rectangle reads as
/// paper; the drips are the entire tell.
private struct Cheese: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h * 0.50))
        // Right drip, long.
        p.addQuadCurve(to: CGPoint(x: w * 0.70, y: h * 0.50),
                       control: CGPoint(x: w * 0.85, y: h * 1.30))
        p.addLine(to: CGPoint(x: w * 0.46, y: h * 0.50))
        // Left drip, shorter — matching drips look like a pennant.
        p.addQuadCurve(to: CGPoint(x: w * 0.22, y: h * 0.50),
                       control: CGPoint(x: w * 0.34, y: h * 1.05))
        p.addLine(to: CGPoint(x: 0, y: h * 0.50))
        p.closeSubpath()
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
