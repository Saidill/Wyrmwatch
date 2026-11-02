import AppKit

/// One track of an album found on Apple's catalogue.
struct AlbumTrack: Identifiable, Equatable {
    let number: Int
    let title: String
    let duration: Double
    let url: URL?
    var id: Int { number }
}

/// For songs streamed from Apple Music, Music.app shares no song list; this finds the song's album on Apple's
/// public iTunes Search API instead (no account or key). It sends only the artist and album name, runs off the
/// main thread with a short timeout, only when the Music tab asks, and remembers each album it has looked up.
@MainActor
final class AlbumLookup: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case found(album: String, tracks: [AlbumTrack])
        case notFound
    }

    @Published private(set) var state: State = .idle
    static let enabledKey = "music.albumLookup"

    private var cache: [String: State] = [:]
    private var task: Task<Void, Never>?
    private var currentKey: String?
    private let offline: Bool

    init(offline: Bool = false) {
        self.offline = offline
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
    }

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// Looks up the album of `track` (cached), replacing any lookup still running.
    func lookUp(_ track: NowPlaying) {
        guard enabled, !track.album.isEmpty else {
            state = .notFound
            return
        }
        let key = "\(track.artist)|\(track.album)".lowercased()
        guard key != currentKey || state == .idle else { return }
        currentKey = key
        task?.cancel()
        if let hit = cache[key] {
            state = hit
            return
        }
        guard !offline else { return }
        state = .loading
        let artist = track.artist, album = track.album
        task = Task { [weak self] in
            let result = await Self.fetch(artist: artist, album: album)
            guard !Task.isCancelled, let self, self.currentKey == key else { return }
            let next: State = result.map { .found(album: $0.0, tracks: $0.1) } ?? .notFound
            self.cache[key] = next
            self.state = next
        }
    }

    func reset() {
        task?.cancel()
        currentKey = nil
        state = .idle
    }

    /// Opens a catalogue track in Music.app.
    func open(_ track: AlbumTrack) {
        guard let url = track.url,
              let music = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MusicBridge.bundleID) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: music, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Self-test: shows a made-up album without going online.
    func injectForTesting(_ state: State) { self.state = state }

    // MARK: Network

    private struct SearchResponse: Decodable {
        struct Album: Decodable { let collectionId: Int; let collectionName: String; let artistName: String }
        let results: [Album]
    }

    private struct LookupResponse: Decodable {
        struct Item: Decodable {
            let wrapperType: String
            let trackNumber: Int?
            let discNumber: Int?
            let trackName: String?
            let trackTimeMillis: Double?
            let trackViewUrl: String?
        }
        let results: [Item]
    }

    nonisolated private static func fetch(artist: String, album: String) async -> (String, [AlbumTrack])? {
        let country = Locale.current.region?.identifier ?? "US"
        let session = URLSession(configuration: {
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = 5
            return c
        }())
        var search = URLComponents(string: "https://itunes.apple.com/search")!
        search.queryItems = [.init(name: "term", value: "\(artist) \(album)"), .init(name: "entity", value: "album"),
                             .init(name: "limit", value: "10"), .init(name: "country", value: country)]
        guard let url = search.url,
              let (data, _) = try? await session.data(from: url),
              let found = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return nil }
        // Prefer the exact album by the same artist; Music often adds " - EP" or "(Remastered)" on one side only.
        func plain(_ s: String) -> String {
            s.lowercased().replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]|\s+-\s+(ep|single)$"#, with: "", options: .regularExpression)
        }
        guard let match = found.results.first(where: { plain($0.collectionName) == plain(album) && plain($0.artistName) == plain(artist) })
                ?? found.results.first(where: { plain($0.collectionName) == plain(album) }) else { return nil }

        var lookup = URLComponents(string: "https://itunes.apple.com/lookup")!
        lookup.queryItems = [.init(name: "id", value: String(match.collectionId)), .init(name: "entity", value: "song"),
                             .init(name: "country", value: country)]
        guard let lookupURL = lookup.url,
              let (tracksData, _) = try? await session.data(from: lookupURL),
              let items = try? JSONDecoder().decode(LookupResponse.self, from: tracksData) else { return nil }
        let tracks = items.results
            .filter { $0.wrapperType == "track" && $0.trackName != nil }
            .sorted { ($0.discNumber ?? 1, $0.trackNumber ?? 0) < ($1.discNumber ?? 1, $1.trackNumber ?? 0) }
            .enumerated()
            .map { AlbumTrack(number: $0.offset + 1, title: $0.element.trackName ?? "", duration: ($0.element.trackTimeMillis ?? 0) / 1000,
                              url: $0.element.trackViewUrl.flatMap(URL.init(string:))) }
        return tracks.isEmpty ? nil : (match.collectionName, tracks)
    }
}
