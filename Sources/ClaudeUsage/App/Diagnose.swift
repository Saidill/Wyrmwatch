import AppKit
import EventKit

/// Reads the live sources once (Music, calendar) with the app's own permissions, writes what it saw
/// to a file and quits. Used to check access after the permission prompts.
/// Run: ClaudeUsage.app/Contents/MacOS/ClaudeUsage --diagnose <output file>
@MainActor
enum Diagnose {
    static func startIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--diagnose") else { return }
        let out = URL(fileURLWithPath: args.count > i + 1 ? args[i + 1] : NSTemporaryDirectory() + "notch-diagnose.txt")
        Task { await run(out) }
    }

    private static func run(_ out: URL) async {
        let music = AppModels.music.bridge
        let info = AppModels.info
        // Leave time for the permission prompts to be answered.
        for _ in 0..<120 {
            try? await Task.sleep(for: .seconds(1))
            let calendarDecided = EKEventStore.authorizationStatus(for: .event) != .notDetermined
            let musicDecided = !MusicBridge.isRunning || music.track != nil || music.permissionDenied
            if calendarDecided && musicDecided { break }
            if MusicBridge.isRunning, music.track == nil { music.refreshAll() }
        }
        info.calendar.requestAccess()
        music.loadPlaylist(force: true)
        try? await Task.sleep(for: .seconds(3))
        let albums = AppModels.music.albums
        // --album-test: look up a known album as if a streamed song were playing (checks the real request).
        let testAlbum = CommandLine.arguments.contains("--album-test")
            ? NowPlaying(id: "TEST", title: "Out of the Blue", artist: "Michael Learns to Rock", album: "Strange Foreign Beauty", duration: 244)
            : nil
        if let track = testAlbum ?? (music.playlist?.isEmpty == true ? music.track : nil) {
            albums.lookUp(track)
            for _ in 0..<12 where albums.state == .loading || albums.state == .idle { try? await Task.sleep(for: .seconds(0.5)) }
        }

        var lines: [String] = []
        lines.append("accessibility allowed: \(CatalogPlayer.canPress)")
        // --play-test <title>|<artist>|<link>: plays one catalogue song the way a click in the list does.
        if let i = CommandLine.arguments.firstIndex(of: "--play-test"), CommandLine.arguments.count > i + 1 {
            let parts = CommandLine.arguments[i + 1].components(separatedBy: "|")
            let player = AppModels.music.player
            player.play(title: parts[0], artist: parts.count > 1 ? parts[1] : "", url: parts.count > 2 ? URL(string: parts[2]) : nil)
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(250))
                if case .working = player.outcome { continue }
                break
            }
            try? await Task.sleep(for: .seconds(1.5))
            music.refreshAll()
            try? await Task.sleep(for: .seconds(1))
            lines.append("play test: \(player.outcome); now \(music.isPlaying ? "playing" : "not playing") \(music.track?.title ?? "-")")
        }
        lines.append("music running: \(MusicBridge.isRunning)")
        lines.append("music permission denied: \(music.permissionDenied)")
        lines.append("track: \(music.track.map { "\($0.title) — \($0.artist) [\($0.id)] \(Int($0.duration))s" } ?? "none")")
        lines.append("playing: \(music.isPlaying), position: \(Int(music.currentPosition()))s, artwork: \(music.artwork != nil)")
        lines.append("playlist: \(music.playlist.map { $0.isEmpty ? "unavailable" : "\($0.count) songs in \"\(music.playlistName)\"" } ?? "not loaded"), current index: \(music.currentIndex.map(String.init) ?? "none")")
        if let track = testAlbum {
            let top = AppModels.music.topSongs
            top.lookUp(track)
            for _ in 0..<12 where top.state == .loading || top.state == .idle { try? await Task.sleep(for: .seconds(0.5)) }
            if case .found(_, let tracks) = top.state {
                lines.append("top songs: \(tracks.prefix(5).map(\.title).joined(separator: ", "))")
            } else {
                lines.append("top songs: \(top.state)")
            }
        }
        switch albums.state {
        case .found(let album, let tracks): lines.append("album look-up: \(tracks.count) songs from \"\(album)\"")
        case .notFound: lines.append("album look-up: not found")
        case .loading: lines.append("album look-up: still loading")
        case .idle: lines.append("album look-up: not needed (library playlist)")
        }
        lines.append("calendar status: \(EKEventStore.authorizationStatus(for: .event).rawValue) (3 = full access)\(info.calendar.lastError.map { ", error: \($0)" } ?? "")")
        lines.append("next event: \(info.calendar.next.map { "\($0.title) at \($0.start)" } ?? "none")")
        try? lines.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
        print(lines.joined(separator: "\n"))
        NSApp.terminate(nil)
    }
}
