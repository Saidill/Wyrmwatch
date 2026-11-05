import AppKit
import QuartzCore
import SwiftUI

/// The temporary Wyrmwatch mascot: the Tabler "dragon" icon (MIT, © Paweł Kuna, tabler.io/icons) redrawn as
/// separate Core Animation layers, so each part moves on its own. Used until a Resources/wyrm.riv exists.
///
/// Parts, in the icon's 24 × 24 grid: wing and body (still), and a head that turns on the neck, made of the skull,
/// the crest, the jaw (on its own hinge) and the eye. Silver strokes; red only for the eye while Claude works and
/// for the fire.
struct WyrmArt: NSViewRepresentable {
    var state: WyrmState
    var look: CGPoint?
    var running: Bool

    func makeNSView(context: Context) -> WyrmArtHost { WyrmArtHost() }

    func updateNSView(_ view: WyrmArtHost, context: Context) {
        view.update(state: state, look: look, running: running)
    }
}

final class WyrmArtHost: NSView {
    private let figure = CALayer()
    /// Turns towards the pointer (on a spring); holds the head, which takes each state's pose.
    private let gaze = CALayer()
    private let head = CALayer()
    private let jaw = CAShapeLayer()
    private let eye = CAShapeLayer()
    private let fire = CAEmitterLayer()
    private var current: (WyrmState, Bool)?
    private var lastLook: CGPoint?

    /// Where the head turns (the neck) and where the jaw hinges, in grid units.
    private static let neck = CGPoint(x: 13.2, y: 8.6)
    private static let hinge = CGPoint(x: 15.4, y: 9)
    private static let mouth = CGPoint(x: 21, y: 7.6)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        figure.bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
        figure.isGeometryFlipped = true
        layer?.addSublayer(figure)

        let wing = Self.stroke(Self.wingPath)
        let body = Self.stroke(Self.bodyPath)
        for layer in [gaze, head] {
            layer.bounds = figure.bounds
            layer.anchorPoint = CGPoint(x: Self.neck.x / 24, y: Self.neck.y / 24)
            layer.position = Self.neck
        }
        gaze.addSublayer(head)
        let skull = Self.stroke(Self.skullPath)
        let crest = Self.stroke(Self.crestPath)
        jaw.path = Self.jawPath
        Self.style(jaw)
        jaw.bounds = figure.bounds
        jaw.anchorPoint = CGPoint(x: Self.hinge.x / 24, y: Self.hinge.y / 24)
        jaw.position = Self.hinge
        eye.path = CGPath(ellipseIn: CGRect(x: -0.9, y: -0.9, width: 1.8, height: 1.8), transform: nil)
        eye.position = CGPoint(x: 15.9, y: 5.2)
        eye.fillColor = NSColor(Palette.silver).cgColor
        [skull, crest, jaw, eye].forEach { head.addSublayer($0) }
        fire.emitterPosition = Self.mouth
        fire.emitterShape = .point
        fire.renderMode = .additive
        fire.birthRate = 0
        head.addSublayer(fire)
        [wing, body, gaze].forEach { figure.addSublayer($0) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        figure.position = CGPoint(x: bounds.midX, y: bounds.midY)
        figure.setAffineTransform(CGAffineTransform(scaleX: side / 24, y: side / 24))
        let scale = window?.backingScaleFactor ?? 2
        [figure, gaze, head, jaw, eye].forEach { $0.contentsScale = scale * side / 24 }
        figure.sublayers?.forEach { $0.contentsScale = scale * side / 24 }
        CATransaction.commit()
    }

    func update(state: WyrmState, look: CGPoint?, running: Bool) {
        if current.map({ $0 != (state, running) }) ?? true {
            current = (state, running)
            apply(state, running: running)
        }
        turn(towards: running && (state == .peek || state == .alert) ? look : nil)
    }

    // MARK: States

    private func apply(_ state: WyrmState, running: Bool) {
        [head, jaw, eye, fire].forEach { $0.removeAllAnimations() }
        fire.birthRate = 0
        fire.emitterCells = nil
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        isHidden = state == .hidden
        let red = NSColor(Palette.red).cgColor, silver = NSColor(Palette.silver).cgColor, white = NSColor(Palette.text).cgColor
        switch state {
        case .hidden: break
        case .sleep:
            // Head down, eye shut.
            head.setAffineTransform(CGAffineTransform(rotationAngle: 0.18))
            eye.setAffineTransform(CGAffineTransform(scaleX: 1, y: 0.2))
            eye.fillColor = silver
            jaw.setAffineTransform(.identity)
        case .peek:
            head.setAffineTransform(.identity)
            eye.setAffineTransform(.identity)
            eye.fillColor = silver
            jaw.setAffineTransform(.identity)
        case .working:
            head.setAffineTransform(CGAffineTransform(rotationAngle: -0.05))
            eye.setAffineTransform(.identity)
            eye.fillColor = red
            jaw.setAffineTransform(.identity)
        case .alert:
            // Head up, eye wide and bright: it wants you.
            head.setAffineTransform(CGAffineTransform(rotationAngle: -0.16))
            eye.setAffineTransform(CGAffineTransform(scaleX: 1.3, y: 1.3))
            eye.fillColor = white
            jaw.setAffineTransform(.identity)
        case .done:
            head.setAffineTransform(CGAffineTransform(rotationAngle: -0.1))
            eye.setAffineTransform(.identity)
            eye.fillColor = red
        }
        CATransaction.commit()
        guard running else { return }
        switch state {
        case .peek:
            blink(every: 4.2)
            // Now and then it rises to peek, then settles.
            let peek = CAKeyframeAnimation(keyPath: "transform.translation.y")
            peek.values = [0, 0, -1.2, -1.2, 0]
            peek.keyTimes = [0, 0.7, 0.76, 0.9, 1]
            peek.duration = 9
            peek.repeatCount = .infinity
            head.add(peek, forKey: "peek")
        case .working:
            blink(every: 5)
            // A slight, steady nod while it works.
            let nod = CABasicAnimation(keyPath: "transform.rotation.z")
            nod.fromValue = -0.05
            nod.toValue = 0.02
            nod.duration = 0.9
            nod.autoreverses = true
            nod.repeatCount = .infinity
            nod.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            head.add(nod, forKey: "nod")
        case .alert:
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.45
            pulse.duration = 0.7
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            eye.add(pulse, forKey: "pulse")
        case .done:
            roar()
        case .sleep, .hidden:
            break
        }
    }

    private func blink(every seconds: CFTimeInterval) {
        let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
        blink.values = [1, 1, 0.15, 1]
        blink.keyTimes = [0, NSNumber(value: 1 - 0.18 / seconds), NSNumber(value: 1 - 0.09 / seconds), 1]
        blink.duration = seconds
        blink.repeatCount = .infinity
        eye.add(blink, forKey: "blink")
    }

    /// Jaw opens, a short burst of fire, jaw closes (once).
    private func roar() {
        let open = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        open.values = [0, 0.45, 0.45, 0]
        open.keyTimes = [0, 0.15, 0.75, 1]
        open.duration = 1.6
        jaw.add(open, forKey: "roar")
        let cell = CAEmitterCell()
        cell.contents = WyrmArtHost.spark
        cell.birthRate = 90
        cell.lifetime = 0.35
        cell.velocity = 14
        cell.velocityRange = 3
        cell.emissionLongitude = 0.2
        cell.emissionRange = .pi / 14
        cell.scale = 0.012
        cell.scaleSpeed = 0.03
        cell.alphaSpeed = -2.6
        cell.color = NSColor(Palette.red).cgColor
        fire.emitterCells = [cell]
        let burst = CAKeyframeAnimation(keyPath: "birthRate")
        burst.values = [0, 0, 1, 1, 0]
        burst.keyTimes = [0, 0.12, 0.18, 0.62, 0.7]
        burst.duration = 1.6
        burst.fillMode = .forwards
        burst.isRemovedOnCompletion = false
        fire.birthRate = 1
        fire.add(burst, forKey: "burst")
    }

    /// Tilts the head towards the pointer on a spring (up and down) and slides the eye a touch (left and right).
    private func turn(towards look: CGPoint?) {
        let target = look ?? .zero
        if let lastLook, abs(lastLook.x - target.x) + abs(lastLook.y - target.y) < 0.02 { return }
        lastLook = target
        let tilt = Double(max(-1, min(1, target.y))) * 0.22
        let spring = CASpringAnimation(keyPath: "transform.rotation.z")
        spring.damping = 14
        spring.stiffness = 160
        spring.fromValue = gaze.presentation()?.value(forKeyPath: "transform.rotation.z") ?? 0
        spring.toValue = tilt
        spring.duration = spring.settlingDuration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gaze.setValue(tilt, forKeyPath: "transform.rotation.z")
        CATransaction.commit()
        gaze.add(spring, forKey: "look")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        eye.position = CGPoint(x: 15.9 + max(-1, min(1, target.x)) * 0.5, y: 5.2)
        CATransaction.commit()
    }

    // MARK: Drawing

    private static func stroke(_ path: CGPath) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path
        style(layer)
        layer.bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
        layer.position = CGPoint(x: 12, y: 12)
        return layer
    }

    private static func style(_ layer: CAShapeLayer) {
        layer.fillColor = nil
        layer.strokeColor = NSColor(Palette.silver).cgColor
        layer.lineWidth = 2
        layer.lineCap = .round
        layer.lineJoin = .round
    }

    // The Tabler "dragon" paths, in absolute coordinates; the head path is split into skull and jaw.
    private static let wingPath: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 10.706, y: 8.849))
        p.addLine(to: CGPoint(x: 5, y: 5.548))
        p.addLine(to: CGPoint(x: 3, y: 12))
        p.addLine(to: CGPoint(x: 6.5, y: 10.027))
        p.addLine(to: CGPoint(x: 7, y: 13))
        p.addLine(to: CGPoint(x: 10.555, y: 11.615))
        return p
    }()

    private static let bodyPath: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 15, y: 9))
        p.addCurve(to: CGPoint(x: 19, y: 16), control1: CGPoint(x: 15, y: 12.5), control2: CGPoint(x: 19, y: 12))
        p.addCurve(to: CGPoint(x: 13.5, y: 21), control1: CGPoint(x: 19, y: 19), control2: CGPoint(x: 16, y: 21))
        p.addCurve(to: CGPoint(x: 7, y: 16), control1: CGPoint(x: 11, y: 21), control2: CGPoint(x: 7.5, y: 20.5))
        p.addCurve(to: CGPoint(x: 14.5, y: 17), control1: CGPoint(x: 9, y: 18), control2: CGPoint(x: 13.592, y: 19.043))
        p.addCurve(to: CGPoint(x: 10.5, y: 10.5), control1: CGPoint(x: 15.594, y: 14.539), control2: CGPoint(x: 10.5, y: 13.541))
        p.addCurve(to: CGPoint(x: 12.3, y: 7.3), control1: CGPoint(x: 10.5, y: 8.438), control2: CGPoint(x: 11, y: 8))
        return p
    }()

    /// The round back of the head (three quarters of a circle around 15,6) and the top of the snout.
    private static let skullPath: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 21, y: 6))
        p.addLine(to: CGPoint(x: 18, y: 6))
        p.addArc(center: CGPoint(x: 15, y: 6), radius: 3, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        return p
    }()

    /// The lower jaw: along the bottom of the snout to its tip.
    private static let jawPath: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 15, y: 9))
        p.addLine(to: CGPoint(x: 20, y: 9))
        p.addLine(to: CGPoint(x: 21, y: 6))
        return p
    }()

    private static let crestPath: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 15, y: 3))
        p.addLine(to: CGPoint(x: 7, y: 3))
        p.addLine(to: CGPoint(x: 12, y: 6))
        return p
    }()

    /// A soft round spark for the flame.
    static let spark: CGImage? = {
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
}
