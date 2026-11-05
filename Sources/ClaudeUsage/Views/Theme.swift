import AppKit
import SwiftUI

// MARK: - Colours & type

/// Black, silver and glass. Always dark, whatever the system appearance.
enum Palette {
    static let bg = Color.black
    /// Cards.
    static let card = Color(hex: 0x1C1C1E)
    /// Buttons at rest, and the empty part of bars.
    static let button = Color(hex: 0x2C2C2E)
    /// Active or hovered buttons and tabs.
    static let buttonHi = Color(hex: 0x3A3A3C)
    static let text = Color(hex: 0xF5F5F7)
    static let text2 = Color(hex: 0x8E8E93)
    /// Faintest text (hints, counters).
    static let text3 = Color(hex: 0x636366)
    /// Progress and the visualizer.
    static let silver = Color(hex: 0xD1D5DB)
    /// The only colour: Claude's "working" dot and usage above 90%.
    static let red = Color(hex: 0xE5322B)

    // Older names, kept so every view speaks the same palette.
    static let glass = card
    static let line = button
    static let track = button
    static let hover = buttonHi
    static let silverBright = silver
    static let steel = text2
    static let onSilver = Color(hex: 0x111113)
    static let rose = red
    static let silverGradient = LinearGradient(colors: [silver, silver], startPoint: .top, endPoint: .bottom)
    static let rim = LinearGradient(colors: [card, card], startPoint: .top, endPoint: .bottom)
    static let confetti: [Color] = [.white, silver, text2, red]

    /// Usage colour: `base` up to 90%, red above. (No other warning colour.)
    static func level(_ percent: Double, base: Color, warn: Double = 90) -> Color {
        percent >= 90 ? red : base
    }
}

/// Corner radii, all continuous.
enum Radius {
    static let card: CGFloat = 20
    static let button: CGFloat = 10
    static let preset: CGFloat = 11
    static let tab: CGFloat = 8

    static func shape(_ r: CGFloat) -> RoundedRectangle { RoundedRectangle(cornerRadius: r, style: .continuous) }
}

extension View {
    /// The one big number of a card: 38 pt semibold, tight tracking, steady digits.
    func bigNumber(_ size: CGFloat = 38) -> some View {
        font(.system(size: size, weight: .semibold)).tracking(-1).monospacedDigit().foregroundStyle(Palette.text)
    }

    /// Small secondary label (11 pt).
    func cardLabel() -> some View {
        font(.app(11)).foregroundStyle(Palette.text2).lineLimit(1).truncationMode(.tail)
    }

    /// Song title (13 pt semibold).
    func songTitle() -> some View {
        font(.app(13, .semibold)).foregroundStyle(Palette.text).lineLimit(1).truncationMode(.tail)
    }

    /// A card: #1C1C1E, radius 20, padding 12.
    func notchCard(padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Radius.shape(Radius.card).fill(Palette.card))
    }
}

/// One set of curves so everything moves the same calm way. Every module uses these; none makes its own.
enum Motion {
    /// The notch growing to live, pop or expanded: an unhurried spring that settles softly.
    static let open = Animation.spring(response: 0.46, dampingFraction: 0.8)
    /// The notch shrinking: a touch quicker and with no bounce, so it tucks away calmly.
    static let close = Animation.spring(response: 0.36, dampingFraction: 1)
    /// Content easing in a beat after the shape starts to grow.
    static let contentIn = Animation.easeOut(duration: 0.32).delay(0.07)
    /// Content fading out before the shape shrinks.
    static let contentOut = Animation.easeIn(duration: 0.14)
    /// The live row's sides fading in once the shape has widened.
    static let liveIn = Animation.easeOut(duration: 0.25).delay(0.1)
    /// Value changes: rings, progress, colours.
    static let smooth = Animation.smooth(duration: 0.28)
    /// Button hover and press.
    static let quick = Animation.snappy(duration: 0.18, extraBounce: 0)
    /// Small celebratory pop-in (a badge or ember lighting up).
    static let popIn = Animation.snappy(duration: 0.3, extraBounce: 0.15)
    /// The Pomodoro fuse drawing out from the centre when focus starts.
    static let fuse = Animation.easeOut(duration: 0.5)
    /// Side panels (the playlist) sliding in and out.
    static let slide = Animation.spring(response: 0.4, dampingFraction: 0.86)
    /// The open notch growing or shrinking to fit the page, and the tab capsule gliding.
    static let resize = Animation.spring(response: 0.45, dampingFraction: 0.8)
    /// A page swapping in when the tab changes (fade, 5 pt shift).
    static let page = Animation.easeOut(duration: 0.22)
    /// What springs become with Reduce Motion on.
    static let reduced = Animation.easeInOut(duration: 0.2)
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Font {
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Containers

/// Frosted glass behind the whole window.
struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension View {
    /// Glass card. `fillHeight` stretches it to the row's height (cards side by side).
    func card(fillHeight: Bool = false) -> some View {
        padding(12)
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
            .background(Radius.shape(Radius.card).fill(Palette.card))
    }
}

struct CardTitle<Trailing: View>: View {
    let text: String
    let trailing: Trailing

    init(_ text: String, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.app(10.5, .semibold))
                .tracking(1.2)
                .foregroundStyle(Palette.text2)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing
        }
    }
}

extension CardTitle where Trailing == EmptyView {
    init(_ text: String) { self.init(text) { EmptyView() } }
}

// MARK: - Controls

/// Round glass toolbar button that brightens on hover.
struct IconButton: View {
    let systemName: String
    let help: String
    var rotation: Double = 0
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? Palette.text : Palette.text2)
                .rotationEffect(.degrees(rotation))
                .frame(width: 28, height: 28)
                .background(Circle().fill(hovering ? Palette.hover : Palette.glass))
                .overlay(Circle().strokeBorder(Palette.rim, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
        .help(help)
    }
}

/// Segmented control whose silver pill glides between options.
struct PillToggle: View {
    let options: [String]
    @Binding var selection: Int
    /// Stretch the segments to fill the available width (used for the main tab bar).
    var fill = false
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                Text(options[i])
                    .font(.app(11.5, .medium))
                    .foregroundStyle(selection == i ? Palette.text : Palette.text2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, fill ? 6 : 4)
                    .frame(maxWidth: fill ? .infinity : nil)
                    .background {
                        if selection == i {
                            Radius.shape(Radius.tab).fill(Palette.buttonHi).matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(Motion.quick) { selection = i } }
            }
        }
        .padding(2)
        .background(Radius.shape(Radius.button).fill(Palette.card))
    }
}

struct Chip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).foregroundStyle(Palette.text2)
            Spacer(minLength: 2)
            Text(value).fontWeight(.medium).foregroundStyle(Palette.text).monospacedDigit()
        }
        .font(.app(11))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Palette.glass))
        .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 0.5))
    }
}

// MARK: - Gauges

/// Slim progress bar for one plan limit. It glides when the value changes and shimmers while refreshing.
struct LimitBar: View {
    let title: String
    let percent: Double?
    let subtitle: String
    var shimmering = false

    private var value: Double { min(max(percent ?? 0, 0), 100) }
    private var warning: Color? { value < 70 ? nil : Palette.level(value, base: Palette.silver) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.app(13, .medium)).foregroundStyle(Palette.text)
                Text(subtitle).font(.app(11)).foregroundStyle(Palette.text3)
                Spacer()
                Text(percent == nil ? "–" : "\(Int(value.rounded()))%")
                    .font(.app(15, .light))
                    .foregroundStyle(warning ?? Palette.text)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.line)
                    Group {
                        if let warning { Capsule().fill(warning) } else { Capsule().fill(Palette.silverGradient) }
                    }
                    .frame(width: value > 0 ? max(6, geo.size.width * value / 100) : 0)
                    .overlay { if shimmering { Shimmer().clipShape(Capsule()) } }
                }
            }
            .frame(height: 6)
        }
        .animation(Motion.smooth, value: value)
    }
}

/// A soft band of light that sweeps across its container.
private struct Shimmer: View {
    @Environment(\.animationsPaused) private var paused

    var body: some View {
        // A highlight sweeping across every 1.2 s; it stops with everything else when out of sight.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
            let phase = paused ? -1 : -1 + 2 * (t * t * (3 - 2 * t))
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width * 1.6)
            }
        }
    }
}

/// "Working" badge for a busy session row: a slowly breathing ellipsis.
struct WorkingBadge: View {
    var hovering = false
    @Environment(\.animationsPaused) private var paused

    var body: some View {
        // Core Animation dots: a repeating SwiftUI symbol effect redrew the panel every frame (about 20% CPU).
        LayerWorkingDots(running: !paused, color: NSColor(Palette.silver))
            .frame(width: WorkingDotsHost.size.width, height: WorkingDotsHost.size.height)
            .allowsHitTesting(false)
    }
}

/// Bar chart whose bars rise in one by one; hovering a bar reports its index.
struct InteractiveBars: View {
    let values: [Int]
    /// Evenly spaced axis labels; values.count should be a multiple of labels.count.
    let labels: [String]
    let current: Int
    var future: Int? = nil
    @Binding var hovered: Int?

    @State private var grown = false
    private let height: CGFloat = 60

    var body: some View {
        let maxValue = max(values.max() ?? 0, 1)
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(values.indices, id: \.self) { i in
                    bar(i, maxValue: maxValue)
                }
            }
            HStack(spacing: 3) {
                ForEach(labels.indices, id: \.self) { i in
                    Text(labels[i])
                        .font(.app(9, .medium))
                        .foregroundStyle(Palette.text3)
                        .frame(maxWidth: .infinity, alignment: labels.count == values.count ? .center : .leading)
                }
            }
        }
        .onAppear { grown = true }
    }

    private func bar(_ i: Int, maxValue: Int) -> some View {
        let barHeight: CGFloat = values[i] > 0 ? max(4, CGFloat(values[i]) / CGFloat(maxValue) * height) : 0
        let isFuture = future.map { i >= $0 } ?? false
        return ZStack(alignment: .bottom) {
            Capsule().fill(Palette.line.opacity(isFuture ? 0.4 : 0.8))
            Capsule()
                .fill(color(i))
                .frame(height: grown ? barHeight : 0)
                .animation(.smooth(duration: 0.4).delay(Double(i) * 0.008), value: grown)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(Motion.quick) {
                if h { hovered = i } else if hovered == i { hovered = nil }
            }
        }
    }

    private func color(_ i: Int) -> AnyShapeStyle {
        if hovered == i { return AnyShapeStyle(Color.white) }
        if i == current { return AnyShapeStyle(Palette.silverGradient) }
        return AnyShapeStyle(Palette.steel.opacity(0.35))
    }
}

/// A gentle shower of silver flakes each time `trigger` changes.
struct ConfettiView: View {
    let trigger: Int

    private struct Piece {
        let vx: Double, vy: Double, spin: Double, size: CGSize, color: Color, round: Bool
    }

    @State private var start: Date?
    @State private var pieces: [Piece] = []
    @Environment(\.reduceMotion) private var reduceMotion
    private let lifetime = 2.4

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: start == nil)) { context in
            Canvas { ctx, size in
                guard let start else { return }
                let t = context.date.timeIntervalSince(start)
                guard t < lifetime else { return }
                for p in pieces {
                    let x = size.width / 2 + p.vx * t
                    let y = 50 + p.vy * t + 0.5 * 320 * t * t
                    var piece = ctx
                    // Fade in quickly, then out slowly.
                    piece.opacity = min(t / 0.2, 1) * (1 - t / lifetime)
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(p.spin * t))
                    let rect = CGRect(origin: CGPoint(x: -p.size.width / 2, y: -p.size.height / 2), size: p.size)
                    piece.fill(p.round ? Path(ellipseIn: rect) : Path(rect), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in burst() }
    }

    private func burst() {
        guard !reduceMotion else { return }
        pieces = (0..<30).map { _ in
            let angle = Double.random(in: -Double.pi * 0.9 ... -Double.pi * 0.1)
            let speed = Double.random(in: 90...220)
            return Piece(
                vx: cos(angle) * speed,
                vy: sin(angle) * speed,
                spin: Double.random(in: -4...4),
                size: CGSize(width: Double.random(in: 3...6), height: Double.random(in: 2...4)),
                color: Palette.confetti.randomElement()!,
                round: Bool.random()
            )
        }
        start = Date()
        Task {
            try? await Task.sleep(for: .seconds(lifetime))
            start = nil
        }
    }
}

// MARK: - Menu bar

enum MenuBarIcon {
    /// Ring that fills with the session limit. `dot` adds a centre dot while Claude is working.
    static func ring(fraction: Double, dot: Bool = false) -> NSImage {
        draw { center, radius in
            stroke(arcFrom: 90, sweep: 360, center: center, radius: radius, alpha: 0.3)
            let f = min(max(fraction, 0), 1)
            if f > 0 { stroke(arcFrom: 90, sweep: 360 * f, center: center, radius: radius, alpha: 1) }
            if dot {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)).fill()
            }
        }
    }

    static func done() -> NSImage {
        let image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Done")!
        image.isTemplate = true
        return image
    }

    private static func draw(_ body: @escaping (NSPoint, CGFloat) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            body(NSPoint(x: 8, y: 8), 6.25)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func stroke(arcFrom start: Double, sweep: Double, center: NSPoint, radius: CGFloat, alpha: CGFloat) {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius,
                       startAngle: CGFloat(start), endAngle: CGFloat(start - sweep), clockwise: true)
        path.lineWidth = 2
        path.lineCapStyle = .round
        NSColor.black.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }
}
