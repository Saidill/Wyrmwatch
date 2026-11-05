import Foundation

struct LiveSession: Identifiable, Decodable, Equatable {
    let pid: Int32
    let sessionId: String?
    let cwd: String?
    let name: String?
    let status: String?
    let kind: String?
    let startedAt: Double?
    let statusUpdatedAt: Double?

    var id: Int32 { pid }
    var isBusy: Bool { status == "busy" }
    /// Claude is waiting for you (a permission prompt or a question).
    var isWaiting: Bool { status == "waiting" }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let cwd { return URL(fileURLWithPath: cwd).lastPathComponent }
        return "Session \(pid)"
    }

    /// Full path with ~ for the home folder.
    var folder: String {
        guard let cwd else { return "" }
        return cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// Last two path components, e.g. "ProjectCode/claude-usage-ui".
    var shortFolder: String {
        guard let cwd else { return "" }
        return URL(fileURLWithPath: cwd).pathComponents.suffix(2).joined(separator: "/")
    }

    var statusSince: Date? {
        (statusUpdatedAt ?? startedAt).map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}

/// Watches ~/.claude/sessions/*.json, which Claude Code keeps updated for every running session.
@MainActor
final class SessionMonitor: ObservableObject {
    @Published private(set) var sessions: [LiveSession] = []
    /// Increments every time a session finishes; drives the confetti.
    @Published private(set) var finishCount = 0
    /// The session that finished most recently; the notch pop shows it.
    private(set) var lastFinished: LiveSession?
    /// True for a few seconds after a session finishes; the menu bar shows a check mark.
    @Published private(set) var celebrating = false

    private var celebrateTask: Task<Void, Never>?

    var busyCount: Int { sessions.filter(\.isBusy).count }
    var waitingCount: Int { sessions.filter(\.isWaiting).count }
    /// What each working session is doing right now, e.g. "Editing HomePage.swift" (from its transcript's tail).
    @Published private(set) var activity: [Int32: String] = [:]
    private let activityReader = ActivityReader()
    private var activityRead: [Int32: Date] = [:]

    private let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/sessions")
    private var lastStatus: [Int32: String] = [:]
    private var firstScan = true
    private var timer: Timer?
    private var dirSource: DispatchSourceFileSystemObject?

    init() {
        scan()
        watchDirectory()
        // Fallback: status changes rewrite files in place, which a directory watch may not see.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    private func watchDirectory() {
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.scan() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        dirSource = source
    }

    func scan() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var found: [LiveSession] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let session = try? JSONDecoder().decode(LiveSession.self, from: data),
                  Self.isAlive(session.pid) else { continue }
            found.append(session)
        }
        found.sort { ($0.isBusy ? 0 : 1, $0.displayName) < ($1.isBusy ? 0 : 1, $1.displayName) }

        for session in found {
            let previous = lastStatus[session.pid]
            // Finished means busy and now idle. Waiting (for a permission or an answer) is not finished.
            if !firstScan, previous == "busy", session.status == "idle" {
                // The notch pops up its own "finished" card, so skip the banner there.
                Notifier.shared.taskFinished(session.displayName, banner: !DisplayModeController.shared.isNotch)
                lastFinished = session
                celebrate()
            }
            lastStatus[session.pid] = session.status ?? ""
        }
        let alive = Set(found.map(\.pid))
        lastStatus = lastStatus.filter { alive.contains($0.key) }
        firstScan = false

        if found != sessions { sessions = found }
        readActivity(found)
    }

    /// Looks at the tail of each active session's transcript, at most every 2 s per session, off the main thread.
    private func readActivity(_ found: [LiveSession]) {
        let now = Date()
        for session in found where session.isBusy || session.isWaiting {
            if let last = activityRead[session.pid], now.timeIntervalSince(last) < 2 { continue }
            activityRead[session.pid] = now
            let pid = session.pid
            activityReader.read(session) { [weak self] text in
                MainActor.assumeIsolated {
                    guard let self, self.activity[pid] != text else { return }
                    self.activity[pid] = text
                }
            }
        }
        let active = Set(found.filter { $0.isBusy || $0.isWaiting }.map(\.pid))
        if activity.keys.contains(where: { !active.contains($0) }) { activity = activity.filter { active.contains($0.key) } }
        activityRead = activityRead.filter { active.contains($0.key) }
    }

    private func celebrate() {
        finishCount += 1
        celebrating = true
        celebrateTask?.cancel()
        celebrateTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.celebrating = false
        }
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}

/// Reads what a session is doing from the last ~200 KB of its transcript (never the whole file): the last tool
/// Claude called, as a short line such as "Editing HomePage.swift" or "Running swift build".
final class ActivityReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "session-activity", qos: .utility)
    private let projects = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
    private static let tail = 200_000

    func read(_ session: LiveSession, completion: @escaping @Sendable (String?) -> Void) {
        queue.async {
            let text = self.transcript(for: session).flatMap(self.lastActivity)
            DispatchQueue.main.async { completion(text) }
        }
    }

    /// ~/.claude/projects/<cwd with every non-alphanumeric as "-">/<session id>.jsonl
    private func transcript(for session: LiveSession) -> URL? {
        guard let id = session.sessionId, let cwd = session.cwd else { return nil }
        let folder = cwd.replacingOccurrences(of: "[^A-Za-z0-9]", with: "-", options: .regularExpression)
        let url = projects.appendingPathComponent(folder).appendingPathComponent(id + ".jsonl")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func lastActivity(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > UInt64(Self.tail) ? size - UInt64(Self.tail) : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        // Newest first; the first (partial) line is skipped.
        for line in data.split(separator: UInt8(ascii: "\n")).dropFirst().reversed() {
            guard line.range(of: Data("\"tool_use\"".utf8)) != nil,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]],
                  let use = content.last(where: { $0["type"] as? String == "tool_use" }) else { continue }
            return Self.describe(tool: use["name"] as? String ?? "", input: use["input"] as? [String: Any] ?? [:])
        }
        return nil
    }

    /// "Editing HomePage.swift", "Reading README.md", "Running swift build", "Searching", …
    static func describe(tool: String, input: [String: Any]) -> String {
        let file = (input["file_path"] as? String ?? input["notebook_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        switch tool {
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return "Editing " + (file ?? "a file")
        case "Read": return "Reading " + (file ?? "a file")
        case "Bash":
            if let description = input["description"] as? String, !description.isEmpty { return description }
            let command = (input["command"] as? String ?? "").split(separator: " ").prefix(2).joined(separator: " ")
            return command.isEmpty ? "Running a command" : "Running " + command
        case "Grep", "Glob": return "Searching the code"
        case "WebFetch", "WebSearch": return "Looking things up"
        case "Task", "Agent": return "Working with a helper"
        case "AskUserQuestion": return "Asking you a question"
        default: return tool.isEmpty ? "Working" : tool
        }
    }
}
