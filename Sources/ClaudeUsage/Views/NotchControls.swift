import SwiftUI

/// A 4 pt bar: track #2A2B2F, filled silver (or a warning colour).
struct ThinBar: View {
    let fraction: Double
    var color: Color = Palette.silver
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule().fill(color)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
        .animation(Motion.smooth, value: fraction)
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
                .font(.app(11, .medium))
                .foregroundStyle(selected ? Palette.onSilver : Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 26)
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
                    .frame(width: 30, alignment: .leading)
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
                    .frame(width: 30, alignment: .trailing)
                    .probe(probePrefix.map { $0 + "length" } ?? "")
            }
            .font(.app(10))
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
