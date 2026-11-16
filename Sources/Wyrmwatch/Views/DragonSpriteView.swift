import AppKit
import QuartzCore
import SwiftUI

/// The mascot's sprite sheets: "Dragon - Fully Animated" by Cethiel (CC0, opengameart.org), packed by
/// scripts/make-dragon-atlas.py into one grid of frames per animation (Resources/Dragon + dragon.json).
final class DragonAtlas {
    struct Animation: Decodable {
        let file: String
        let columns: Int
        let rows: Int
        let frames: Int
        let fps: Double
        let loop: Bool
    }

    private struct Manifest: Decodable {
        let frameWidth: CGFloat
        let frameHeight: CGFloat
        let animations: [String: Animation]
    }

    /// nil when the app was built without the sprites; the mascot's slot is then empty.
    static let shared = DragonAtlas()

    /// Width over height of one frame.
    let aspect: CGFloat
    let animations: [String: Animation]
    private let folder: URL
    private var images: [String: CGImage] = [:]

    private init?() {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Dragon"),
              let data = try? Data(contentsOf: folder.appendingPathComponent("dragon.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data), manifest.frameHeight > 0 else { return nil }
        self.folder = folder
        aspect = manifest.frameWidth / manifest.frameHeight
        animations = manifest.animations
    }

    /// The sheet of one animation, decoded the first time it plays.
    func image(_ name: String) -> CGImage? {
        if let image = images[name] { return image }
        guard let animation = animations[name],
              let source = CGImageSourceCreateWithURL(folder.appendingPathComponent(animation.file) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        images[name] = image
        return image
    }

    /// Where each frame sits in its sheet, in unit coordinates. Frames run left to right, top row first; a layer's
    /// `contentsRect` counts rows from the bottom on macOS, hence the flip.
    func rects(_ animation: Animation) -> [CGRect] {
        let w = 1 / CGFloat(animation.columns), h = 1 / CGFloat(animation.rows)
        return (0..<animation.frames).map {
            CGRect(x: CGFloat($0 % animation.columns) * w, y: 1 - CGFloat($0 / animation.columns + 1) * h, width: w, height: h)
        }
    }
}

/// The dragon, playing the animation of its state. One layer; frames change through a keyframe animation on
/// `contentsRect`, which the render server runs (no SwiftUI or AppKit redraw per frame).
struct DragonSpriteView: NSViewRepresentable {
    var state: WyrmState
    /// false while the notch is closed or Reduce Motion is on: one still frame, no animation at all.
    var running: Bool

    func makeNSView(context: Context) -> DragonSpriteHost { DragonSpriteHost() }

    func updateNSView(_ view: DragonSpriteHost, context: Context) {
        view.update(state: state, running: running)
    }
}

final class DragonSpriteHost: NSView {
    private let sprite = CALayer()
    private let atlas = DragonAtlas.shared
    private var shown: (state: WyrmState, running: Bool)?
    /// The sheet on the layer.
    private var sheet: String?
    private var next: DispatchWorkItem?

    /// For the self-test: the sheet on the layer, and whether frames (or the sleeping breath) are playing.
    var sheetForTesting: String? { sheet }
    var isAnimatingForTesting: Bool { !(sprite.animationKeys() ?? []).isEmpty }

    private static let frames = "frames"
    private static let breath = "breath"
    /// How long one animation blends into the next.
    private static let crossfade: CFTimeInterval = 0.15

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        // Nothing here animates by itself: frames and the crossfade are added explicitly.
        sprite.actions = ["contents": NSNull(), "contentsRect": NSNull(), "bounds": NSNull(), "position": NSNull()]
        sprite.contentsGravity = .resize
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0) // breathes from the ground up
        layer?.addSublayer(sprite)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        guard let atlas else { return }
        // As large as fits, centred, standing on the bottom edge.
        let size = bounds.width / max(bounds.height, 1) > atlas.aspect
            ? CGSize(width: bounds.height * atlas.aspect, height: bounds.height)
            : CGSize(width: bounds.width, height: bounds.width / atlas.aspect)
        sprite.bounds = CGRect(origin: .zero, size: size)
        sprite.position = CGPoint(x: bounds.midX, y: bounds.midY - size.height / 2)
    }

    func update(state: WyrmState, running: Bool) {
        if let shown, shown == (state, running) { return }
        let before = shown
        shown = (state, running)
        next?.cancel()
        sprite.removeAnimation(forKey: Self.breath)
        guard atlas != nil, state != .hidden else {
            sprite.removeAllAnimations()
            sprite.contents = nil
            sheet = nil
            return
        }
        guard running else { hold(state); return }
        let wasAsleep = before?.state == .sleep
        switch state {
        case .sleep:
            // Lie down (straight to the last frame when it was already lying there), then breathe.
            if wasAsleep || before == nil { hold(.sleep); breathe() } else { play("sleep") { [weak self] in self?.breathe() } }
        case .done:
            // Once, then back to watching.
            play("done") { [weak self] in self?.play("idle") }
        default:
            let name = Self.loop(for: state)
            if wasAsleep { play("sleep", reversed: true, speed: 1.6) { [weak self] in self?.play(name) } } else { play(name) }
        }
    }

    private static func loop(for state: WyrmState) -> String {
        switch state {
        case .working: return "working"
        case .alert: return "alert"
        default: return "idle"
        }
    }

    /// Plays one sheet: forever when it loops, else once, holding its last frame and then calling `then`.
    private func play(_ name: String, reversed: Bool = false, speed: Float = 1, then: (() -> Void)? = nil) {
        guard let atlas, let animation = atlas.animations[name], let image = atlas.image(name) else { return }
        var rects = atlas.rects(animation)
        if reversed { rects.reverse() }
        guard let first = rects.first, let last = rects.last else { return }
        show(image, name, rect: animation.loop ? first : last, fade: true)
        let frames = CAKeyframeAnimation(keyPath: "contentsRect")
        frames.values = rects.map { NSValue(rect: $0) }
        frames.keyTimes = (0...rects.count).map { NSNumber(value: Double($0) / Double(rects.count)) }
        frames.calculationMode = .discrete
        frames.duration = Double(rects.count) / animation.fps
        frames.speed = speed
        frames.repeatCount = animation.loop ? .infinity : 1
        sprite.add(frames, forKey: Self.frames)
        guard !animation.loop, let then else { return }
        let work = DispatchWorkItem(block: then)
        next = work
        DispatchQueue.main.asyncAfter(deadline: .now() + frames.duration / Double(speed), execute: work)
    }

    /// One still frame of a state, with nothing moving.
    private func hold(_ state: WyrmState) {
        let name: String
        switch state {
        case .sleep: name = "sleep"
        case .done: name = "done"
        default: name = Self.loop(for: state)
        }
        guard let atlas, let animation = atlas.animations[name], let image = atlas.image(name) else { return }
        let rects = atlas.rects(animation)
        // Asleep: lying down (the last frame). Done: reared up (a third of the way in). Otherwise the first frame.
        let index = state == .sleep ? rects.count - 1 : state == .done ? rects.count / 3 : 0
        sprite.removeAllAnimations()
        show(image, name, rect: rects[index], fade: false)
    }

    private func show(_ image: CGImage, _ name: String, rect: CGRect, fade: Bool) {
        sprite.removeAnimation(forKey: Self.frames)
        if fade, sheet != nil, sheet != name || sprite.contentsRect != rect {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = Self.crossfade
            sprite.add(transition, forKey: "crossfade")
        }
        sprite.contents = image
        sprite.contentsRect = rect
        sheet = name
    }

    /// Asleep: a slow rise and fall.
    private func breathe() {
        guard shown?.state == .sleep, shown?.running == true else { return }
        let breath = CABasicAnimation(keyPath: "transform.scale.y")
        breath.fromValue = 1
        breath.toValue = 1.05
        breath.duration = 2.2
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sprite.add(breath, forKey: Self.breath)
    }
}
