import AppKit
import EventKit

/// Reads the live sources once (Music, calendar, battery) with the app's own permissions, writes what it saw
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

        var lines: [String] = []
        lines.append("music running: \(MusicBridge.isRunning)")
        lines.append("music permission denied: \(music.permissionDenied)")
        lines.append("track: \(music.track.map { "\($0.title) — \($0.artist) [\($0.id)] \(Int($0.duration))s" } ?? "none")")
        lines.append("playing: \(music.isPlaying), position: \(Int(music.currentPosition()))s, artwork: \(music.artwork != nil)")
        lines.append("playlist: \(music.playlist.map { $0.isEmpty ? "unavailable" : "\($0.count) songs in \"\(music.playlistName)\"" } ?? "not loaded"), current index: \(music.currentIndex.map(String.init) ?? "none")")
        lines.append("calendar status: \(EKEventStore.authorizationStatus(for: .event).rawValue) (3 = full access)")
        lines.append("next event: \(info.calendar.next.map { "\($0.title) at \($0.start)" } ?? "none")")
        lines.append("battery: \(info.battery.reading.map { "\($0.percent)% charging=\($0.charging) onPower=\($0.onPower)" } ?? "none")")
        try? lines.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
        print(lines.joined(separator: "\n"))
        NSApp.terminate(nil)
    }
}
