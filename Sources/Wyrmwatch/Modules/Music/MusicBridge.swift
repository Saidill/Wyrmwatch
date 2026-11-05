import AppKit
import Combine

/// The song Music.app is on.
struct NowPlaying: Equatable {
    /// Music's persistent ID for the track, used to key the artwork cache.
    let id: String
    let title: String
    let artist: String
    let album: String
    /// Length in seconds (0 for a stream).
    let duration: Double
}

/// One row of the playlist being played.
struct PlaylistTrack: Identifiable, Equatable {
    /// 1-based position in the playlist, which is also how a track is played.
    let index: Int
    let title: String
    let artist: String
    let duration: Double
    var id: Int { index }
}

/// What's playing. Apple Music: song changes and play/pause arrive as a system notification (no polling), and
/// AppleScript fills in what the notification lacks (playlist, favourite, shuffle, repeat), always off the main
/// thread and never when Music isn't running (it would launch it). Any other player (Spotify, browsers, ...):
/// mediaremote-adapter's stream, with its own play/pause/next/previous/seek, and no playlist.
@MainActor
final class MusicBridge: ObservableObject {
    @Published private(set) var track: NowPlaying?
    @Published private(set) var isPlaying = false
    /// Where playback was at `positionDate`; the app extrapolates from there instead of asking every second.
    @Published private(set) var position: Double = 0
    @Published private(set) var positionDate = Date()
    @Published private(set) var artwork: NSImage?
    /// Accent picked from the artwork (its dominant colour), for a faint tint on the card.
    @Published private(set) var accent: NSColor?
    /// nil = not loaded; empty = the source has no readable list (radio, catalog songs outside the library).
    @Published private(set) var playlist: [PlaylistTrack]?
    @Published private(set) var playlistName = ""
    /// Index of the playing track within `playlist`.
    @Published private(set) var currentIndex: Int?
    /// The user hasn't let this app control Music (System Settings → Privacy → Automation).
    @Published private(set) var permissionDenied = false
    @Published private(set) var shuffle = false
    /// The song is a favourite (Music's heart).
    @Published private(set) var favorite = false
    /// Music's song repeat: off, one or all.
    @Published private(set) var repeatMode: RepeatMode = .off
    /// The app playing `track`. Playlists, favourites, shuffle and repeat only exist for Apple Music.
    @Published private(set) var source = MusicBridge.bundleID
    var isMusicApp: Bool { source == Self.bundleID }
    /// "Spotify", "Safari", ...: shown when another app than Music is playing.
    var sourceName: String {
        if let name = NSRunningApplication.runningApplications(withBundleIdentifier: source).first?.localizedName { return name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        // "com.spotify.client" → "Spotify"
        let parts = source.split(separator: ".")
        return (parts.count > 1 ? String(parts[1]) : source).capitalized
    }

    enum RepeatMode: String { case off, one, all }

    /// Self-test only: asks the card to slide its playlist in.
    @Published var showListForTesting = false
    /// Fires when the song changes (not on the first song seen).
    let trackChanged = PassthroughSubject<NowPlaying, Never>()

    private let queue = DispatchQueue(label: "music.applescript", qos: .userInitiated)
    private let artworkCache = ArtworkCache()
    private var playlistKey: String?
    private var observer: Any?
    private let adapter: NowPlayingAdapter?
    /// Self-test: no AppleScript and no real notifications.
    private let offline: Bool

    static let bundleID = "com.apple.Music"

    init(offline: Bool = false) {
        self.offline = offline
        adapter = offline ? nil : NowPlayingAdapter()
        guard !offline else { return }
        adapter?.onChange = { [weak self] item in self?.adapterChanged(item) }
        adapter?.start()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { self?.handle(info) }
        }
        if Self.isRunning { refreshAll() }
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Playback position now, worked out from the last reading.
    func currentPosition(at date: Date = Date()) -> Double {
        let p = isPlaying ? position + date.timeIntervalSince(positionDate) : position
        guard let duration = track?.duration, duration > 0 else { return max(p, 0) }
        return min(max(p, 0), duration)
    }

    // MARK: Notification

    private func handle(_ info: [AnyHashable: Any]) {
        let state = info["Player State"] as? String ?? ""
        // Music stopping says nothing about another app that is playing.
        if state == "Stopped", !isMusicApp { return }
        if state != "Stopped" { takeOver(Self.bundleID) }
        if state == "Stopped" {
            setPlaying(false)
            track = nil
            return
        }
        let wasPlaying = isPlaying
        let freeze = currentPosition()
        isPlaying = state == "Playing"
        let title = info["Name"] as? String ?? ""
        let artist = info["Artist"] as? String ?? ""
        let album = info["Album"] as? String ?? ""
        // Library songs carry a persistent ID; Apple Music streams and radio don't, so fall back to what they do carry.
        let id: String
        if let pid = info["PersistentID"] as? NSNumber {
            id = String(format: "%016llX", pid.uint64Value)
        } else if let url = info["Store URL"] as? String, !url.isEmpty {
            id = url
        } else if !title.isEmpty {
            id = "stream:\(title)|\(artist)|\(album)"
        } else {
            return
        }
        let next = NowPlaying(id: id, title: title, artist: artist, album: album,
                              duration: ((info["Total Time"] as? NSNumber)?.doubleValue ?? 0) / 1000)
        if next.id != track?.id, !sameSong(next, track) {
            let first = track == nil
            track = next
            position = 0
            positionDate = Date()
            loadArtwork(for: next)
            if !first { trackChanged.send(next) }
            // Same playlist: just move the highlight. Otherwise the list is fetched again when next shown.
            if let index = playlist?.firstIndex(where: { $0.title == next.title && $0.artist == next.artist }) {
                currentIndex = index
            } else if playlist != nil {
                playlist = nil
                playlistKey = nil
            }
            // One AppleScript read per song change (not polling): fills in what the notification leaves out
            // for streams (the real ID, position, favourite, shuffle and repeat) and the artwork.
            refreshAll()
        } else if wasPlaying != isPlaying {
            // Paused or resumed: carry the position across.
            position = freeze
            positionDate = Date()
        }
    }

    // MARK: Other players

    private func adapterChanged(_ item: NowPlayingAdapter.Item?) {
        guard let item else {
            // Nothing plays any more. Music's own notifications speak for Music.
            if !isMusicApp { setPlaying(false); track = nil; takeOver(Self.bundleID) }
            return
        }
        if item.bundleID == Self.bundleID {
            // Back to Music: read it the richer way.
            if !isMusicApp { takeOver(Self.bundleID); refreshAll() }
            return
        }
        // Another app took over only when it plays; a paused one in the background doesn't push Music aside.
        guard item.playing || !isMusicApp || track == nil else { return }
        takeOver(item.bundleID)
        let next = NowPlaying(id: item.id, title: item.title, artist: item.artist, album: item.album, duration: item.duration)
        if next != track {
            let first = track == nil
            let newSong = next.id != track?.id
            track = next
            if newSong {
                if let data = item.artwork, let image = NSImage(data: data) {
                    let entry = artworkCache.store(image, for: next.id)
                    artwork = entry.image
                    accent = entry.accent
                } else {
                    loadArtwork(for: next)
                }
                if !first { trackChanged.send(next) }
            }
        } else if artwork == nil, let data = item.artwork, let image = NSImage(data: data) {
            let entry = artworkCache.store(image, for: next.id)
            artwork = entry.image
            accent = entry.accent
        }
        isPlaying = item.playing
        position = item.elapsed + (item.playing ? Date().timeIntervalSince(item.stamp) : 0)
        positionDate = Date()
    }

    /// Switches whose song is shown; the Music-only parts are cleared when another app takes over.
    private func takeOver(_ bundle: String) {
        guard source != bundle else { return }
        source = bundle
        if bundle != Self.bundleID {
            playlist = []
            playlistKey = nil
            currentIndex = nil
            favorite = false
            shuffle = false
            repeatMode = .off
        } else {
            playlist = nil
        }
    }

    /// The same song seen through the notification (stream fallback ID) and through AppleScript (persistent ID).
    private func sameSong(_ a: NowPlaying, _ b: NowPlaying?) -> Bool {
        guard let b, a.id.hasPrefix("stream:") || b.id.hasPrefix("stream:") else { return false }
        return a.title == b.title && a.artist == b.artist && a.album == b.album
    }

    private func setPlaying(_ playing: Bool) {
        position = currentPosition()
        positionDate = Date()
        isPlaying = playing
    }

    // MARK: Reading

    /// Reads everything once: state, song, position, artwork. Used at launch and when the panel opens.
    func refreshAll() {
        guard !offline, isMusicApp, Self.isRunning else { return }
        run("""
        tell application "Music"
            if player state is stopped then return "stopped"
            set t to current track
            set fav to "false"
            try
                set fav to (favorited of t) as text
            on error
                try
                    set fav to (loved of t) as text
                end try
            end try
            return fav & tab & (player state as text) & tab & (persistent ID of t) & tab & (name of t) & tab & (artist of t) & tab & (album of t) & tab & (duration of t) & tab & player position & tab & (shuffle enabled as text) & tab & (song repeat as text)
        end tell
        """) { [weak self] result in
            guard let self, let text = result?.stringValue else { return }
            if text == "stopped" { self.track = nil; self.isPlaying = false; return }
            var f = text.components(separatedBy: "\t")
            guard f.count >= 8 else { return }
            self.favorite = f.removeFirst() == "true"
            let next = NowPlaying(id: f[1], title: f[2], artist: f[3], album: f[4], duration: Double(f[5].replacingOccurrences(of: ",", with: ".")) ?? 0)
            if next.id != self.track?.id || self.artwork == nil { self.loadArtwork(for: next) }
            self.track = next
            self.isPlaying = f[0] == "playing"
            self.position = Double(f[6].replacingOccurrences(of: ",", with: ".")) ?? 0
            self.positionDate = Date()
            if f.count >= 9 {
                self.shuffle = f[7] == "true"
                self.repeatMode = RepeatMode(rawValue: f[8]) ?? .off
            }
        }
    }

    /// Reads the playing playlist in one go (names, artists, durations) unless it is already loaded.
    func loadPlaylist(force: Bool = false) {
        guard !offline, isMusicApp, Self.isRunning else { return }
        run("""
        tell application "Music"
            try
                set p to current playlist
                set k to persistent ID of p
            on error
                return "none"
            end try
            set i to 0
            try
                set i to index of current track
            end try
            if (count of tracks of p) is 0 then return "none"
            set ns to name of every track of p
            set ars to artist of every track of p
            set ds to duration of every track of p
            set AppleScript's text item delimiters to (ASCII character 31)
            set out to k & tab & (name of p) & tab & i & tab & (ns as text) & tab & (ars as text) & tab & (ds as text)
            set AppleScript's text item delimiters to ""
            return out
        end tell
        """) { [weak self] result in
            guard let self else { return }
            guard let text = result?.stringValue, text != "none" else {
                self.playlist = []
                self.playlistKey = nil
                self.currentIndex = nil
                return
            }
            let f = text.components(separatedBy: "\t")
            guard f.count >= 6 else { self.playlist = []; return }
            if !force, f[0] == self.playlistKey, self.playlist != nil {
                self.currentIndex = Int(f[2]).map { $0 - 1 }
                return
            }
            let sep = String(UnicodeScalar(31))
            let names = f[3].components(separatedBy: sep)
            let artists = f[4].components(separatedBy: sep)
            let durations = f[5].components(separatedBy: sep)
            self.playlist = names.indices.map { i in
                PlaylistTrack(index: i + 1, title: names[i],
                              artist: i < artists.count ? artists[i] : "",
                              duration: i < durations.count ? Double(durations[i].replacingOccurrences(of: ",", with: ".")) ?? 0 : 0)
            }
            self.playlistKey = f[0]
            self.playlistName = f[1]
            self.currentIndex = Int(f[2]).flatMap { $0 > 0 ? $0 - 1 : nil }
        }
    }

    private func loadArtwork(for track: NowPlaying) {
        if let cached = artworkCache[track.id] {
            artwork = cached.image
            accent = cached.accent
            return
        }
        artwork = nil
        accent = nil
        guard !offline, isMusicApp, Self.isRunning else { return }
        run("""
        tell application "Music"
            try
                return raw data of artwork 1 of current track
            on error
                return ""
            end try
        end tell
        """) { [weak self] result in
            guard let self, self.track?.id == track.id, let data = result?.data, let image = NSImage(data: data) else { return }
            let entry = self.artworkCache.store(image, for: track.id)
            self.artwork = entry.image
            self.accent = entry.accent
        }
    }

    // MARK: Controls

    func playPause() {
        setPlaying(!isPlaying) // feels instant; the notification confirms it
        if isMusicApp { command("playpause") } else { adapter?.send(.togglePlayPause) }
    }

    func next() { if isMusicApp { command("next track") } else { adapter?.send(.next) } }

    func toggleShuffle() {
        shuffle.toggle()
        command("set shuffle enabled to \(shuffle)")
    }

    /// Hearts or un-hearts the playing song.
    func toggleFavorite() {
        favorite.toggle()
        let value = favorite ? "true" : "false"
        command("""
        try
            set favorited of current track to \(value)
        on error
            set loved of current track to \(value)
        end try
        """, wrapped: false)
    }

    /// "Play music" when nothing is on: starts Music (opening it if needed) and plays.
    func startMusic() {
        guard !offline else { return }
        run("tell application \"Music\" to play") { [weak self] _ in self?.refreshAll() }
    }

    /// Off → all → one → off, like Music's own button.
    func cycleRepeat() {
        repeatMode = switch repeatMode { case .off: .all; case .all: .one; case .one: .off }
        command("set song repeat to \(repeatMode.rawValue)")
    }
    func previous() { if isMusicApp { command("previous track") } else { adapter?.send(.previous) } }

    func seek(to seconds: Double) {
        position = seconds
        positionDate = Date()
        if isMusicApp { command("set player position to \(String(format: "%.2f", seconds))") } else { adapter?.seek(to: seconds) }
    }

    func play(_ item: PlaylistTrack) {
        currentIndex = playlist?.firstIndex(of: item)
        command("play track \(item.index) of current playlist")
    }

    func pause() {
        guard isPlaying else { return }
        setPlaying(false)
        if isMusicApp { command("pause") } else { adapter?.send(.pause) }
    }

    func play() {
        guard !isPlaying, track != nil else { return }
        setPlaying(true)
        if isMusicApp { command("play") } else { adapter?.send(.play) }
    }

    /// Opens the Automation pane so the user can allow this app to control Music.
    func openPermissionSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    private func command(_ line: String, wrapped: Bool = true) {
        guard !offline, Self.isRunning else { return }
        run(wrapped ? "tell application \"Music\" to \(line)" : "tell application \"Music\"\n\(line)\nend tell") { _ in }
    }

    // MARK: AppleScript

    private func run(_ source: String, completion: @escaping @MainActor (NSAppleEventDescriptor?) -> Void) {
        queue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let code = error?[NSAppleScript.errorNumber] as? Int
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // -1743: not allowed to send Apple events to Music.
                    if code == -1743 { self.permissionDenied = true } else if error == nil { self.permissionDenied = false }
                    completion(error == nil ? result : nil)
                }
            }
        }
    }

    // MARK: Self-test

    /// Feeds a made-up playerInfo notification through the real handler.
    func handleForTesting(_ info: [AnyHashable: Any]) { handle(info) }

    /// Feeds a made-up adapter state (the JSON payload) through the real handler.
    func adapterForTesting(_ state: [String: Any]?) { adapterChanged(state.flatMap(NowPlayingAdapter.item(from:))) }

    func injectForTesting(track: NowPlaying?, playing: Bool, position: Double = 0, artwork: NSImage? = nil,
                          playlist: [PlaylistTrack]? = nil, currentIndex: Int? = nil) {
        let changed = track != nil && self.track != nil && track?.id != self.track?.id
        takeOver(Self.bundleID)
        self.track = track
        isPlaying = playing
        self.position = position
        positionDate = Date()
        if let artwork {
            let entry = artworkCache.store(artwork, for: track?.id ?? "")
            self.artwork = entry.image
            accent = entry.accent
        }
        self.playlist = playlist
        self.currentIndex = currentIndex
        if changed, let track { trackChanged.send(track) }
    }
}
