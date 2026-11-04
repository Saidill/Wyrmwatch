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
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open([url], withApplicationAt: music, configuration: configuration)
        guard Self.canPress else {
            finish(.openedOnly(title))
            return
        }
        // Give Music a moment to show the song, then press its Play button (retrying while the page loads).
        Task { [weak self] in
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(350))
                if MusicUI.pressPlay(forSong: title) {
                    self?.finish(.played(title))
                    return
                }
            }
            self?.finish(.openedOnly(title))
        }
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

/// Reads and presses Music.app's interface through the Accessibility API.
@MainActor
enum MusicUI {
    private static var app: AXUIElement? {
        NSRunningApplication.runningApplications(withBundleIdentifier: MusicBridge.bundleID).first
            .map { AXUIElementCreateApplication($0.processIdentifier) }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String {
        (attribute(element, name) as? String) ?? ""
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    /// Every element of Music's windows, breadth first, up to `limit`.
    private static func walk(limit: Int = 4000) -> [(element: AXUIElement, depth: Int)] {
        guard let app else { return [] }
        var out: [(AXUIElement, Int)] = []
        var frontier = ((attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []).map { ($0, 0) }
        while !frontier.isEmpty, out.count < limit {
            let (element, depth) = frontier.removeFirst()
            out.append((element, depth))
            if depth < 30 { frontier.append(contentsOf: children(element).map { ($0, depth + 1) }) }
        }
        return out
    }

    /// The text of an element: its title, description, value or help.
    private static func label(_ element: AXUIElement) -> String {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
            .map { string(element, $0) }.filter { !$0.isEmpty }.joined(separator: " / ")
    }

    /// Presses the Play control that belongs to `title`: a row naming the song with a play button in it,
    /// or else a lone "Play" button on a single song's page. Returns whether something was pressed.
    static func pressPlay(forSong title: String) -> Bool {
        let base = AlbumLookup.plain(title)
        let all = walk()
        // A row or cell that mentions the song, with a play button inside.
        for (element, _) in all where AlbumLookup.plain(label(element)).contains(base) {
            for child in descendants(element) where isPlayButton(child) {
                if AXUIElementPerformAction(child, kAXPressAction as CFString) == .success { return true }
            }
            // The row itself may play when pressed (double-click equivalent on track rows).
            if string(element, kAXRoleAttribute) == kAXRowRole as String || string(element, kAXRoleAttribute) == "AXCell" {
                if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success { return true }
            }
        }
        return false
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

    private static func isPlayButton(_ element: AXUIElement) -> Bool {
        guard string(element, kAXRoleAttribute) == kAXButtonRole as String else { return false }
        let text = label(element).lowercased()
        return text == "play" || text.hasPrefix("play ") || text.contains("/ play") || text.hasPrefix("play /")
    }

    /// Diagnose: a readable outline of Music's interface (roles and labels).
    static func dump(limit: Int = 2500) -> String {
        walk(limit: limit).map { element, depth in
            String(repeating: "  ", count: depth) + string(element, kAXRoleAttribute) + "  " + label(element)
        }.joined(separator: "\n")
    }
}
