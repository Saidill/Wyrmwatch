import SwiftUI

/// The Wyrmwatch progress bar: a row of small overlapping scales (8 pt). Filled scales are silver (or `color`),
/// the rest #2C2C2E. When the value grows, the newly filled scales light one after another, 20 ms apart.
/// (Kept under its old name so every bar in the app draws this way.)
struct ThinBar: View {
    let fraction: Double
    var color: Color = Palette.silver
    var height: CGFloat = 8
    @State private var shown = 0
    @State private var from = 0
    @Environment(\.reduceMotion) private var reduceMotion

    /// Scale width and step: each scale overlaps the one before by a third.
    private var scale: CGFloat { height }
    private var step: CGFloat { height * 2 / 3 }

    var body: some View {
        GeometryReader { geo in
            let count = max(1, Int((geo.size.width - scale) / step) + 1)
            let target = Int((min(max(fraction, 0), 1) * Double(count)).rounded())
            ZStack(alignment: .leading) {
                ForEach(0..<count, id: \.self) { i in
                    ScaleShape()
                        .fill(i < shown ? color : Palette.button)
                        .overlay(ScaleShape().stroke(Palette.bg, lineWidth: 1))
                        .frame(width: scale, height: height)
                        .offset(x: CGFloat(i) * step)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12).delay(Double(max(0, i - from)) * 0.02), value: shown)
                }
            }
            .onAppear { shown = target; from = target }
            .onChange(of: target) { old, new in
                from = min(old, new)
                shown = new
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

/// One scale: flat on top, rounded below, like a fish scale seen from the side.
struct ScaleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.15))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.15), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.15))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.minY + r.height * 0.7),
                   control2: CGPoint(x: r.midX + r.width * 0.3, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.15), control1: CGPoint(x: r.midX - r.width * 0.3, y: r.maxY),
                   control2: CGPoint(x: r.minX, y: r.minY + r.height * 0.7))
        p.closeSubpath()
        return p
    }
}

/// Round button with an SF Symbol: #24262B at rest, #3A3D44 on hover.
struct RoundButton: View {
    let systemName: String
    var diameter: CGFloat = 30
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: diameter * 0.36, weight: .semibold))
                .foregroundStyle(Palette.text)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(hovering ? Palette.buttonHi : Palette.button))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
        .help(help)
    }
}

/// A plain icon button for the player row: grey, brighter on hover.
struct GlyphButton: View {
    let systemName: String
    var size: CGFloat = 13
    var active = false
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(active || hovering ? Palette.text : Palette.text2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
        .help(help)
    }
}

/// Capsule chip: #24262B, silver text.
struct NotchChip: View {
    let title: String
    var selected = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.app(11))
                .foregroundStyle(selected ? Palette.onSilver : Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(Capsule().fill(selected ? Palette.silver : (hovering ? Palette.buttonHi : Palette.button)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
    }
}

/// Song progress you can drag to seek: elapsed | 4 pt bar | length. Ticks once a second while playing and in view.
struct SeekRow: View {
    @ObservedObject var bridge: MusicBridge
    var probePrefix: String? = nil
    @Environment(\.animationsPaused) private var paused
    @State private var dragging: Double?

    var body: some View {
        let duration = max(bridge.track?.duration ?? 0, 1)
        TimelineView(.animation(minimumInterval: 1, paused: paused || !bridge.isPlaying || dragging != nil)) { context in
            let now = dragging ?? bridge.currentPosition(at: context.date)
            HStack(spacing: 8) {
                Text(Self.format(now))
                    .frame(width: 32, alignment: .leading)
                    .probe(probePrefix.map { $0 + "elapsed" } ?? "")
                GeometryReader { geo in
                    ThinBar(fraction: now / duration)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { g in dragging = min(max(g.location.x / geo.size.width, 0), 1) * duration }
                            .onEnded { _ in
                                if let dragging { bridge.seek(to: dragging) }
                                dragging = nil
                            })
                }
                .frame(height: 12)
                .probe(probePrefix.map { $0 + "progress" } ?? "")
                Text(Self.format(duration))
                    .frame(width: 32, alignment: .trailing)
                    .probe(probePrefix.map { $0 + "length" } ?? "")
            }
            .font(.app(11))
            .foregroundStyle(Palette.text2)
            .monospacedDigit()
            .lineLimit(1)
        }
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(max(seconds, 0).rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Card controls

/// Buttons shrink a touch (0.96) while pressed; with Reduce Motion they don't move.
struct Pressable: ButtonStyle {
    @Environment(\.reduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == Pressable {
    static var pressable: Pressable { Pressable() }
}

/// A button inside a card: #2C2C2E (or #3A3A3C when `active`), radius 10. Shows a symbol and/or a title.
struct CardButton: View {
    var systemName: String?
    var title: String?
    var active = false
    var height: CGFloat = 30
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemName { Image(systemName: systemName).font(.system(size: 13, weight: .semibold)) }
                if let title { Text(title).font(.app(13, .semibold)).lineLimit(1).minimumScaleFactor(0.85) }
            }
            .foregroundStyle(Palette.text)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(Radius.shape(Radius.button).fill(active || hovering ? Palette.buttonHi : Palette.button))
            .contentShape(Radius.shape(Radius.button))
        }
        .buttonStyle(.pressable)
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
        .help(help)
    }
}

/// A preset tile (radius 11, 34 pt tall).
struct PresetButton: View {
    let title: String
    var selected = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.app(13, .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
                .background(Radius.shape(Radius.preset).fill(selected || hovering ? Palette.buttonHi : Palette.button))
                .contentShape(Radius.shape(Radius.preset))
        }
        .buttonStyle(.pressable)
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
    }
}

/// Cards come in one after another, 30 ms apart (fade and a 5 pt rise); with Reduce Motion they just appear.
private struct CardAppear: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.reduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 5)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Motion.page.delay(Double(index) * 0.03)) { shown = true }
            }
    }
}

extension View {
    func cardAppear(_ index: Int) -> some View { modifier(CardAppear(index: index)) }
}
