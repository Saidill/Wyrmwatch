import SwiftUI

/// The Music page: the cover in its own 150 × 150 card, an info card beside it (title, artist · album, progress,
/// controls), and the library playlist underneath when Music shares one. Clicking a song plays it.
struct MusicPage: View {
    @ObservedObject var bridge: MusicBridge
    var coverSpace: Namespace.ID?
    @Environment(\.animationsPaused) private var paused

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                CoverArt(image: bridge.artwork, id: bridge.track?.id ?? "", size: 150, radius: Radius.card)
                    .modifier(MatchedCover(space: coverSpace))
                    .frame(width: 152, height: 152)
                    .probe("music.cover")
                    .cardAppear(0)
                info
                    .frame(height: 152)
                    .probe("music.info")
                    .cardAppear(1)
            }
            if let list = bridge.playlist, !list.isEmpty {
                playlist(list)
                    .frame(height: 120)
                    .probe("music.list")
                    .cardAppear(2)
            }
        }
        .onAppear {
            bridge.refreshAll()
            bridge.loadPlaylist()
        }
        .onChange(of: bridge.track?.id) { _, _ in if !paused { bridge.loadPlaylist() } }
    }

    @ViewBuilder private var info: some View {
        Group {
            if bridge.permissionDenied {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Allow this app to control Music to see what's playing.")
                        .font(.app(13))
                        .foregroundStyle(Palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    CardButton(title: "Give access") { bridge.openPermissionSettings() }
                        .frame(width: 120)
                }
            } else if let track = bridge.track {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.app(16, .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text([track.artist, bridge.isMusicApp ? track.album : bridge.sourceName].filter { !$0.isEmpty }
                        .joined(separator: " · ")).cardLabel()
                    Spacer(minLength: 6)
                    SeekRow(bridge: bridge)
                    Spacer(minLength: 6)
                    HStack(spacing: 8) {
                        if bridge.isMusicApp {
                            CardButton(systemName: "shuffle", active: bridge.shuffle, help: "Shuffle") { bridge.toggleShuffle() }
                        }
                        CardButton(systemName: "backward.fill", help: "Previous") { bridge.previous() }
                        CardButton(systemName: bridge.isPlaying ? "pause.fill" : "play.fill", active: true,
                                   help: bridge.isPlaying ? "Pause" : "Play") { bridge.playPause() }
                        CardButton(systemName: "forward.fill", help: "Next") { bridge.next() }
                        if bridge.isMusicApp {
                            CardButton(systemName: bridge.repeatMode == .one ? "repeat.1" : "repeat", active: bridge.repeatMode != .off,
                                       help: "Repeat") { bridge.cycleRepeat() }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(MusicBridge.isRunning ? "Nothing playing" : "Music isn't open").cardLabel()
                    Spacer(minLength: 0)
                    CardButton(systemName: "play.fill", title: "Play music", active: true, height: 32) { bridge.startMusic() }
                        .frame(width: 152)
                }
            }
        }
        .notchCard()
    }

    private func playlist(_ list: [PlaylistTrack]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(list) { item in
                        SongRow(item: item, current: bridge.currentIndex == item.index - 1) { bridge.play(item) }
                            .id(item.index)
                    }
                }
                .padding(8)
            }
            .background(Radius.shape(Radius.card).fill(Palette.card))
            .clipShape(Radius.shape(Radius.card))
            .onAppear { center(proxy) }
            .onChange(of: bridge.currentIndex) { _, _ in withAnimation(Motion.smooth) { center(proxy) } }
        }
    }

    private func center(_ proxy: ScrollViewProxy) {
        guard let index = bridge.currentIndex else { return }
        proxy.scrollTo(index + 1, anchor: .center)
    }
}

/// Title | length; the playing song in white, the rest in grey.
private struct SongRow: View {
    let item: PlaylistTrack
    let current: Bool
    let play: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(item.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(SeekRow.format(item.duration))
                .monospacedDigit()
                .fixedSize()
        }
        .font(.app(12, current ? .semibold : .regular))
        .foregroundStyle(current ? Palette.text : Palette.text2)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Radius.shape(Radius.button).fill(hovering ? Palette.button : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: play)
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
    }
}
