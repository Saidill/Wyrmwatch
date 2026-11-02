import SwiftUI

/// The Music page: the cover (120 pt) and the playlist beside it, title | length per row,
/// the playing song in white and the rest in grey. Clicking a song plays it.
struct MusicPage: View {
    @ObservedObject var bridge: MusicBridge
    @ObservedObject private var albums = AppModels.music.albums
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
            if bridge.playlist?.isEmpty == true, let track = bridge.track { albums.lookUp(track) }
        }
        .onChange(of: bridge.track?.id) { _, _ in if !paused { bridge.loadPlaylist() } }
        // Streamed song with no list from Music: find its album instead (in the background).
        .onChange(of: bridge.playlist?.isEmpty) { _, empty in
            if empty == true, let track = bridge.track { albums.lookUp(track) }
        }
        .onChange(of: bridge.track?.album) { _, _ in
            if bridge.playlist?.isEmpty == true, let track = bridge.track { albums.lookUp(track) }
        }
    }

    @ViewBuilder private var playlist: some View {
        if let list = bridge.playlist {
            if list.isEmpty {
                AlbumList(lookup: AppModels.music.albums, bridge: bridge)
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

/// "From this album": the streamed song's album from Apple's catalogue, the playing song in white.
private struct AlbumList: View {
    @ObservedObject var lookup: AlbumLookup
    @ObservedObject var bridge: MusicBridge

    var body: some View {
        switch lookup.state {
        case .found(let album, let tracks):
            VStack(alignment: .leading, spacing: 4) {
                Text("From \(album)")
                    .font(.app(10.5, .medium))
                    .foregroundStyle(Palette.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(tracks) { track in
                                let current = Self.matches(track.title, bridge.track?.title ?? "")
                                SongRow(item: PlaylistTrack(index: track.number, title: track.title, artist: "", duration: track.duration),
                                        current: current) { lookup.open(track) }
                                    .id(track.number)
                            }
                        }
                    }
                    .onAppear { center(proxy, tracks) }
                    .onChange(of: bridge.track?.title) { _, _ in withAnimation(Motion.smooth) { center(proxy, tracks) } }
                }
            }
        case .loading:
            HStack(spacing: 8) {
                LayerWorkingDots(running: true, color: NSColor(Palette.text2))
                    .frame(width: WorkingDotsHost.size.width, height: WorkingDotsHost.size.height)
                Text("Finding the album…").font(.app(11.5)).foregroundStyle(Palette.text2)
            }
            .padding(.horizontal, 8)
        case .idle, .notFound:
            VStack(alignment: .leading, spacing: 4) {
                Text("No song list for this song")
                    .font(.app(12, .medium))
                    .foregroundStyle(Palette.text)
                Text(lookup.enabled
                     ? "It's streaming from Apple Music and its album wasn't found."
                     : "It's streaming from Apple Music. Turn on album look-up in Settings → Music to see its album.")
                    .font(.app(11))
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func center(_ proxy: ScrollViewProxy, _ tracks: [AlbumTrack]) {
        guard let hit = tracks.first(where: { Self.matches($0.title, bridge.track?.title ?? "") }) else { return }
        proxy.scrollTo(hit.number, anchor: .center)
    }

    /// The same song, ignoring case and bracketed extras such as "(Remastered)".
    static func matches(_ a: String, _ b: String) -> Bool {
        func plain(_ s: String) -> String {
            s.lowercased().replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        return !a.isEmpty && plain(a) == plain(b)
    }
}
