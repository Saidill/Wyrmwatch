import AppKit
import SwiftUI

/// What the dragon is up to; it follows what's going on in the notch.
enum DragonMood: Equatable {
    /// Nothing running: dimmed, a slow "z" drifting up.
    case sleeping
    /// Awake and calm: a slow breath.
    case idle
    /// Claude is working: the eye glows and a soft red glow pulses behind it.
    case working
    /// Something just finished: a short burst of flame from the mouth.
    case happy
    /// Keeping watch over a focus session: still, eye bright.
    case guarding
}

private struct AnimationsPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Stops every repeating animation (dragon, visualizer) while it's out of sight,
    /// e.g. the notch content when the notch is closed.
    var animationsPaused: Bool {
        get { self[AnimationsPausedKey.self] }
        set { self[AnimationsPausedKey.self] = newValue }
    }
}

/// The dragon artwork: "Spiked dragon head" by Delapouite, from game-icons.net, CC BY 3.0
/// (https://game-icons.net/1x1/delapouite/spiked-dragon-head.html). Used as a template image and tinted red.
enum DragonArt {
    static let image: NSImage = {
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path fill="#000" d="M188.8 20.38c-5.3 26.85 4.6 55.74 34.1 86.52 11.2-7.29 31.6-10.94 50-8.16-46-22.31-66.5-47.13-84.1-78.36zM29.19 26.62C43.56 73.08 81.09 128.8 129.6 168.3 93.51 166 49.93 153.1 18.76 143c24.96 35.2 64.17 52.9 103.34 66.3C97.13 227 66.99 245 18.66 248c54.64 19.2 107.54 8.9 131.34.7-17.9 34.9-100.72 66.2-122.31 77 53.26 4.2 121.71-11 167.01-32.9 10 24.6-1.6 53.2-10.1 77.8-1.9 4.5-3.8 8.9-5.7 13.3 5.1-3.5 10.1-7 14.9-10.6 23.6-16.2 47.8-31.9 59.5-58.8 26.1 31.2 62.7 62.1 107 85.4 17.4 22.1 28.3 49 34.2 73.8 8.3-19.1 13.8-40.2 9.7-60.3 24.5-3.6 35.6-29.7 35.5-54.4-12.6 6.2-15.1 6.3-31.2 8.2 0-10.1.6-12.5-3-28.7-10.3 8.4-21 11.2-30.8 11.8 2.1-7.6 3-19.5 3.7-27.3-13 7.1-19.2 9.7-30.1 10.8-.4-10.9-.1-20-4.1-30.4-29.6 19-48.6 1.5-68-21.3 19.8-17 96.4-21.8 95.1 7.1 14-7.3 18.8-11.2 23.6-15.9 9.1 8.5 13.4 20.9 15.1 31.4 9.3-9.4 10.3-10.5 17.1-23.8 5.7 10.1 8.8 17 10.7 30.6 8.5-6.2 15.4-13.1 19.8-21.4 7.5 15.5 8.3 16 12.4 33 17.8-13.1 21.8-31.2 22.8-47.6 2-33-.3-108.2-31-142.9 1.7 36.3-13.1 70-33.8 80.7-12.6 4.9-96.5-74.6-137.6-93.3-23.5-10.2-48.1 7.1-67.8 9.3C147 106.2 83.57 70.94 29.19 26.62zM296.1 152.8c13.3 20.9 32.2 36.9 60.1 55-19.4 2.9-65.8-6.7-77.7-24-5.5-7.9 7.1-21.3 17.6-31zM180.6 319.1c-14.4 6.2-29.2 10.9-43.8 14.3-2.4 3.6-4.6 7.1-6.7 10.5 14.8 5.3 31.5 7 44.1 2.8 3.3-9.8 5.5-19.3 6.4-27.6zm-68 19.1l-10.2 1.5c-31.81 36.6-61.9 103.2-48.24 151.9h36.13c-11.12-37.7-16.53-87.1 22.31-153.4zm8.5 21.5c-5.9 11.4-10.4 22.1-13.8 32.1 12.9 6.7 29.1 8.9 44.8 8.2 4.6-10.5 9.8-21.8 14.6-33.3-15.4 1.8-31.4-1.4-45.6-7zm111.4 6.6c-12 10.5-25.2 20.3-38.9 29.6 7 34 33.4 63.4 73.9 95.7h83.3c-57.2-31.8-94.6-73.3-118.3-125.3zm-130 43.2c-2.5 11.8-3.3 22.7-3 32.9 37.3 14.2 62.5 13.5 97.5 4.1-7.2-10.3-13-21-16.9-32.3-32.7 9.4-55.4 5.7-77.6-4.7zm106.6 52.4c-38.1 10.9-68.8 13.2-107.5.3 1.8 10.4 4.5 20.1 7.5 29.4h130.1c-11.3-9.8-21.4-19.6-30.1-29.7z"/></svg>"##
        let image = NSImage(data: Data(svg.utf8)) ?? NSImage()
        image.isTemplate = true
        return image
    }()

    // Landmarks on the artwork, as fractions of its size (from the top left).
    static let eye = CGPoint(x: 0.625, y: 0.365)
    /// Between the jaws, just behind the front teeth (not the snout tip above them).
    static let mouth = CGPoint(x: 0.85, y: 0.665)

    static let red = LinearGradient(colors: [Color(hex: 0xF0454B), Color(hex: 0xC8202C), Color(hex: 0x8E1119)],
                                    startPoint: .top, endPoint: .bottom)
}

/// The Notchwyrm mascot. Animates gently while on show (in Core Animation layers), lifts a little
/// when the pointer is on it, and stays completely still when `animated` is off (the live notch) or out of sight.
struct DragonView: View {
    var mood: DragonMood
    var size: CGFloat = 28
    /// Draws one fixed moment instead of animating (the self-test and the app icon use it).
    var at: Double? = nil
    /// Extra width to the right (as a fraction of `size`) for the flame.
    var fireRoom: CGFloat = 0
    /// Off in the live notch: the dragon is a still badge there, which keeps the notch cheap.
    var animated = true
    @Environment(\.animationsPaused) private var paused
    @State private var hovering = false

    var body: some View {
        let still = paused || at != nil || !animated
        Group {
            if still {
                DragonFrame(mood: mood, t: at ?? 0, size: size)
            } else {
                // Animated by Core Animation: no work in the app per frame.
                LayerDragon(mood: mood, size: size, running: true)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size * (1 + fireRoom), height: size, alignment: .leading)
        .scaleEffect(hovering ? 1.08 : 1, anchor: .bottomLeading)
        .rotationEffect(.degrees(hovering ? -4 : 0), anchor: .bottomLeading)
        .onHover { inside in withAnimation(Motion.quick) { hovering = inside } }
        .id(mood)
        .transition(.opacity)
        .animation(Motion.smooth, value: mood)
        .accessibilityLabel(label)
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

/// One moment of the dragon.
private struct DragonFrame: View {
    let mood: DragonMood
    let t: Double
    let size: CGFloat

    var body: some View {
        let breath = sin(t * 2 * .pi / 3.2)
        let pulse = 0.5 + 0.5 * sin(t * 2 * .pi / 1.6)
        let glow: Double = switch mood {
        case .working: 0.25 + 0.35 * pulse
        case .guarding: 0.35
        case .happy: 0.5
        default: 0
        }
        ZStack(alignment: .topLeading) {
            if glow > 0 {
                art.blur(radius: size * 0.1).opacity(glow)
            }
            art
                .scaleEffect(mood == .idle || mood == .sleeping ? 1 + 0.015 * breath : 1, anchor: .bottom)
                .opacity(mood == .sleeping ? 0.55 : 1)
            if mood != .sleeping {
                eye(brightness: mood == .idle ? 0.55 : 0.85 + 0.15 * pulse)
            }
            if mood == .happy { flame }
            if mood == .sleeping, size >= 24 { snore }
        }
        .frame(width: size, height: size, alignment: .topLeading)
    }

    private var art: some View {
        Image(nsImage: DragonArt.image)
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(DragonArt.red)
            .frame(width: size, height: size)
    }

    /// A warm light in the eye socket.
    private func eye(brightness: Double) -> some View {
        Ellipse()
            .fill(RadialGradient(colors: [Color(hex: 0xFFE3A3).opacity(brightness), Color(hex: 0xFF8A1F).opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size * 0.07))
            .frame(width: size * 0.16, height: size * 0.09)
            .position(x: DragonArt.eye.x * size, y: DragonArt.eye.y * size)
    }

    /// A short flame from the mouth, every 2.4 s.
    private var flame: some View {
        let ph = t.truncatingRemainder(dividingBy: 2.4)
        let raw = ph < 0.25 ? ph / 0.25 : ph < 1.3 ? 1 : ph < 1.7 ? 1 - (ph - 1.3) / 0.4 : 0
        let burst = raw * raw * (3 - 2 * raw)
        return Canvas { ctx, _ in
            guard burst > 0.02 else { return }
            let origin = CGPoint(x: DragonArt.mouth.x * size, y: DragonArt.mouth.y * size)
            for i in 0..<5 {
                let f = Double(i) / 4
                let flicker = 0.85 + 0.15 * sin(t * 23 + Double(i) * 1.7)
                let c = CGPoint(x: origin.x + (0.05 + 0.45 * f) * size * burst, y: origin.y - 0.04 * f * size + sin(t * 9 + f * 4) * 0.02 * size)
                let r = (0.05 + 0.09 * f) * size * burst * flicker
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF1C9).opacity(1 - f * 0.8), Color(hex: 0xFF7A1A).opacity(0.85 - f * 0.4),
                                                                 Color(hex: 0xC8202C).opacity(0)]),
                                               center: c, startRadius: 0, endRadius: r))
            }
        }
        .frame(width: size * 1.6, height: size)
        .allowsHitTesting(false)
    }

    /// A small "z" rising from the snout and fading.
    private var snore: some View {
        let phase = (t / 2.8).truncatingRemainder(dividingBy: 1)
        return Text("z")
            .font(.system(size: size * 0.22, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.text2)
            .opacity(sin(phase * .pi) * 0.8)
            .position(x: (0.88 + phase * 0.1) * size, y: (0.3 - phase * 0.25) * size)
    }
}
