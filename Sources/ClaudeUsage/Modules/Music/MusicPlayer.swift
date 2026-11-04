import AppKit
import ApplicationServices

/// Plays a song picked from a catalogue list (an album, top songs, recent) in Music.app.
/// Music can't be told by script to play a catalogue song, so: a copy in the library is played directly;
/// otherwise the song is opened in Music and its Play button pressed through Accessibility (which the user
/// allows once). Without that permission the song is only opened, and the caller is told so.
@MainActor
final class CatalogPlayer: ObservableObject {
    enum Outcome: Equatable {
        case idle
        case working(String)
        case played(String)
        /// Opened in Music; pressing play there (or allowing Accessibility) is up to the user.
        case openedOnly(String)
    }

    @Published private(set) var outcome: Outcome = .idle
    private let queue = DispatchQueue(label: "music.catalog-player", qos: .userInitiated)
    /// Bumped on every click; a search still running for an older click stops at once.
    private var generation = 0
    private var clearTask: Task<Void, Never>?

    /// Whether this app may press buttons in other apps.
    static var canPress: Bool { AXIsProcessTrusted() }

    /// Asks macOS to show the Accessibility prompt (once) and opens the right pane in System Settings.
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func play(title: String, artist: String, url: URL?) {
        generation += 1
        outcome = .working(title)
        let base = AlbumLookup.plain(title)
        let script = Self.libraryScript(title: base, artist: artist)
        queue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue ?? "none"
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if result == "library" {
                        self.finish(.played(title))
                    } else if let url {
                        self.playFromCatalog(title: title, url: url)
                    } else {
                        // A song from "Recent" has no catalogue link yet: find it, then play it the same way.
                        Task {
                            if let found = await Self.catalogURL(title: title, artist: artist) {
                                self.playFromCatalog(title: title, url: found)
                            } else {
                                self.finish(.openedOnly(title))
                            }
                        }
                    }
                }
            }
        }
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

    // MARK: Library

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

    // MARK: Catalogue

    private func playFromCatalog(title: String, url: URL) {
        guard let music = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MusicBridge.bundleID) else {
            finish(.openedOnly(title))
            return
        }
        let mine = generation
        let bridge = AppModels.music.bridge
        let songBefore = bridge.track?.id
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open([url], withApplicationAt: music, configuration: configuration)
        guard Self.canPress else {
            finish(.openedOnly(title))
            return
        }
        // Give Music a moment to show the song, then press that song's Play button, retrying while the page loads.
        // Stops at once if another song is clicked, Music closes or changes window, or something else starts playing.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            let window = MusicUI.mainWindow()
            for _ in 0..<12 {
                guard let self, self.generation == mine, MusicBridge.isRunning,
                      MusicUI.isSameWindow(window, MusicUI.mainWindow()),
                      bridge.track?.id == songBefore else {
                    self?.finishIfCurrent(mine, .openedOnly(title))
                    return
                }
                if MusicUI.pressPlay(forSong: title) {
                    // Check that the song that started is the one picked; never press anything again either way.
                    try? await Task.sleep(for: .milliseconds(1200))
                    bridge.refreshAll()
                    try? await Task.sleep(for: .milliseconds(400))
                    let right = AlbumLookup.plain(title) == AlbumLookup.plain(bridge.track?.title ?? "")
                    self.finishIfCurrent(mine, right ? .played(title) : .openedOnly(title))
                    return
                }
                try? await Task.sleep(for: .milliseconds(350))
            }
            self?.finishIfCurrent(mine, .openedOnly(title))
        }
    }

    /// Reports the result only if no newer click has replaced this one.
    private func finishIfCurrent(_ mine: Int, _ result: Outcome) {
        guard generation == mine else { return }
        finish(result)
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

/// Finds and presses Music.app's Play button through the Accessibility API — and nothing else.
///
/// Scope, on purpose:
/// - Only Music.app: every call starts from the running process with bundle ID `com.apple.Music`, checked again
///   before use. No other application is ever looked at.
/// - Only reading what's needed to recognise the clicked song's Play button: the role, title and description of
///   buttons, rows, cells and plain text, plus the visible text of static labels. Values of fields (such as
///   Music's search text) are never read.
/// - Only pressing buttons whose label is "Play"; nothing else (rows, menus, fields) is ever pressed, and at most
///   one press per click.
/// - Only the Play button next to the exact title of the song that was clicked; never a lone or unrelated one.
/// - Nothing read here is stored, logged, written to a file or sent anywhere; it lives in memory for one search.
@MainActor
enum MusicUI {
    /// Music.app's accessibility element, or nil when it isn't running (or isn't really Music).
    private static var music: AXUIElement? {
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: MusicBridge.bundleID).first,
              process.bundleIdentifier == MusicBridge.bundleID else { return nil }
        return AXUIElementCreateApplication(process.processIdentifier)
    }

    /// The only roles looked at. Everything else (fields, menus, images…) is skipped without being read.
    private static let readableRoles: Set<String> = [kAXWindowRole, kAXGroupRole, kAXScrollAreaRole, kAXTableRole, kAXOutlineRole,
                                                      kAXRowRole, "AXCell", kAXButtonRole, kAXStaticTextRole, kAXListRole,
                                                      "AXCollection", "AXSection", kAXSplitGroupRole]

    private static func copy(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func role(_ element: AXUIElement) -> String { (copy(element, kAXRoleAttribute) as? String) ?? "" }

    /// Title and description; for static text (a label shown on screen) also its value, which is where macOS
    /// keeps the visible text. Values of anything else, such as text fields and search boxes, are never read.
    private static func label(_ element: AXUIElement) -> String {
        var names = [kAXTitleAttribute, kAXDescriptionAttribute]
        if role(element) == kAXStaticTextRole { names.append(kAXValueAttribute) }
        return names.compactMap { copy(element, $0) as? String }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        ((copy(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []).filter { readableRoles.contains(role($0)) }
    }

    /// Music's windows and their readable elements, breadth first, up to `limit`.
    private static func walk(limit: Int = 4000) -> [AXUIElement] {
        guard let music else { return [] }
        var out: [AXUIElement] = []
        var frontier = (copy(music, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        while !frontier.isEmpty, out.count < limit {
            let element = frontier.removeFirst()
            out.append(element)
            frontier.append(contentsOf: children(element))
        }
        return out
    }

    private static func isPlayButton(_ element: AXUIElement) -> Bool {
        guard role(element) == kAXButtonRole else { return false }
        let text = label(element).lowercased()
        return text == "play" || text.hasPrefix("play ")
    }

    /// Presses the Play button that belongs to `title`, and only that one: it looks for elements whose label is
    /// exactly the song title (ignoring case and extras such as "(Remastered)"), then for a Play button in the same
    /// block as that title (at most four levels up, and never beyond the song's own row). If none is found nothing
    /// is pressed.
    static func pressPlay(forSong title: String) -> Bool {
        let base = AlbumLookup.plain(title)
        guard !base.isEmpty else { return false }
        let titles = walk().filter { [kAXStaticTextRole, kAXRowRole, "AXCell", kAXButtonRole].contains(role($0))
            && AlbumLookup.plain(label($0)) == base }
        for element in titles {
            var block = element
            for _ in 0..<4 {
                if let play = ([block] + descendants(block)).first(where: isPlayButton) {
                    return AXUIElementPerformAction(play, kAXPressAction as CFString) == .success
                }
                // A song's row is its boundary: never climb into the table, where other songs' buttons live.
                if [kAXRowRole, "AXCell"].contains(role(block)) { break }
                guard let parent = copy(block, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID(),
                      role(parent as! AXUIElement) != kAXWindowRole else { break }
                block = parent as! AXUIElement
            }
        }
        return false
    }

    /// Music's main window, to notice when it changes or closes during a search.
    static func mainWindow() -> AXUIElement? {
        guard let music, let window = copy(music, kAXMainWindowAttribute),
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return (window as! AXUIElement)
    }

    static func isSameWindow(_ a: AXUIElement?, _ b: AXUIElement?) -> Bool {
        guard let a, let b else { return false }
        return CFEqual(a, b)
    }

    /// TEMPORARY (one-time inspection agreed with the user; remove after the test): the roles and visible labels
    /// in Music's main window, printed to standard output only. Never written to a file by the app.
    static func inspectionLines(limit: Int = 700) -> [String] {
        guard let window = mainWindow() else { return ["no Music window"] }
        var out: [String] = []
        var frontier: [(AXUIElement, Int)] = [(window, 0)]
        while !frontier.isEmpty, out.count < limit {
            let (element, depth) = frontier.removeFirst()
            out.append(String(repeating: "  ", count: depth) + role(element) + "  " + label(element))
            frontier.insert(contentsOf: children(element).map { ($0, depth + 1) }, at: 0)
        }
        return out
    }

    private static func descendants(_ element: AXUIElement, limit: Int = 200) -> [AXUIElement] {
        var out: [AXUIElement] = []
        var frontier = children(element)
        while !frontier.isEmpty, out.count < limit {
            let next = frontier.removeFirst()
            out.append(next)
            frontier.append(contentsOf: children(next))
        }
        return out
    }
}
