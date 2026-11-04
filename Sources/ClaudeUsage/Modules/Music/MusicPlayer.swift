import AppKit

/// Plays a song picked from a catalogue list (an album, top songs, recent).
/// Music.app can't be told by script to play an Apple Music catalogue song, so: a copy in the library is played
/// directly with AppleScript; otherwise the song's page is only opened in Music, and nothing is pressed there.
@MainActor
final class CatalogPlayer: ObservableObject {
    enum Outcome: Equatable {
        case idle
        case working(String)
        case played(String)
        /// Opened in Music; pressing play there is up to the user.
        case openedOnly(String)
    }

    @Published private(set) var outcome: Outcome = .idle
    private let queue = DispatchQueue(label: "music.catalog-player", qos: .userInitiated)
    private var clearTask: Task<Void, Never>?
    /// Bumped on every click; a result for an older click is dropped.
    private var generation = 0

    func play(title: String, artist: String, url: URL?) {
        generation += 1
        let mine = generation
        outcome = .working(title)
        let script = Self.libraryScript(title: AlbumLookup.plain(title), artist: artist)
        queue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue ?? "none"
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.generation == mine else { return }
                    if result == "library" {
                        self.finish(.played(title))
                    } else if let url {
                        self.open(url, title: title, mine: mine)
                    } else {
                        // A song from "Recent" has no catalogue link yet: find it, then open it.
                        Task {
                            if let found = await Self.catalogURL(title: title, artist: artist) {
                                self.open(found, title: title, mine: mine)
                            } else if self.generation == mine {
                                self.finish(.openedOnly(title))
                            }
                        }
                    }
                }
            }
        }
    }

    /// Shows the song's page in Music without pressing anything.
    private func open(_ url: URL, title: String, mine: Int) {
        guard generation == mine else { return }
        if let music = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MusicBridge.bundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: music, configuration: NSWorkspace.OpenConfiguration())
        }
        finish(.openedOnly(title))
    }

    /// The catalogue link of a song, from the iTunes Search API.
    nonisolated private static func catalogURL(title: String, artist: String) async -> URL? {
        struct Response: Decodable {
            struct Song: Decodable { let trackName: String?; let artistName: String?; let trackViewUrl: String? }
            let results: [Song]
        }
        var search = URLComponents(string: "https://itunes.apple.com/search")!
        search.queryItems = [.init(name: "term", value: "\(title) \(artist)"), .init(name: "entity", value: "song"),
                             .init(name: "limit", value: "10"), .init(name: "country", value: Locale.current.region?.identifier ?? "US")]
        guard let url = search.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let found = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let hit = found.results.first { AlbumLookup.plain($0.trackName ?? "") == AlbumLookup.plain(title)
            && AlbumLookup.plain($0.artistName ?? "") == AlbumLookup.plain(artist) }
        return hit?.trackViewUrl.flatMap(URL.init(string:))
    }

    /// Plays the first library song whose name contains `title` by `artist`; answers "library" or "none".
    nonisolated private static func libraryScript(title: String, artist: String) -> String {
        func quoted(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        return """
        tell application "Music"
            try
                set hits to (every track of library playlist 1 whose name contains \(quoted(title)) and artist contains \(quoted(artist)))
                if (count of hits) > 0 then
                    play item 1 of hits
                    return "library"
                end if
            end try
            return "none"
        end tell
        """
    }

    private func finish(_ result: Outcome) {
        outcome = result
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.outcome = .idle
        }
    }
}
