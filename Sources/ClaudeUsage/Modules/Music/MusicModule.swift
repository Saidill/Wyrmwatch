import Combine
import SwiftUI

/// Apple Music in the notch: cover and a little visualizer while playing, a short pop when the song changes,
/// and a Now Playing card with controls and the playlist.
@MainActor
final class MusicModule: NotchModule {
    let id = "music"
    let bridge: MusicBridge
    /// For a streamed song's song list: its album, or the artist's top songs.
    let albums: AlbumLookup
    let topSongs: AlbumLookup
    let pops: AsyncStream<NotchPop>
    private let popSink: AsyncStream<NotchPop>.Continuation
    private var subscriptions: Set<AnyCancellable> = []

    enum Keys {
        static let popOnChange = "music.popOnChange"
        static let listOnHover = "music.listOnHover"
    }

    init(bridge: MusicBridge, pomodoro: PomodoroTimer) {
        self.bridge = bridge
        albums = AlbumLookup(kind: .album, offline: SelfTest.isRequested || Perf.isRequested)
        topSongs = AlbumLookup(kind: .topSongs, offline: SelfTest.isRequested || Perf.isRequested)
        (pops, popSink) = AsyncStream.makeStream(of: NotchPop.self)
        UserDefaults.standard.register(defaults: [Keys.popOnChange: true, Keys.listOnHover: true])
        bridge.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        bridge.trackChanged.sink { [weak self] track in self?.songChanged(track) }.store(in: &subscriptions)

        // Optional: music plays while focusing and pauses for breaks.
        let sync = { UserDefaults.standard.bool(forKey: PomodoroTimer.Keys.musicSync) }
        pomodoro.starts.sink { [weak bridge] phase in
            guard sync() else { return }
            phase.isBreak ? bridge?.pause() : bridge?.play()
        }.store(in: &subscriptions)
        pomodoro.events.sink { [weak bridge] event in
            if sync(), event == .focusDone { bridge?.pause() }
        }.store(in: &subscriptions)
    }

    var livePriority: Int? { bridge.isPlaying && bridge.track != nil ? 4 : nil }

    func liveLeading() -> AnyView { AnyView(MusicLiveCover(bridge: bridge)) }
    func liveTrailing() -> AnyView { AnyView(MusicVisualizer(playing: bridge.isPlaying)) }
    func expandedCard() -> AnyView? { AnyView(NowPlayingCard(bridge: bridge)) }
    func setVisible(_ visible: Bool) {}

    private func songChanged(_ track: NowPlaying) {
        guard UserDefaults.standard.bool(forKey: Keys.popOnChange) else { return }
        popSink.yield(NotchPop(kind: .music, duration: 2.5) { SongPop(bridge: self.bridge) })
    }
}

// MARK: - Pieces

/// Album cover with rounded corners, or a note on glass when there's none. A new cover crossfades in.
struct CoverArt: View {
    let image: NSImage?
    let id: String
    var size: CGFloat
    var radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                shape.fill(Palette.glass)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(Palette.text3)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.line, lineWidth: 0.5))
        .id(id + (image == nil ? "-none" : ""))
        .transition(.opacity)
        .animation(Motion.smooth, value: id)
    }
}

private struct MusicLiveCover: View {
    @ObservedObject var bridge: MusicBridge
    @Environment(\.coverSpace) private var coverSpace

    var body: some View {
        CoverArt(image: bridge.artwork, id: bridge.track?.id ?? "", size: 18, radius: 5)
            .modifier(MatchedCover(space: coverSpace))
    }
}

/// Four bars bouncing to an imagined beat. Decorative only: reading real audio would need screen-recording
/// permission. Still when paused or out of sight.
struct MusicVisualizer: View {
    let playing: Bool
    var color: Color = Palette.silver
    @Environment(\.animationsPaused) private var paused

    var body: some View {
        // Core Animation layers: the bounce costs the app nothing per frame.
        LayerVisualizer(running: playing && !paused, color: NSColor(color))
            .frame(width: VisualizerHost.size.width, height: VisualizerHost.size.height)
            .allowsHitTesting(false)
    }
}

/// Song changed: cover, title and artist for a moment.
private struct SongPop: View {
    @ObservedObject var bridge: MusicBridge

    var body: some View {
        HStack(spacing: 12) {
            CoverArt(image: bridge.artwork, id: bridge.track?.id ?? "", size: 44, radius: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(bridge.track?.title ?? "")
                    .font(.app(13, .medium))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(bridge.track?.artist ?? "")
                    .font(.app(11))
                    .foregroundStyle(Palette.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            MusicVisualizer(playing: bridge.isPlaying)
        }
        .padding(.top, -4)
        .contentShape(Rectangle())
        .onTapGesture { NotchWindowController.shared.expand() }
    }
}

// MARK: - Card

/// Now Playing in the expanded notch. Resting the pointer on it (or the list button) slides in the playlist.
struct NowPlayingCard: View {
    @ObservedObject var bridge: MusicBridge
    @AppStorage(MusicModule.Keys.listOnHover) private var listOnHover = true
    @Environment(\.animationsPaused) private var paused
    @Environment(\.reduceMotion) private var reduceMotion
    @State private var showList = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(showList ? "Playlist" : "Now playing") {
                if bridge.track != nil {
                    Button { toggleList(!showList) } label: {
                        Image(systemName: showList ? "chevron.left" : "list.bullet")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Palette.text2)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(showList ? "Back" : "Playlist")
                }
            }
            ZStack(alignment: .topLeading) {
                if showList {
                    PlaylistPanel(bridge: bridge)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    nowPlaying
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .clipped()
            .animation(Motion.adapt(Motion.slide, reduceMotion), value: showList)
        }
        .card()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: bridge.accent ?? .clear).opacity(0.10))
        )
        .animation(Motion.smooth, value: showList)
        .onHover { inside in
            hoverTask?.cancel()
            if inside {
                guard listOnHover, bridge.track != nil else { return }
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    toggleList(true)
                }
            } else if showList {
                toggleList(false)
            }
        }
        .onChange(of: bridge.showListForTesting) { _, show in toggleList(show) }
        // Read the position once when the panel comes into view; after that it is worked out locally.
        .onChange(of: paused) { _, hidden in
            if !hidden { bridge.refreshAll() } else { showList = false }
        }
    }

    private func toggleList(_ show: Bool) {
        if show { bridge.loadPlaylist() }
        withAnimation(Motion.adapt(Motion.slide, reduceMotion)) { showList = show }
    }

    @ViewBuilder
    private var nowPlaying: some View {
        if bridge.permissionDenied {
            VStack(alignment: .leading, spacing: 8) {
                Text("Allow this app to control Music to see what's playing.")
                    .font(.app(11))
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Give access") { bridge.openPermissionSettings() }
                    .controlSize(.small)
            }
        } else if let track = bridge.track {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    CoverArt(image: bridge.artwork, id: track.id, size: 56, radius: 10)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.app(12.5, .medium))
                            .foregroundStyle(Palette.text)
                            .lineLimit(2)
                        Text(track.artist)
                            .font(.app(11))
                            .foregroundStyle(Palette.text3)
                            .lineLimit(1)
                    }
                }
                Scrubber(bridge: bridge)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    IconButton(systemName: "backward.fill", help: "Previous") { bridge.previous() }
                    IconButton(systemName: bridge.isPlaying ? "pause.fill" : "play.fill",
                               help: bridge.isPlaying ? "Pause" : "Play") { bridge.playPause() }
                    IconButton(systemName: "forward.fill", help: "Next") { bridge.next() }
                    Spacer(minLength: 0)
                }
            }
        } else {
            HStack(spacing: 10) {
                CoverArt(image: nil, id: "", size: 40, radius: 8)
                Text(MusicBridge.isRunning ? "Nothing playing" : "Music isn't open")
                    .font(.app(11.5))
                    .foregroundStyle(Palette.text3)
            }
        }
    }
}

/// Song progress you can drag to seek. Moves once a second while playing and in view.
struct Scrubber: View {
    @ObservedObject var bridge: MusicBridge
    @Environment(\.animationsPaused) private var paused
    @State private var dragging: Double?

    var body: some View {
        let duration = max(bridge.track?.duration ?? 0, 1)
        TimelineView(.animation(minimumInterval: 1, paused: paused || !bridge.isPlaying || dragging != nil)) { context in
            let now = dragging ?? bridge.currentPosition(at: context.date)
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.line)
                        Capsule().fill(Palette.silverGradient)
                            .frame(width: geo.size.width * min(now / duration, 1))
                    }
                    .frame(height: dragging == nil ? 3 : 5)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in dragging = min(max(g.location.x / geo.size.width, 0), 1) * duration }
                        .onEnded { _ in
                            if let dragging { bridge.seek(to: dragging) }
                            dragging = nil
                        })
                    .animation(Motion.quick, value: dragging == nil)
                }
                .frame(height: 10)
                HStack {
                    Text(Self.format(now))
                    Spacer()
                    Text("-" + Self.format(max(duration - now, 0)))
                }
                .font(.app(9.5))
                .foregroundStyle(Palette.text3)
                .monospacedDigit()
            }
        }
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
