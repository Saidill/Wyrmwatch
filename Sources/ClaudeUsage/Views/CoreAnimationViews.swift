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

// MARK: - Dragon

/// The dragon with its mood animated by layers: a breath, a pulsing glow, a lit eye, a particle flame, a drifting "z".
struct LayerDragon: NSViewRepresentable {
    let mood: DragonMood
    let size: CGFloat
    var running: Bool

    func makeNSView(context: Context) -> DragonHost { DragonHost() }

    func updateNSView(_ view: DragonHost, context: Context) {
        view.update(mood: mood, size: size, running: running)
    }
}

final class DragonHost: NSView {
    private let glow = CALayer()
    private let art = CALayer()
    private let eye = CAGradientLayer()
    private let flame = CAEmitterLayer()
    private let snore = CATextLayer()
    private var state: (DragonMood, CGFloat, Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.isGeometryFlipped = true
        layer?.masksToBounds = false
        eye.type = .radial
        eye.colors = [NSColor(hex: 0xFFE3A3).cgColor, NSColor(hex: 0xFF8A1F).withAlphaComponent(0).cgColor]
        eye.startPoint = CGPoint(x: 0.5, y: 0.5)
        eye.endPoint = CGPoint(x: 1, y: 1)
        snore.string = "z"
        snore.foregroundColor = NSColor(hex: 0x8D9096).cgColor
        snore.alignmentMode = .center
        flame.renderMode = .additive
        flame.emitterShape = .point
        [glow, art, eye, flame, snore].forEach { layer?.addSublayer($0) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        state = nil
        needsLayout = true
    }

    func update(mood: DragonMood, size: CGFloat, running: Bool) {
        if let state, state == (mood, size, running) { return }
        state = (mood, size, running)
        let scale = window?.backingScaleFactor ?? 2
        [glow, art, eye, flame, snore].forEach { $0.removeAllAnimations(); $0.contentsScale = scale }
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let images = DragonImages.shared.images(size: size, scale: scale)
        art.frame = CGRect(x: 0, y: 0, width: size, height: size)
        art.contents = images.art
        art.opacity = mood == .sleeping ? 0.55 : 1
        let spread = size * 0.25
        glow.frame = art.frame.insetBy(dx: -spread, dy: -spread)
        glow.contents = images.glow
        glow.opacity = switch mood {
        case .working: 0.4
        case .guarding: 0.35
        case .happy: 0.5
        default: 0
        }
        eye.bounds = CGRect(x: 0, y: 0, width: size * 0.16, height: size * 0.1)
        eye.position = CGPoint(x: DragonArt.eye.x * size, y: DragonArt.eye.y * size)
        eye.opacity = mood == .sleeping ? 0 : (mood == .idle ? 0.55 : 0.95)
        snore.fontSize = size * 0.22
        snore.frame = CGRect(x: size * 0.82, y: size * 0.1, width: size * 0.25, height: size * 0.28)
        snore.opacity = 0
        flame.emitterPosition = CGPoint(x: DragonArt.mouth.x * size, y: DragonArt.mouth.y * size)
        flame.frame = CGRect(x: 0, y: 0, width: size, height: size)
        flame.emitterCells = nil
        flame.birthRate = 0
        CATransaction.commit()

        guard running else { return }
        let now = CACurrentMediaTime()
        switch mood {
        case .idle, .sleeping:
            let breath = CABasicAnimation(keyPath: "transform.scale")
            breath.fromValue = 1.0
            breath.toValue = 1.015
            breath.duration = 1.6
            breath.autoreverses = true
            breath.repeatCount = .infinity
            breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            art.add(breath, forKey: "breath")
            if mood == .sleeping, size >= 24 {
                let rise = CABasicAnimation(keyPath: "position")
                rise.fromValue = NSValue(point: CGPoint(x: size * 0.92, y: size * 0.3))
                rise.toValue = NSValue(point: CGPoint(x: size * 1.02, y: size * 0.05))
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [0, 0.8, 0]
                fade.keyTimes = [0, 0.5, 1]
                let group = CAAnimationGroup()
                group.animations = [rise, fade]
                group.duration = 2.8
                group.repeatCount = .infinity
                snore.add(group, forKey: "snore")
            }
        case .working:
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.2
            pulse.toValue = 0.6
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glow.add(pulse, forKey: "pulse")
            let eyePulse = pulse.copy() as! CABasicAnimation
            eyePulse.fromValue = 0.7
            eyePulse.toValue = 1
            eye.add(eyePulse, forKey: "pulse")
        case .happy:
            flame.emitterCells = [Self.flameCell(size: size, image: DragonImages.shared.spark)]
            flame.birthRate = 1
            // Bursts: on for 1.3 s out of every 2.4 s.
            let burst = CAKeyframeAnimation(keyPath: "birthRate")
            burst.values = [0, 1, 1, 0, 0]
            burst.keyTimes = [0, 0.08, 0.54, 0.62, 1]
            burst.duration = 2.4
            burst.repeatCount = .infinity
            burst.beginTime = now
            flame.add(burst, forKey: "burst")
        case .guarding:
            // Watching: the eye brightens and dims slowly.
            let watch = CABasicAnimation(keyPath: "opacity")
            watch.fromValue = 0.6
            watch.toValue = 1
            watch.duration = 1.2
            watch.autoreverses = true
            watch.repeatCount = .infinity
            watch.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            eye.add(watch, forKey: "watch")
        }
    }

    private static func flameCell(size: CGFloat, image: CGImage?) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = image
        cell.birthRate = 70
        cell.lifetime = 0.42
        cell.lifetimeRange = 0.12
        cell.velocity = size * 1.3
        cell.velocityRange = size * 0.3
        cell.emissionLongitude = 0
        cell.emissionRange = .pi / 14
        cell.scale = size / 260
        cell.scaleSpeed = size / 220
        cell.alphaSpeed = -2.2
        cell.color = NSColor(hex: 0xFFC46B).cgColor
        cell.redRange = 0.05
        cell.greenRange = 0.25
        cell.greenSpeed = -1.6
        cell.blueSpeed = -1.2
        return cell
    }
}

/// The tinted dragon and its glow, drawn once per size and screen scale.
@MainActor
final class DragonImages {
    static let shared = DragonImages()
    private var cache: [String: (art: CGImage?, glow: CGImage?)] = [:]
    private static let context = CIContext()

    /// A soft round spark for the flame particles.
    lazy var spark: CGImage? = {
        let side = 32
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                                        locations: [0, 1]) else { return nil }
        let c = CGPoint(x: side / 2, y: side / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(side) / 2, options: [])
        return ctx.makeImage()
    }()

    func images(size: CGFloat, scale: CGFloat) -> (art: CGImage?, glow: CGImage?) {
        let key = "\(size)@\(scale)"
        if let hit = cache[key] { return hit }
        let px = Int((size * scale).rounded())
        let art = Self.tinted(px: px)
        var glow: CGImage?
        if let art {
            // The glow is the dragon itself, blurred once, with room around it for the blur to spread.
            let pad = CGFloat(px) * 0.25
            let blurred = CIImage(cgImage: art).transformed(by: CGAffineTransform(translationX: pad, y: pad))
                .applyingGaussianBlur(sigma: Double(px) * 0.06)
            glow = Self.context.createCGImage(blurred, from: CGRect(x: 0, y: 0, width: CGFloat(px) + pad * 2, height: CGFloat(px) + pad * 2))
        }
        cache[key] = (art, glow)
        return (art, glow)
    }

    /// The artwork filled with the red gradient.
    private static func tinted(px: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let mask = DragonArt.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: px, height: px)
        ctx.clip(to: rect, mask: mask)
        let colors = [NSColor(hex: 0xF0454B), NSColor(hex: 0xC8202C), NSColor(hex: 0x8E1119)].map(\.cgColor) as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(px)), end: .zero, options: [])
        }
        return ctx.makeImage()
    }
}
