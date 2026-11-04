import AppKit

/// One track of an album found on Apple's catalogue.
struct AlbumTrack: Identifiable, Equatable {
    let number: Int
    let title: String
    let duration: Double
    let url: URL?
    var id: Int { number }
}

/// For songs streamed from Apple Music, Music.app shares no song list; this finds one on Apple's public
/// iTunes Search API instead (no account or key): the song's album, or the artist's top songs. It sends only the
/// artist (and album) name, runs off the main thread with a short timeout, only when the Music tab asks,
/// and remembers each list it has looked up.
@MainActor
final class AlbumLookup: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case found(album: String, tracks: [AlbumTrack])
        case notFound
    }

    /// Which list this looks up.
    enum Kind { case album, topSongs }

    @Published private(set) var state: State = .idle
    static let enabledKey = "music.albumLookup"
    let kind: Kind

    private var cache: [String: State] = [:]
    private var task: Task<Void, Never>?
    private var currentKey: String?
    private let offline: Bool

    init(kind: Kind = .album, offline: Bool = false) {
        self.kind = kind
        self.offline = offline
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
    }

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// Looks up the album of `track` (cached), replacing any lookup still running.
    func lookUp(_ track: NowPlaying) {
        guard enabled, !track.artist.isEmpty, kind == .topSongs || !track.album.isEmpty else {
            state = .notFound
            return
        }
        let key = (kind == .album ? "\(track.artist)|\(track.album)" : track.artist).lowercased()
        guard key != currentKey || state == .idle else { return }
        currentKey = key
        task?.cancel()
        if let hit = cache[key] {
            state = hit
            return
        }
        guard !offline else { return }
        state = .loading
        let artist = track.artist, album = track.album, kind = kind
        task = Task { [weak self] in
            let result = kind == .album ? await Self.fetch(artist: artist, album: album) : await Self.fetchTopSongs(artist: artist)
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

    /// Plays a catalogue track's library copy, or else opens its page in Music.app.
    func open(_ track: AlbumTrack, artist: String) {
        AppModels.music.player.play(title: track.title, artist: artist, url: track.url)
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

    nonisolated private static let session = URLSession(configuration: {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 5
        return c
    }())

    nonisolated private static var country: String { Locale.current.region?.identifier ?? "US" }

    /// Lower-cased, without "(Remastered)", "[Live]", " - EP" and the like.
    nonisolated static func plain(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]|\s+-\s+(ep|single)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private struct SongSearch: Decodable {
        struct Song: Decodable {
            let trackName: String?
            let artistName: String?
            let trackTimeMillis: Double?
            let trackViewUrl: String?
        }
        let results: [Song]
    }

    /// The artist's most popular songs (the search ranks them by popularity), one version of each.
    nonisolated private static func fetchTopSongs(artist: String) async -> (String, [AlbumTrack])? {
        var search = URLComponents(string: "https://itunes.apple.com/search")!
        search.queryItems = [.init(name: "term", value: artist), .init(name: "entity", value: "song"),
                             .init(name: "attribute", value: "artistTerm"), .init(name: "limit", value: "40"),
                             .init(name: "country", value: country)]
        guard let url = search.url,
              let (data, _) = try? await session.data(from: url),
              let found = try? JSONDecoder().decode(SongSearch.self, from: data) else { return nil }
        var seen = Set<String>()
        var tracks: [AlbumTrack] = []
        for song in found.results where plain(song.artistName ?? "") == plain(artist) {
            guard let title = song.trackName, seen.insert(plain(title)).inserted else { continue }
            tracks.append(AlbumTrack(number: tracks.count + 1, title: title, duration: (song.trackTimeMillis ?? 0) / 1000,
                                     url: song.trackViewUrl.flatMap(URL.init(string:))))
            if tracks.count == 15 { break }
        }
        return tracks.isEmpty ? nil : (artist, tracks)
    }

    nonisolated private static func fetch(artist: String, album: String) async -> (String, [AlbumTrack])? {
        var search = URLComponents(string: "https://itunes.apple.com/search")!
        search.queryItems = [.init(name: "term", value: "\(artist) \(album)"), .init(name: "entity", value: "album"),
                             .init(name: "limit", value: "10"), .init(name: "country", value: country)]
        guard let url = search.url,
              let (data, _) = try? await session.data(from: url),
              let found = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return nil }
        // Prefer the exact album by the same artist; Music often adds " - EP" or "(Remastered)" on one side only.
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

/// Where a streamed song most likely came from, judged by the song before it (Music.app doesn't say).
enum StreamContext: String, CaseIterable, Identifiable {
    case album, topSongs, recent
    var id: String { rawValue }

    var title: String {
        switch self {
        case .album: return "Album"
        case .topSongs: return "Top songs"
        case .recent: return "Recent"
        }
    }

    /// Same album as the last song: the album. Same artist, another album: the artist's top songs.
    /// Another artist: a station or mix, so what has played. The first song: its album.
    static func infer(current: NowPlaying, previous: NowPlaying?) -> StreamContext {
        guard let previous else { return .album }
        let sameArtist = AlbumLookup.plain(previous.artist) == AlbumLookup.plain(current.artist)
        if !sameArtist { return .recent }
        return AlbumLookup.plain(previous.album) == AlbumLookup.plain(current.album) ? .album : .topSongs
    }
}
