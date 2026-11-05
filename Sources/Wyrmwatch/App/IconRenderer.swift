import AppKit
import SwiftUI

/// Draws the app icon (a notch with a red dot, on a dark tile) at 1024 × 1024 and quits.
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
            // The notch, with the red "watching" dot beside it.
            UnevenRoundedRectangle(bottomLeadingRadius: 90, bottomTrailingRadius: 90, style: .continuous)
                .fill(Color.black)
                .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 90, bottomTrailingRadius: 90, style: .continuous)
                    .strokeBorder(Color(hex: 0x3A3A3C), lineWidth: 6))
                .frame(width: 560, height: 230)
                .offset(y: -297)
            Circle().fill(Color(hex: 0xE5322B)).frame(width: 64, height: 64).offset(x: 0, y: -297)
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
