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
                StreamList(bridge: bridge, albums: AppModels.music.albums, top: AppModels.music.topSongs)
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

/// A streamed song's list. Music.app doesn't say where the song came from, so the list is guessed from the song
/// before it (same album: the album; same artist: their top songs; another artist: what has played) and can be
/// switched by hand. Only the list on show is fetched, in the background, once per album or artist.
private struct StreamList: View {
    @ObservedObject var bridge: MusicBridge
    @ObservedObject var albums: AlbumLookup
    @ObservedObject var top: AlbumLookup
    /// A list picked by hand, and the guess it overrode (a new guess drops it).
    @State private var picked: (context: StreamContext, over: StreamContext)?

    private var inferred: StreamContext {
        guard let track = bridge.track else { return .album }
        return StreamContext.infer(current: track, previous: bridge.history.dropFirst().first)
    }

    private var context: StreamContext {
        if let picked, picked.over == inferred { return picked.context }
        return inferred
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(StreamContext.allCases) { option in
                    Text(option.title)
                        .font(.app(10.5, .medium))
                        .foregroundStyle(context == option ? Palette.text : Palette.text2)
                        .padding(.horizontal, 9)
                        .frame(height: 20)
                        .background(Capsule().fill(context == option ? Palette.track : .clear))
                        .contentShape(Capsule())
                        .onTapGesture { withAnimation(Motion.quick) { picked = (option, inferred) } }
                }
                Spacer(minLength: 0)
            }
            .probe("music.context")
            Group {
                switch context {
                case .album: CatalogList(lookup: albums, header: { "From \($0)" }, bridge: bridge)
                case .topSongs: CatalogList(lookup: top, header: { "Top songs by \($0)" }, bridge: bridge)
                case .recent: recent
                }
            }
            .id(context)
            .transition(.opacity.animation(Motion.page))
            .probe("music.album")
        }
        .onAppear(perform: fetch)
        .onChange(of: context) { _, _ in fetch() }
        .onChange(of: bridge.track?.id) { _, _ in fetch() }
    }

    /// Asks for the list on show only.
    private func fetch() {
        guard let track = bridge.track else { return }
        switch context {
        case .album: albums.lookUp(track)
        case .topSongs: top.lookUp(track)
        case .recent: break
        }
    }

    /// Songs played this session, the current one first.
    private var recent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(bridge.history.enumerated()), id: \.offset) { i, song in
                    SongRow(item: PlaylistTrack(index: i + 1, title: song.artist.isEmpty ? song.title : "\(song.title) — \(song.artist)",
                                                artist: "", duration: song.duration),
                            current: i == 0) {}
                        .help("Played this session")
                }
            }
        }
    }
}

/// An album or an artist's top songs from Apple's catalogue, the playing song in white.
private struct CatalogList: View {
    @ObservedObject var lookup: AlbumLookup
    let header: (String) -> String
    @ObservedObject var bridge: MusicBridge

    var body: some View {
        switch lookup.state {
        case .found(let name, let tracks):
            VStack(alignment: .leading, spacing: 2) {
                Text(header(name))
                    .font(.app(10.5, .medium))
                    .foregroundStyle(Palette.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(tracks) { track in
                                SongRow(item: PlaylistTrack(index: track.number, title: track.title, artist: "", duration: track.duration),
                                        current: Self.matches(track.title, bridge.track?.title ?? "")) { lookup.open(track) }
                                    .id(track.number)
                            }
                        }
                    }
                    // Rows half out of view fade into the edges instead of being sliced.
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                                 .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .onAppear { center(proxy, tracks) }
                    .onChange(of: bridge.track?.title) { _, _ in withAnimation(Motion.smooth) { center(proxy, tracks) } }
                }
            }
        case .loading:
            HStack(spacing: 8) {
                LayerWorkingDots(running: true, color: NSColor(Palette.text2))
                    .frame(width: WorkingDotsHost.size.width, height: WorkingDotsHost.size.height)
                Text("Finding the songs…").font(.app(11.5)).foregroundStyle(Palette.text2)
            }
            .padding(.horizontal, 8)
        case .idle, .notFound:
            VStack(alignment: .leading, spacing: 4) {
                Text("No song list for this song")
                    .font(.app(12, .medium))
                    .foregroundStyle(Palette.text)
                Text(lookup.enabled
                     ? "It's streaming from Apple Music and nothing was found for it."
                     : "It's streaming from Apple Music. Turn on look-up in Settings → Music to see its songs.")
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
        !a.isEmpty && AlbumLookup.plain(a) == AlbumLookup.plain(b)
    }
}
