import Combine
import AppKit
import Darwin

/// Puts the notch in each state for a while and measures the app's own CPU and memory there.
/// Run: <app>/Contents/MacOS/<exe> --perf <output file>   (or scripts/measure-perf.sh)
@MainActor
enum Perf {
    static var isRequested: Bool { CommandLine.arguments.contains("--perf") }
    /// How often things changed during a measurement: publishers firing, and the notch view redrawing.
    static var counts: [String: Int] = [:]
    static func count(_ name: String) { if isRequested { counts[name, default: 0] += 1 } }
    private static var watchers: Set<AnyCancellable> = []

    static func startIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--perf") else { return }
        let out = URL(fileURLWithPath: args.count > i + 1 ? args[i + 1] : NSTemporaryDirectory() + "notch-perf.txt")
        Task { await run(out) }
    }

    private static func run(_ out: URL) async {
        let notch = NotchWindowController.shared
        let registry = notch.model.registry
        let display = DisplayModeController.shared
        let original = display.setting
        let saved = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?
            .filter { $0.key.hasPrefix("pomodoro.") } ?? [:]
        notch.holdOpenForTesting = true
        if display.notchScreen != nil { display.setting = .notch }
        // Let the launch work finish first (reading a week of Claude Code history).
        try? await Task.sleep(for: .seconds(20))

        let sources: [(String, ObservableObjectPublisher)] = [
            ("sessions", AppModels.sessions.objectWillChange), ("usage", AppModels.usage.objectWillChange),
            ("limits", AppModels.limits.objectWillChange), ("pomodoro", AppModels.pomodoro.timer.objectWillChange),
            ("music", AppModels.music.bridge.objectWillChange), ("registry", registry.objectWillChange),
            ("model", notch.model.objectWillChange)]
        for (name, publisher) in sources {
            publisher.sink { _ in MainActor.assumeIsolated { count(name) } }.store(in: &watchers)
        }
        var lines = ["state                  cpu %   memory MB   (15 s each, after 2 s to settle; token scan every 60 s)"]
        func measure(_ name: String) async {
            try? await Task.sleep(for: .seconds(2))
            counts = [:]
            let (cpu0, t0) = (cpuSeconds(), Date())
            try? await Task.sleep(for: .seconds(15))
            let cpu = (cpuSeconds() - cpu0) / Date().timeIntervalSince(t0) * 100
            let line = String(format: "%@%6.2f   %8.1f", name.padding(toLength: 22, withPad: " ", startingAt: 0), cpu, memoryMB())
            lines.append(line)
            lines.append("    changes: " + counts.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
            counts = [:]
            print(line)
        }

        registry.onlyForTesting = []
        await measure("closed")

        registry.onlyForTesting = ["pomodoro"]
        AppModels.pomodoro.timer.runForTesting(phase: .focus, secondsLeft: 20 * 60)
        await measure("live: pomodoro")
        UserDefaults.standard.set(true, forKey: MotionPreference.forceKey)
        await measure("live: pomodoro, still")
        UserDefaults.standard.removeObject(forKey: MotionPreference.forceKey)
        AppModels.pomodoro.timer.reset()

        registry.onlyForTesting = ["claude"]
        await measure(registry.active == nil ? "live: claude (inactive)" : "live: claude")

        registry.onlyForTesting = ["music"]
        AppModels.music.bridge.injectForTesting(
            track: NowPlaying(id: "PERF", title: "Song", artist: "Artist", album: "", duration: 240), playing: true)
        await measure("live: music")

        registry.onlyForTesting = nil
        notch.open()
        await measure("expanded (music on)")
        AppModels.music.bridge.injectForTesting(track: nil, playing: false)
        await measure("expanded (idle)")
        // Each page on its own, since each draws different things.
        let tabBefore = UserDefaults.standard.object(forKey: NotchTab.storageKey)
        for tab in NotchTab.allCases {
            UserDefaults.standard.set(tab.rawValue, forKey: NotchTab.storageKey)
            await measure("  tab: \(tab.rawValue)")
        }
        UserDefaults.standard.set(tabBefore, forKey: NotchTab.storageKey)
        UserDefaults.standard.set(true, forKey: MotionPreference.forceKey)
        await measure("expanded, still")
        UserDefaults.standard.removeObject(forKey: MotionPreference.forceKey)
        notch.close()
        registry.onlyForTesting = []
        await measure("closed again")

        for key in UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?.keys
            .filter({ $0.hasPrefix("pomodoro.") }) ?? [] where saved[key] == nil {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for (key, value) in saved { UserDefaults.standard.set(value, forKey: key) }
        display.setting = original
        try? lines.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    /// User + system CPU time used by this process so far.
    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return s(usage.ru_utime) + s(usage.ru_stime)
    }

    /// Memory footprint, as Activity Monitor's "Memory" column shows it.
    private static func memoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
