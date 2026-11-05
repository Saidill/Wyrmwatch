import AppKit

/// What any app is playing (Spotify, a browser, Podcasts, ...), read through mediaremote-adapter
/// (BSD 3-Clause, vendored in Vendor/mediaremote-adapter). Since macOS 15.4 only Apple-signed processes may read
/// now playing, so the adapter runs inside /usr/bin/perl and streams JSON lines; this class reads them.
/// No permission prompt, no polling: one long-lived process that only prints when something changes.
@MainActor
final class NowPlayingAdapter {
    struct Item: Equatable {
        let bundleID: String
        let id: String
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let playing: Bool
        /// Playback position at `stamp`.
        let elapsed: Double
        let stamp: Date
        let artwork: Data?
    }

    /// The adapter's commands (MRCommand IDs).
    enum Command: Int { case play = 0, pause = 1, togglePlayPause = 2, next = 4, previous = 5 }

    /// Called on the main thread with the current item, or nil when nothing plays.
    var onChange: (Item?) -> Void = { _ in }

    private let script: String
    private let framework: String
    private var process: Process?
    private var state: [String: Any] = [:]
    private var buffer = Data()
    private var restarts = 0
    private var quitObserver: Any?

    /// nil when the app was built without the adapter (no CMake) or it can't run on this Mac.
    init?() {
        guard let script = Bundle.main.path(forResource: "mediaremote-adapter", ofType: "pl"),
              let frameworks = Bundle.main.privateFrameworksPath else { return nil }
        let framework = (frameworks as NSString).appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: framework) else { return nil }
        self.script = script
        self.framework = framework
        // The stream is a child process: it goes when the app goes.
        quitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                                              queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func start() {
        guard process == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script, framework, "stream", "--debounce=100"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(chunk) } }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.ended() } }
        }
        do { try process.run() } catch { return }
        self.process = process
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    func send(_ command: Command) { runOnce(["send", String(command.rawValue)]) }

    func seek(to seconds: Double) { runOnce(["seek", String(Int(max(0, seconds) * 1_000_000))]) }

    // MARK: Reading

    private func receive(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  json["type"] as? String == "data", let payload = json["payload"] as? [String: Any] else { continue }
            if json["diff"] as? Bool == true {
                for (key, value) in payload {
                    if value is NSNull { state[key] = nil } else { state[key] = value }
                }
            } else {
                state = payload
            }
            restarts = 0
            onChange(Self.item(from: state))
        }
    }

    static func item(from state: [String: Any]) -> Item? {
        guard let title = state["title"] as? String, !title.isEmpty,
              let bundle = state["bundleIdentifier"] as? String ?? state["parentApplicationBundleIdentifier"] as? String
        else { return nil }
        let artist = state["artist"] as? String ?? ""
        let album = state["album"] as? String ?? ""
        let unique = (state["uniqueIdentifier"] as? NSNumber)?.stringValue ?? "\(title)|\(artist)|\(album)"
        let stamp = (state["timestamp"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        return Item(bundleID: bundle, id: "mr:\(bundle):\(unique)", title: title, artist: artist, album: album,
                    duration: (state["duration"] as? NSNumber)?.doubleValue ?? 0,
                    playing: state["playing"] as? Bool ?? false,
                    elapsed: (state["elapsedTime"] as? NSNumber)?.doubleValue ?? 0, stamp: stamp,
                    artwork: (state["artworkData"] as? String).flatMap { Data(base64Encoded: $0) })
    }

    /// The stream died (it shouldn't): start it again a few times, slower each time, then give up.
    private func ended() {
        process = nil
        state = [:]
        buffer.removeAll()
        onChange(nil)
        guard restarts < 5 else { return }
        restarts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(restarts * restarts) * 2) { [weak self] in self?.start() }
    }

    private func runOnce(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script, framework] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
