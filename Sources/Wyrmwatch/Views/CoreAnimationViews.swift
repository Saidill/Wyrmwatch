import AppKit
import QuartzCore
import SwiftUI

// Repeating animations done in Core Animation: they run in the render server, so the app itself does no
// work per frame (SwiftUI would redraw the panel on every frame). Each one stops entirely when `running` is off.

// MARK: - Visualizer

/// Four bars bouncing out of step, as layers.
struct LayerVisualizer: NSViewRepresentable {
    var running: Bool
    var color: NSColor

    func makeNSView(context: Context) -> VisualizerHost { VisualizerHost() }

    func updateNSView(_ view: VisualizerHost, context: Context) {
        view.update(running: running, color: color)
    }
}

final class VisualizerHost: NSView {
    private var bars: [CALayer] = []
    private var running = false
    static let size = CGSize(width: 16, height: 12)

    override init(frame: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        for i in 0..<4 {
            let bar = CALayer()
            bar.frame = CGRect(x: CGFloat(i) * 4.5, y: 0, width: 2.5, height: Self.size.height)
            bar.cornerRadius = 1.25
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bar.position = CGPoint(x: CGFloat(i) * 4.5 + 1.25, y: Self.size.height / 2)
            bar.setAffineTransform(CGAffineTransform(scaleX: 1, y: 0.25))
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { Self.size }

    func update(running: Bool, color: NSColor) {
        bars.forEach { $0.backgroundColor = color.cgColor }
        guard running != self.running else { return }
        self.running = running
        let durations: [CFTimeInterval] = [0.42, 0.55, 0.37, 0.61]
        for (i, bar) in bars.enumerated() {
            if running {
                let bounce = CABasicAnimation(keyPath: "transform.scale.y")
                bounce.fromValue = 0.22
                bounce.toValue = 1.0
                bounce.duration = durations[i]
                bounce.autoreverses = true
                bounce.repeatCount = .infinity
                bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bounce.beginTime = CACurrentMediaTime() - Double(i) * 0.17
                bar.add(bounce, forKey: "bounce")
            } else {
                bar.removeAllAnimations()
            }
        }
    }
}

// MARK: - Status dot

/// A small dot that pulses slowly (fades between 45% and 100% over 1.6 s) while `pulsing`.
struct LayerPulseDot: NSViewRepresentable {
    var color: NSColor
    var pulsing: Bool
    var diameter: CGFloat = 6

    func makeNSView(context: Context) -> PulseDotHost { PulseDotHost(diameter: diameter) }

    func updateNSView(_ view: PulseDotHost, context: Context) {
        view.update(color: color, pulsing: pulsing)
    }
}

final class PulseDotHost: NSView {
    private let dot = CALayer()
    private var pulsing = false
    private let diameter: CGFloat

    init(diameter: CGFloat) {
        self.diameter = diameter
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        wantsLayer = true
        dot.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        dot.cornerRadius = diameter / 2
        layer?.addSublayer(dot)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: diameter, height: diameter) }

    func update(color: NSColor, pulsing: Bool) {
        dot.backgroundColor = color.cgColor
        guard pulsing != self.pulsing else { return }
        self.pulsing = pulsing
        guard pulsing else {
            dot.removeAllAnimations()
            return
        }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.45
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.add(pulse, forKey: "pulse")
    }
}

/// Claude's state as a dot: red and pulsing while working, steady white while waiting for you, hidden otherwise.
struct ClaudeStatusDot: View {
    var working: Bool
    var waiting: Bool
    var diameter: CGFloat = 6
    @Environment(\.animationsPaused) private var paused

    var body: some View {
        if working || waiting {
            LayerPulseDot(color: NSColor(working ? Palette.red : Palette.text), pulsing: working && !paused, diameter: diameter)
                .frame(width: diameter, height: diameter)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Working dots

/// Three dots fading in turn: a session is working.
struct LayerWorkingDots: NSViewRepresentable {
    var running: Bool
    var color: NSColor

    func makeNSView(context: Context) -> WorkingDotsHost { WorkingDotsHost() }

    func updateNSView(_ view: WorkingDotsHost, context: Context) {
        view.update(running: running, color: color)
    }
}

final class WorkingDotsHost: NSView {
    static let size = CGSize(width: 16, height: 4)
    private var dots: [CALayer] = []
    private var running = false

    override init(frame: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        for i in 0..<3 {
            let dot = CALayer()
            dot.frame = CGRect(x: CGFloat(i) * 6, y: 0, width: 4, height: 4)
            dot.cornerRadius = 2
            dot.opacity = 0.35
            layer?.addSublayer(dot)
            dots.append(dot)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { Self.size }

    func update(running: Bool, color: NSColor) {
        dots.forEach { $0.backgroundColor = color.cgColor }
        guard running != self.running else { return }
        self.running = running
        for (i, dot) in dots.enumerated() {
            guard running else {
                dot.removeAllAnimations()
                continue
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.3
            fade.toValue = 1
            fade.duration = 0.45
            fade.autoreverses = true
            fade.repeatCount = .infinity
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fade.beginTime = CACurrentMediaTime() + Double(i) * 0.15
            dot.add(fade, forKey: "fade")
        }
    }
}
