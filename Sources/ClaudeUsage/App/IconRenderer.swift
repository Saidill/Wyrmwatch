import AppKit
import SwiftUI

/// Draws the app icon (the red dragon on a black tile) at 1024 × 1024 and quits.
/// Used by scripts/build-app.sh: <exe> --render-icon <out.png>
@MainActor
enum IconRenderer {
    static func renderIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-icon"), args.count > i + 1 else { return }
        let tile = RoundedRectangle(cornerRadius: 185, style: .continuous)
        let icon = ZStack {
            tile.fill(LinearGradient(colors: [Color(hex: 0x1C1D20), .black], startPoint: .top, endPoint: .bottom))
                .overlay(tile.strokeBorder(Color(hex: 0x2A2B2F), lineWidth: 4))
                .frame(width: 824, height: 824)
            DragonView(mood: .guarding, size: 560, at: 1000)
                .offset(x: -10, y: 10)
        }
        .frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: icon)
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { exit(1) }
        do { try png.write(to: URL(fileURLWithPath: args[i + 1])) } catch { exit(1) }
        exit(0)
    }
}
