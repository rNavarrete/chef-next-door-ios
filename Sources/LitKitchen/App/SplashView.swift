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
                chefIllustration
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

    /// The chef, as artwork rather than as paths.
    ///
    /// Drawn by hand and dropped in as an asset. An earlier attempt rebuilt this
    /// illustration in SwiftUI `Shape`s and it did not survive the translation —
    /// flowing hair, a running stride and a lidded pot are not things Bézier
    /// code writes well, and the result read as a pile of capsules.
    ///
    /// The source PNG sat on a 250/250/250 page. Keying that out by colour ate
    /// her hat and jacket, which are also white; the background is removed by
    /// flood-filling inward from the border instead, so only the page goes and
    /// anything enclosed by her outline stays.
    ///
    /// Blink and steam are gone with the shapes. A flat image still lands,
    /// breathes and scales, which is all a 1.6-second splash needs.
    private var chefIllustration: some View {
        Image("ChefRunning")
            .resizable()
            .scaledToFit()
            .scaleEffect(
                x: breathing ? 1.02 : 0.99,
                y: breathing ? 0.99 : 1.02,
                anchor: .bottom
            )
    }

    /// The chef.
    ///
    /// Same drawing language as before — one flat fill per part, one uniform
    /// ink line, no gradients — but the subject changed with the name. A burger
    /// belonged to "Lit Kitchen", which was about food. "Chef Next Door" is
    /// about a person, and a character with a face carries a name about people
    /// in a way a sandwich cannot.
    ///
    /// The neckerchief is `heat`, the app's marigold. It inherits the role the
    /// cheese used to play: the single place a brand colour lands on the
    /// character, small enough to read as an accent rather than as branding.
    private var chefCharacter: some View {
        // Fractions of the frame, so the whole thing scales as one object and
        // nudging a part means moving one number.
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let ink = self.ink
            // One weight everywhere. Mixed 6s and 7s read as a drawing that
            // could not decide, not as depth.
            let line: CGFloat = 7

            ZStack(alignment: .top) {
                // Back to front, each part overlapping the one before by a few
                // points so it reads as one drawing rather than stacked pieces:
                //
                //   toque puff 0…0.34 · band 0.30…0.42
                //   face 0.38…0.86 · collar 0.80…0.95

                // No collar. An earlier pass had a marigold neckerchief under the
                // chin; it hung like a bib, and a yellow shape below a round tan
                // head made the whole character read as a bee. Sanrio faces are
                // a head and one accessory — the toque is the accessory, and
                // anything else competes with it.

                // The face. A circle slightly wider than tall — a true circle
                // reads as a ball, and the squash is most of what makes it a
                // face.
                Ellipse()
                    .fill(Color(hex: 0xF5C57A))
                    .overlay { Ellipse().stroke(ink, lineWidth: line) }
                    .frame(width: w * 0.76, height: h * 0.46)
                    .offset(y: h * 0.38)
                    .overlay {
                        face.offset(y: h * 0.36)
                    }

                // The puff. Three lobes rather than one dome — one dome is a
                // beanie, and the lobes are the whole reason a toque reads as a
                // chef's hat at this size.
                ToquePuff()
                    .fill(Color(hex: 0xFBF6EC))
                    .overlay { ToquePuff().stroke(ink, lineWidth: line) }
                    .frame(width: w * 0.78, height: h * 0.34)
                // Toque band, in `heat`. This is where the brand colour lives
                // now — one stripe, structural rather than decorative, doing the
                // job the cheese did on the burger.
                //
                // Drawn AFTER the puff so it covers where the three lobes meet
                // it. With the puff on top, each lobe's bottom stroke crossed
                // the band as a vertical seam and the hat looked cracked.
                RoundedRectangle(cornerRadius: h * 0.03, style: .continuous)
                    .fill(LK.Palette.heat)
                    .overlay {
                        RoundedRectangle(cornerRadius: h * 0.03, style: .continuous)
                            .stroke(ink, lineWidth: line)
                    }
                    .frame(width: w * 0.72, height: h * 0.11)
                    .offset(y: h * 0.30)

            }
            .frame(width: w, height: h, alignment: .top)
            // Squash and stretch, anchored at the base — it settles like
            // something soft rather than scaling like a graphic.
            .scaleEffect(
                x: breathing ? 1.02 : 0.99,
                y: breathing ? 0.99 : 1.02,
                anchor: .bottom
            )
            // Steam still rises, but from beside the hat rather than out of
            // the top of a bun. A chef is the one thing on screen that is
            // actually cooking.
            .overlay(alignment: .top) {
                steam.offset(y: -h * 0.10)
            }
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

/// The bottom bun: flat on top, rounded underneath. Shallower than the crown —
/// a burger whose halves match looks like a sandwich.

/// Lettuce: straight along the top where it meets the patty, scalloped along
/// the bottom where it hangs out of the bun.

/// A cheese slice with two drips. Without them a yellow rectangle reads as
/// paper; the drips are the entire tell.

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

/// The puffy crown of a chef's toque: three lobes across the top.
///
/// One dome would be a beanie. The lobes are what make it read as a toque at
/// 190pt, and they are why this is a Shape rather than three overlapping
/// circles — overlapping circles leave seams where the ink line crosses itself.
private struct ToquePuff: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // Sit the lobes on a baseline a little above the bottom so the band
        // below can overlap without a gap showing between them.
        let base = rect.minY + h * 0.92

        p.move(to: CGPoint(x: rect.minX + w * 0.06, y: base))

        // Left lobe. Controls at 1.35x the lobe height: a cubic's midpoint is
        // (p0 + 3c1 + 3c2 + p3) / 8, so this lands the crown on the rect's top
        // edge instead of overshooting it — the same arithmetic the old bun
        // needed.
        p.addCurve(
            to: CGPoint(x: rect.minX + w * 0.36, y: base),
            control1: CGPoint(x: rect.minX - w * 0.04, y: rect.minY + h * 0.30),
            control2: CGPoint(x: rect.minX + w * 0.40, y: rect.minY + h * 0.12)
        )
        // Centre lobe, tallest — it reaches the top of the rect.
        p.addCurve(
            to: CGPoint(x: rect.minX + w * 0.64, y: base),
            control1: CGPoint(x: rect.minX + w * 0.22, y: rect.minY - h * 0.22),
            control2: CGPoint(x: rect.minX + w * 0.78, y: rect.minY - h * 0.22)
        )
        // Right lobe, mirroring the left.
        p.addCurve(
            to: CGPoint(x: rect.minX + w * 0.94, y: base),
            control1: CGPoint(x: rect.minX + w * 0.60, y: rect.minY + h * 0.12),
            control2: CGPoint(x: rect.maxX + w * 0.04, y: rect.minY + h * 0.30)
        )
        p.addLine(to: CGPoint(x: rect.minX + w * 0.94, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.06, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

