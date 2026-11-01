import SwiftUI

/// What the dragon is up to; it follows what's going on in the notch.
enum DragonMood: Equatable {
    /// Nothing running: head down, eye shut, a wisp of smoke.
    case sleeping
    /// Awake and calm: slow breaths, the odd blink.
    case idle
    /// Claude is working: eye glowing, jaw working, sparks at the mouth.
    case working
    /// Something just finished: rears up and breathes a burst of fire.
    case happy
    /// Keeping watch over a focus session: still, head high, eye wide and bright.
    case guarding
}

private struct AnimationsPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Stops every repeating animation (dragon, ember, visualizer) while it's out of sight,
    /// e.g. the notch content when the notch is closed.
    var animationsPaused: Bool {
        get { self[AnimationsPausedKey.self] }
        set { self[AnimationsPausedKey.self] = newValue }
    }
}

/// The Notchwyrm mascot: a red dragon head in profile, drawn and animated in a Canvas.
/// It perks up when the pointer is on it.
struct DragonView: View {
    var mood: DragonMood
    var size: CGFloat = 28
    /// Draws one fixed moment instead of animating (the self-test and the app icon use it).
    var at: Double? = nil
    /// Extra width to the right (as a fraction of `size`) so the fire isn't cut off.
    var fireRoom: CGFloat = 0
    @Environment(\.animationsPaused) private var paused
    @State private var hovering = false
    @State private var lift = 0.0

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: paused || at != nil)) { timeline in
            Canvas { ctx, canvas in
                DragonDrawing(mood: mood, t: at ?? timeline.date.timeIntervalSinceReferenceDate, lift: lift, detailed: size >= 24)
                    .draw(in: &ctx, side: canvas.height)
            }
        }
        .frame(width: size * (1 + fireRoom), height: size)
        // Its own layer, so each frame redraws just the dragon and not the window around it.
        .drawingGroup()
        .onHover { inside in
            hovering = inside
            withAnimation(Motion.quick) { lift = inside ? 1 : 0 }
        }
        .id(mood)
        .transition(.opacity)
        .animation(Motion.smooth, value: mood)
        .accessibilityLabel(label)
    }

    /// Calm moods move fine at 15 fps; the working jaw and the fire get 30.
    private var frameInterval: Double {
        mood == .working || mood == .happy ? 1.0 / 30 : 1.0 / 15
    }

    private var label: String {
        switch mood {
        case .sleeping: return "Dragon, asleep"
        case .idle: return "Dragon, resting"
        case .working: return "Dragon, working"
        case .happy: return "Dragon, breathing fire"
        case .guarding: return "Dragon, keeping watch"
        }
    }
}

/// The dragon itself, in units of the canvas height, facing right.
struct DragonDrawing {
    let mood: DragonMood
    let t: Double
    /// 0–1: how far the head is raised because the pointer is on it.
    var lift: Double = 0
    var detailed = true

    static let scaleTop = Color(hex: 0xF0454B)
    static let scaleMid = Color(hex: 0xC8202C)
    static let scaleDark = Color(hex: 0x6E0B14)
    static let horn = Color(hex: 0xEDE4DA)
    static let eyeGlow = Color(hex: 0xFFC24B)

    func draw(in ctx: inout GraphicsContext, side s: CGFloat) {
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }

        // MARK: Pose
        let breathe = sin(t * 2 * .pi / (mood == .sleeping ? 4 : 3))
        var tilt = 0.0, drop = 0.0, jaw = 0.02, fire = 0.0, eyeOpen = 1.0, glow = 0.55
        switch mood {
        case .sleeping:
            tilt = 0.16; drop = 0.06; eyeOpen = 0; glow = 0
        case .idle:
            tilt = 0.02 * breathe
            // A blink every 4.5 s.
            eyeOpen = t.truncatingRemainder(dividingBy: 4.5) < 0.14 ? 0.08 : 1
        case .working:
            tilt = -0.03 + 0.015 * sin(t * 5); jaw = 0.05 + 0.035 * abs(sin(t * 7)); glow = 0.85 + 0.15 * sin(t * 6)
        case .happy:
            // A burst every 2.4 s: rear up, open wide, fire, settle.
            let ph = t.truncatingRemainder(dividingBy: 2.4)
            let raw = ph < 0.25 ? ph / 0.25 : ph < 1.4 ? 1 : ph < 1.8 ? 1 - (ph - 1.4) / 0.4 : 0
            fire = raw * raw * (3 - 2 * raw)
            tilt = -0.14 * fire; jaw = 0.03 + 0.16 * fire; glow = 1
        case .guarding:
            tilt = -0.06 + 0.006 * breathe; glow = 0.95 + 0.05 * sin(t * 0.9)
        }
        tilt -= 0.07 * lift
        glow = min(1, glow + 0.3 * lift)

        // Rotate the head about the neck; everything below is drawn in head space.
        var head = ctx
        let pivot = p(0.3, 0.86)
        head.translateBy(x: pivot.x, y: pivot.y + (drop + breathe * 0.006) * s)
        head.rotate(by: .radians(tilt))
        head.translateBy(x: -pivot.x, y: -pivot.y)

        let rim = max(0.6, 0.016 * s)
        let scales = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [.init(color: Self.scaleTop, location: 0), .init(color: Self.scaleMid, location: 0.45),
                             .init(color: Self.scaleDark, location: 1)]),
            startPoint: p(0.5, 0.25), endPoint: p(0.45, 0.95))

        // MARK: Horns (growing out of the back of the skull, behind it)
        for (base, tip, width, bend) in [((0.46, 0.36), (0.13, 0.08), 0.085, 0.07), ((0.37, 0.43), (0.06, 0.27), 0.07, 0.06)] {
            var h = Path()
            h.move(to: p(base.0 + 0.02, base.1 - width / 2))
            h.addQuadCurve(to: p(tip.0, tip.1), control: p((base.0 + tip.0) / 2, tip.1 - bend * 0.4))
            h.addQuadCurve(to: p(base.0 - 0.01, base.1 + width / 2), control: p((base.0 + tip.0) / 2 + 0.02, (base.1 + tip.1) / 2 + bend))
            h.closeSubpath()
            head.fill(h, with: .linearGradient(Gradient(colors: [Color(hex: 0x9C8F84), Self.horn]),
                                               startPoint: p(base.0, base.1), endPoint: p(tip.0, tip.1)))
        }

        // MARK: Neck fins
        if detailed {
            for (i, y) in [0.52, 0.64, 0.76].enumerated() {
                let x = 0.2 - Double(i) * 0.015
                var fin = Path()
                fin.move(to: p(x + 0.04, y - 0.04))
                fin.addQuadCurve(to: p(x - 0.09, y + 0.01), control: p(x - 0.03, y - 0.05))
                fin.addLine(to: p(x + 0.03, y + 0.05))
                fin.closeSubpath()
                head.fill(fin, with: .color(Self.scaleDark))
            }
        }

        // MARK: Lower jaw (behind the skull; opens with `jaw`)
        var lower = Path()
        lower.move(to: p(0.49, 0.58))
        lower.addQuadCurve(to: p(0.88, 0.60 + jaw), control: p(0.70, 0.60 + jaw * 0.5))
        lower.addQuadCurve(to: p(0.62, 0.71 + jaw * 0.6), control: p(0.82, 0.69 + jaw))
        lower.addQuadCurve(to: p(0.46, 0.70), control: p(0.53, 0.73))
        lower.closeSubpath()
        // Inside of the mouth shows as the jaw opens.
        if jaw > 0.04 {
            var mouth = Path()
            mouth.move(to: p(0.56, 0.59))
            mouth.addLine(to: p(0.9, 0.565))
            mouth.addLine(to: p(0.87, 0.60 + jaw))
            mouth.addLine(to: p(0.58, 0.62))
            mouth.closeSubpath()
            head.fill(mouth, with: .color(Color(hex: 0x2A0306)))
        }
        head.fill(lower, with: .linearGradient(Gradient(colors: [Self.scaleMid, Self.scaleDark]),
                                               startPoint: p(0.6, 0.6), endPoint: p(0.6, 0.75)))
        head.stroke(lower, with: .color(Self.scaleDark), lineWidth: rim)

        // MARK: Skull
        var skull = Path()
        skull.move(to: p(0.18, 0.98))
        skull.addCurve(to: p(0.30, 0.40), control1: p(0.10, 0.74), control2: p(0.16, 0.48))
        skull.addCurve(to: p(0.57, 0.30), control1: p(0.40, 0.31), control2: p(0.48, 0.27))
        // Brow bump over the eye, then the long snout ridge.
        skull.addCurve(to: p(0.71, 0.36), control1: p(0.63, 0.31), control2: p(0.67, 0.32))
        skull.addCurve(to: p(0.94, 0.48), control1: p(0.80, 0.39), control2: p(0.90, 0.42))
        skull.addQuadCurve(to: p(0.92, 0.57), control: p(0.98, 0.54))
        skull.addQuadCurve(to: p(0.55, 0.60), control: p(0.74, 0.585))
        skull.addCurve(to: p(0.46, 0.80), control1: p(0.47, 0.63), control2: p(0.45, 0.72))
        skull.addQuadCurve(to: p(0.48, 0.98), control: p(0.46, 0.9))
        skull.closeSubpath()
        head.fill(skull, with: scales)
        head.stroke(skull, with: .color(Self.scaleDark), lineWidth: rim)
        var noseHorn = Path()
        noseHorn.move(to: p(0.78, 0.405))
        noseHorn.addQuadCurve(to: p(0.79, 0.32), control: p(0.77, 0.36))
        noseHorn.addQuadCurve(to: p(0.85, 0.425), control: p(0.83, 0.37))
        noseHorn.closeSubpath()
        head.fill(noseHorn, with: .color(Self.horn))

        // Teeth along the upper jaw, showing when the mouth opens.
        if jaw > 0.05, detailed {
            for x in stride(from: 0.64, through: 0.84, by: 0.06) {
                var tooth = Path()
                tooth.move(to: p(x, 0.595))
                tooth.addLine(to: p(x + 0.018, 0.64))
                tooth.addLine(to: p(x + 0.036, 0.59))
                tooth.closeSubpath()
                head.fill(tooth, with: .color(Self.horn))
            }
        }

        // Brow ridge, cheek and nostril.
        var brow = Path()
        brow.move(to: p(0.53, 0.375))
        brow.addQuadCurve(to: p(0.72, 0.37), control: p(0.63, 0.32))
        head.stroke(brow, with: .color(Self.scaleDark), style: StrokeStyle(lineWidth: rim * 1.6, lineCap: .round))
        if detailed {
            var cheek = Path()
            cheek.move(to: p(0.56, 0.52))
            cheek.addQuadCurve(to: p(0.40, 0.66), control: p(0.44, 0.52))
            head.stroke(cheek, with: .color(Self.scaleDark.opacity(0.7)), style: StrokeStyle(lineWidth: rim * 0.8, lineCap: .round))
            var shine = Path()
            shine.move(to: p(0.33, 0.44))
            shine.addQuadCurve(to: p(0.52, 0.32), control: p(0.38, 0.34))
            head.stroke(shine, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: rim * 0.9, lineCap: .round))
        }
        head.fill(Path(ellipseIn: CGRect(x: 0.86 * s, y: 0.45 * s, width: 0.035 * s, height: 0.02 * s)),
                  with: .color(Self.scaleDark))

        // MARK: Eye
        let eye = p(0.63, 0.425)
        if eyeOpen > 0.5 {
            let r = 0.11 * s
            head.fill(Path(ellipseIn: CGRect(x: eye.x - r, y: eye.y - r, width: r * 2, height: r * 2)),
                      with: .radialGradient(Gradient(colors: [Self.eyeGlow.opacity(0.55 * glow), Self.eyeGlow.opacity(0)]),
                                            center: eye, startRadius: 0, endRadius: r))
            var almond = Path()
            almond.move(to: p(0.575, 0.435))
            almond.addQuadCurve(to: p(0.69, 0.405), control: p(0.63, 0.37))
            almond.addQuadCurve(to: p(0.575, 0.435), control: p(0.64, 0.46))
            head.fill(almond, with: .color(Self.eyeGlow))
            head.fill(Path(ellipseIn: CGRect(x: 0.626 * s, y: 0.398 * s, width: 0.016 * s, height: 0.044 * s)),
                      with: .color(Color(hex: 0x1A0204)))
        } else {
            var lid = Path()
            lid.move(to: p(0.575, 0.43))
            lid.addQuadCurve(to: p(0.69, 0.415), control: p(0.63, 0.455))
            head.stroke(lid, with: .color(Self.scaleDark), style: StrokeStyle(lineWidth: rim * 1.2, lineCap: .round))
        }

        // MARK: Breath
        let mouthPoint = p(0.9, 0.6 + jaw * 0.5)
        if mood == .sleeping, detailed {
            // A wisp of smoke from the nostril.
            for i in 0..<2 {
                let phase = (t * 0.28 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let r = (0.02 + phase * 0.04) * s
                let c = CGPoint(x: (0.9 + phase * 0.06) * s, y: (0.44 - phase * 0.3) * s)
                head.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                          with: .color(Color(hex: 0x8D9096).opacity(sin(phase * .pi) * 0.4)))
            }
        }
        if mood == .working {
            // Sparks spitting from the mouth.
            for i in 0..<3 {
                let phase = (t * 1.3 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let c = CGPoint(x: mouthPoint.x + phase * 0.14 * s, y: mouthPoint.y - phase * 0.12 * s + sin(phase * 9 + Double(i)) * 0.02 * s)
                let r = 0.012 * s * (1 - phase * 0.6)
                head.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                          with: .color(Self.eyeGlow.opacity(1 - phase)))
            }
        }
        if fire > 0.05 {
            for i in 0..<6 {
                let f = Double(i) / 5
                let flicker = 0.85 + 0.15 * sin(t * 25 + Double(i) * 1.9)
                let c = CGPoint(x: mouthPoint.x + (0.06 + 0.4 * f) * fire * s, y: mouthPoint.y + sin(t * 11 + f * 5) * 0.015 * s)
                let r = (0.06 + 0.12 * f) * s * fire * flicker
                head.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                          with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF3C4).opacity(1 - f), Color(hex: 0xFF8A1F).opacity(0.9 - f * 0.4),
                                                                  Color(hex: 0xD7263D).opacity(0)]),
                                                center: c, startRadius: 0, endRadius: r))
            }
        }
    }
}
