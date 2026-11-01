import SwiftUI

/// The Music page, three columns across the open notch: the cover | title, artist · album, progress and
/// controls | the playlist, scrolling on its own with the playing song in blue.
struct MusicPage: View {
    @ObservedObject var bridge: MusicBridge
    @Environment(\.animationsPaused) private var paused

    var body: some View {
        Group {
            if bridge.permissionDenied {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Allow this app to control Music to see what's playing.")
                        .font(.app(12))
                        .foregroundStyle(Palette.text2)
                    Button("Give access") { bridge.openPermissionSettings() }
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else if let track = bridge.track {
                HStack(alignment: .top, spacing: 16) {
                    CoverArt(image: bridge.artwork, id: track.id, size: 120, radius: 14)
                    details(track)
                        .frame(width: 214, height: 120, alignment: .topLeading)
                    PlaylistPanel(bridge: bridge, height: 128)
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 14) {
                    CoverArt(image: nil, id: "", size: 120, radius: 14)
                    Text(MusicBridge.isRunning ? "Nothing playing" : "Music isn't open")
                        .font(.app(13))
                        .foregroundStyle(Palette.text3)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            bridge.refreshAll()
            bridge.loadPlaylist()
        }
        .onChange(of: bridge.track?.id) { _, _ in if !paused { bridge.loadPlaylist() } }
    }

    private func details(_ track: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.title)
                .font(.app(14, .semibold))
                .foregroundStyle(Palette.text)
                .lineLimit(2)
            Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.app(11.5))
                .foregroundStyle(Palette.text3)
                .lineLimit(1)
            Spacer(minLength: 4)
            Scrubber(bridge: bridge)
            HStack(spacing: 4) {
                toggle("shuffle", on: bridge.shuffle, help: "Shuffle") { bridge.toggleShuffle() }
                Spacer(minLength: 0)
                IconButton(systemName: "backward.fill", help: "Previous") { bridge.previous() }
                IconButton(systemName: bridge.isPlaying ? "pause.fill" : "play.fill",
                           help: bridge.isPlaying ? "Pause" : "Play") { bridge.playPause() }
                IconButton(systemName: "forward.fill", help: "Next") { bridge.next() }
                Spacer(minLength: 0)
                toggle(bridge.repeatMode == .one ? "repeat.1" : "repeat", on: bridge.repeatMode != .off,
                       help: "Repeat") { bridge.cycleRepeat() }
            }
        }
    }

    private func toggle(_ symbol: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? Palette.blue : Palette.text3)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
