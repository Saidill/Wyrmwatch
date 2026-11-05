import AppKit

/// Album covers by track, each with its dominant colour worked out once.
@MainActor
final class ArtworkCache {
    struct Entry {
        let image: NSImage
        let accent: NSColor?
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private let limit = 40

    subscript(id: String) -> Entry? { entries[id] }

    func store(_ image: NSImage, for id: String) -> Entry {
        let entry = Entry(image: image, accent: Self.dominantColor(of: image))
        if entries[id] == nil { order.append(id) }
        entries[id] = entry
        if order.count > limit { entries[order.removeFirst()] = nil }
        return entry
    }

    /// Shrinks the cover to 8×8 and averages it, leaning towards the more colourful pixels.
    static func dominantColor(of image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        var r = 0.0, g = 0.0, b = 0.0, total = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let pr = Double(pixels[i]) / 255, pg = Double(pixels[i + 1]) / 255, pb = Double(pixels[i + 2]) / 255
            let saturation = max(pr, pg, pb) - min(pr, pg, pb)
            let weight = 0.15 + saturation
            r += pr * weight; g += pg * weight; b += pb * weight; total += weight
        }
        guard total > 0 else { return nil }
        return NSColor(srgbRed: r / total, green: g / total, blue: b / total, alpha: 1)
    }
}
