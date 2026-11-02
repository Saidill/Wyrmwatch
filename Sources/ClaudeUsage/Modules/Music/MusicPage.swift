import SwiftUI

/// The Music page: the cover (120 pt) and the playlist beside it, title | length per row,
/// the playing song in white and the rest in grey. Clicking a song plays it.
struct MusicPage: View {
    @ObservedObject var bridge: MusicBridge
    @Environment(\.animationsPaused) private var paused

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            CoverArt(image: bridge.artwork, id: bridge.track?.id ?? "", size: 120, radius: 16)
                .probe("music.cover")
            Group {
                if bridge.permissionDenied {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Allow this app to control Music to see what's playing.")
                            .font(.app(12))
                            .foregroundStyle(Palette.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        NotchChip(title: "Give access") { bridge.openPermissionSettings() }
                            .frame(width: 100)
                    }
                } else if bridge.track == nil {
                    NotchChip(title: "Play music") { bridge.startMusic() }
                        .frame(width: 120)
                } else {
                    playlist
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .probe("music.list")
        }
        .frame(height: 120)
        .onAppear {
            bridge.refreshAll()
            bridge.loadPlaylist()
        }
        .onChange(of: bridge.track?.id) { _, _ in if !paused { bridge.loadPlaylist() } }
    }

    @ViewBuilder private var playlist: some View {
        if let list = bridge.playlist {
            if list.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No song list for this song")
                        .font(.app(12, .medium))
                        .foregroundStyle(Palette.text)
                    Text("It's streaming from Apple Music, and Music only shares the song list for playlists and albums in your library.")
                        .font(.app(11))
                        .foregroundStyle(Palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(list) { item in
                                SongRow(item: item, current: bridge.currentIndex == item.index - 1) { bridge.play(item) }
                                    .id(item.index)
                            }
                        }
                    }
                    .onAppear { center(proxy) }
                    .onChange(of: bridge.currentIndex) { _, _ in withAnimation(Motion.smooth) { center(proxy) } }
                }
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func center(_ proxy: ScrollViewProxy) {
        guard let index = bridge.currentIndex else { return }
        proxy.scrollTo(index + 1, anchor: .center)
    }
}

private struct SongRow: View {
    let item: PlaylistTrack
    let current: Bool
    let play: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(item.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(SeekRow.format(item.duration))
                .monospacedDigit()
                .fixedSize()
        }
        .font(.app(12, current ? .semibold : .regular))
        .foregroundStyle(current ? Palette.text : (hovering ? Palette.text2.opacity(1) : Palette.text2))
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? Palette.button : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: play)
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
    }
}
