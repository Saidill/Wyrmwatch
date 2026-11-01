import AppKit
import SwiftUI

/// Drives the real app through mode switches and every notch state, checks that the right window is
/// visible and clickable each time, and saves a picture of each screen.
/// Run: ClaudeUsage.app/Contents/MacOS/ClaudeUsage --selftest <output folder>
@MainActor
enum SelfTest {
    private static var out = URL(fileURLWithPath: NSTemporaryDirectory())
    private static var report: [String] = []
    private static var failures = 0

    /// The app was started to run the self-test (no AppleScript to Music, no real Music notifications).
    static let isRequested = CommandLine.arguments.contains("--selftest")

    static func startIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest") else { return }
        if args.count > i + 1 { out = URL(fileURLWithPath: args[i + 1]) }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        Task { await run() }
    }

    private static func run() async {
        let display = DisplayModeController.shared
        let notch = NotchWindowController.shared
        let original = display.setting
        notch.holdOpenForTesting = true
        // A real pointer resting on the notch would hold pops open; the timing checks must not depend on it.
        notch.model.registry.popQueue.isHovering = { false }
        await wait(1.5) // let the app finish launching
        renderDragons()

        for round in 1...3 {
            log("— Round \(round)")

            // Menu bar mode: the icon opens the popover.
            display.setting = .menuBar
            await wait(0.8)
            check(notch.window?.isVisible != true, "notch window hidden in menu bar mode")
            check(visibleIcons() == 1, "exactly one menu bar icon")
            await clickStatusItem()
            check(popoverWindow()?.isVisible == true, "popover opens from the menu bar icon")
            if round == 1, let w = popoverWindow() {
                snapshot(w, "1-menubar-popover")
                check(await dragonMoves(in: w), "dragon moves in the menu bar header")
            }

            // Header button inside the popover: switch to the notch while the popover is open.
            display.toggle()
            await wait(1.0)
            check(display.isNotch, "switched to notch mode")
            check(notch.window?.isVisible == true, "notch window visible")
            check(notch.window?.ignoresMouseEvents == true, "closed notch lets clicks through")
            check(popoverWindow()?.isVisible != true, "popover gone after switching to the notch")
            check(visibleIcons() == 0, "menu bar icon hidden in notch mode")

            // Open the notch, as hovering does.
            notch.open()
            await wait(0.9)
            check(notch.model.expanded, "notch opens")
            check(notch.window?.ignoresMouseEvents == false, "open notch takes clicks")
            if round == 1, let w = notch.window {
                snapshot(w, "2-notch-open")
                check(await dragonMoves(in: w), "dragon moves in the open notch header")
            }

            // Header button inside the notch: back to the menu bar while the notch is open.
            display.toggle()
            await wait(1.0)
            check(!display.isNotch, "switched back to menu bar mode")
            check(notch.window?.isVisible != true, "notch window hidden again")
            check(!notch.model.expanded, "notch state reset")
            check(visibleIcons() == 1, "exactly one menu bar icon after coming back")
            await clickStatusItem()
            check(popoverWindow()?.isVisible == true, "popover still opens after coming back from the notch")
            await clickStatusItem()
            check(popoverWindow()?.isVisible != true, "clicking the icon again closes it")
            await closePopover()

            // And to the notch again from the menu bar: it must open again.
            display.setting = .notch
            await wait(0.8)
            notch.open()
            await wait(0.9)
            check(notch.model.expanded && notch.window?.isVisible == true, "notch opens again after a round trip")
            notch.close()
            await wait(0.6)
            check(!notch.model.expanded && notch.window?.ignoresMouseEvents == true, "notch closes cleanly")
        }

        // Pictures of each popover tab.
        display.setting = .menuBar
        await wait(0.6)
        let originalTab = UserDefaults.standard.integer(forKey: "popoverTab")
        for (tab, name) in [(1, "5-menubar-recent"), (2, "6-menubar-usage"), (0, "")] {
            UserDefaults.standard.set(tab, forKey: "popoverTab")
            await clickStatusItem()
            await wait(0.8)
            if !name.isEmpty, let w = popoverWindow() { snapshot(w, name) }
            await closePopover()
        }
        UserDefaults.standard.set(originalTab, forKey: "popoverTab")

        // Pictures of the other notch states.
        display.setting = .notch
        await wait(0.8)
        if let panel = notch.window {
            // The closed hover zone must stay inside the menu bar, so browser tabs under the notch can't open it.
            let zone = notch.activeRect()
            let notchBottom = panel.frame.maxY - (notch.screens.first?.screen.notch.height ?? 0)
            check(zone.minY >= notchBottom - 0.5, "closed notch hover zone stays inside the menu bar")
            check(!zone.contains(NSPoint(x: panel.frame.midX, y: notchBottom - 12)), "pointer on a tab under the notch doesn't count")
        }
        if let w = notch.window { snapshot(w, AppModels.sessions.busyCount > 0 ? "3-notch-live" : "3-notch-closed") }
        AppModels.claude.pop(LiveSession(pid: 1, sessionId: nil, cwd: NSHomeDirectory() + "/ProjectCode/claude-usage-ui",
                                         name: "claude-usage-ui", status: "idle", kind: nil, startedAt: nil,
                                         statusUpdatedAt: nil))
        await wait(1.0)
        check(notch.model.state == .pop, "finished pop shows")
        check(notch.window?.ignoresMouseEvents == false, "pop takes clicks")
        if let w = notch.window { snapshot(w, "4-notch-finished-pop") }
        notch.model.registry.popQueue.clear()
        await wait(0.6)
        checkCore()
        await checkPomodoro()
        await checkMusic()
        await checkInfo()
        await checkReduceMotion()
        renderSettings()
        await checkVirtualNotch()

        display.setting = original
        log(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        try? report.joined(separator: "\n").write(to: out.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    /// A notch drawn by the app on a screen without one: pill when closed, same states as the real one,
    /// one panel per screen, and only one of them open at a time.
    private static func checkVirtualNotch() async {
        let display = DisplayModeController.shared
        let notch = NotchWindowController.shared
        log("— Virtual notch")
        display.forceVirtualForTesting = true
        display.setting = .allScreens
        await wait(1.0)
        let screens = notch.screens
        check(screens.count == NSScreen.screens.count, "one notch panel per screen (\(screens.count))")
        check(screens.allSatisfy { $0.screen.isVirtual }, "every panel is virtual when forced")
        check(screens.allSatisfy { $0.window.isVisible && $0.window.ignoresMouseEvents }, "closed virtual notches let clicks through")
        check(screens.allSatisfy { $0.window.frame.size == NotchWindowController.windowSize }, "virtual panels keep the fixed window size")
        if let first = screens.first {
            let menuBar = NSScreen.screens.first { $0.displayID == first.screen.display }.map { $0.frame.maxY - $0.visibleFrame.maxY } ?? 0
            check(first.screen.notch.width == 185 && abs(first.screen.notch.height - (menuBar >= 20 ? menuBar : 24)) < 0.5,
                  "virtual notch is 185 × menu bar height (\(first.screen.notch))")
            notch.model.registry.mutedForTesting = true
            await wait(0.6)
            check(notch.model.state(on: first.screen.display) == .closed, "virtual notch closes with no module active")
            check(first.screen.size(for: .closed, contentHeight: 300) == NotchScreen.pill, "closed virtual notch is a 120 × 6 pill")
            let zone = notch.activeRect()
            check(zone.minY >= first.window.frame.maxY - 6.5, "pill hover zone stays at the very top")
            snapshot(first.window, "7-virtual-closed")
            notch.model.registry.mutedForTesting = false
            await wait(0.6)
            if notch.model.live != nil {
                check(notch.model.state(on: first.screen.display) == .live, "virtual notch goes live with an active module")
                snapshot(first.window, "7-virtual-live")
            }

            notch.open(on: first.screen.display)
            await wait(0.9)
            check(notch.model.state(on: first.screen.display) == .expanded, "virtual notch opens")
            check(first.window.ignoresMouseEvents == false, "open virtual notch takes clicks")
            check(screens.dropFirst().allSatisfy { notch.model.state(on: $0.screen.display) != .expanded },
                  "only one screen's notch is open")
            snapshot(first.window, "8-virtual-open")
            notch.close()
            await wait(0.6)

            AppModels.claude.pop(LiveSession(pid: 1, sessionId: nil, cwd: nil, name: "virtual", status: "idle", kind: nil,
                                             startedAt: nil, statusUpdatedAt: nil))
            await wait(1.0)
            check(notch.model.state(on: first.screen.display) == .pop, "virtual notch shows pops")
            snapshot(first.window, "9-virtual-pop")
            notch.model.registry.popQueue.clear()
            await wait(0.6)
        }

        // Switching back to one notch closes and releases the extra panels, never leaving a duplicate.
        display.forceVirtualForTesting = false
        display.setting = .notch
        await wait(0.8)
        check(notch.screens.count == (display.notchScreen == nil ? 0 : 1), "back to a single notch panel")
        check(notch.screens.allSatisfy { !$0.screen.isVirtual }, "notch mode uses only the real notch")
        display.setting = .auto
        await wait(0.8)
        check(notch.screens.count == 1, "auto puts one notch on the menu bar screen")
    }

    /// Pomodoro: wins the live notch, pauses, pops when focus ends, and survives a restart.
    /// Its saved state is put back afterwards so the test leaves no trace in the real stats.
    private static func checkPomodoro() async {
        let notch = NotchWindowController.shared
        let timer = AppModels.pomodoro.timer
        log("— Pomodoro")
        let saved = savedSettings(prefix: "pomodoro.")
        let display = notch.screens.first?.screen.display ?? 0

        timer.runForTesting(phase: .focus, secondsLeft: 8 * 60 + 12)
        await wait(0.8)
        check(notch.model.live?.id == "pomodoro", "running Pomodoro owns the live notch (over Claude)")
        check(notch.model.state(on: display) == .live, "notch is live while focusing")
        if let w = notch.window { snapshot(w, "10-pomodoro-live") }

        timer.pause()
        await wait(0.6)
        check(timer.isPaused && notch.model.live?.id == "pomodoro", "paused Pomodoro stays live")
        check(abs(timer.remaining() - timer.remaining(at: Date().addingTimeInterval(60))) < 0.01, "paused clock doesn't move")
        if let w = notch.window { snapshot(w, "11-pomodoro-paused") }

        timer.runForTesting(phase: .focus, secondsLeft: 9)
        await wait(0.5)
        if let w = notch.window { snapshot(w, "12-pomodoro-last-seconds") }

        let before = (timer.todaySessions, timer.completedInCycle)
        timer.runForTesting(phase: .focus, secondsLeft: 1.2)
        await wait(2.2)
        check(timer.phase == .shortBreak || timer.phase == .longBreak, "focus ending moves on to a break")
        check(timer.todaySessions == before.0 + 1, "finished focus counts in today's stats")
        check(timer.completedInCycle == min(before.1 + 1, PomodoroTimer.sessionsPerCycle), "one more ember lit")
        check(notch.model.pop?.kind == .pomodoro, "focus done pops")
        if let w = notch.window { snapshot(w, "13-pomodoro-focus-done") }
        notch.dismissPop()
        await wait(0.6)
        check(notch.model.live?.id != "pomodoro", "Pomodoro leaves the live notch between phases")

        timer.runForTesting(phase: .shortBreak, secondsLeft: 3 * 60)
        await wait(0.8)
        if let w = notch.window { snapshot(w, "14-pomodoro-break") }
        timer.runForTesting(phase: .shortBreak, secondsLeft: 1.2)
        await wait(2.2)
        check(timer.phase == .focus && notch.model.pop?.kind == .pomodoro, "break ending pops and goes back to focus")
        if let w = notch.window { snapshot(w, "15-pomodoro-break-done") }
        notch.dismissPop()

        // Restart: a fresh clock reads the same end date back.
        timer.runForTesting(phase: .focus, secondsLeft: 600)
        let end = timer.endDate
        let reloaded = PomodoroTimer()
        check(reloaded.isRunning && reloaded.endDate.map { abs($0.timeIntervalSince(end!)) < 0.01 } == true,
              "Pomodoro picks up after a restart")
        // A phase that ran out while the app was closed is finished on launch.
        UserDefaults.standard.set(Date().addingTimeInterval(-30).timeIntervalSince1970, forKey: PomodoroTimer.Keys.endDate)
        let late = PomodoroTimer()
        check(!late.isRunning && late.phase != .focus, "a phase that ended while closed is finished on launch")

        // The card in the open notch.
        timer.runForTesting(phase: .focus, secondsLeft: 17 * 60 + 40)
        notch.open()
        await wait(1.0)
        if let w = notch.window { snapshot(w, "16-pomodoro-card") }
        notch.close()
        await wait(0.6)

        timer.reset()
        restoreSettings(saved, prefix: "pomodoro.")
        timer.restore()
        await wait(0.4)
    }

    /// Music, fed a made-up song and playlist (the self-test never scripts the real Music app).
    private static func checkMusic() async {
        let notch = NotchWindowController.shared
        let bridge = AppModels.music.bridge
        let registry = notch.model.registry
        log("— Music")
        let display = notch.screens.first?.screen.display ?? 0
        let defaults = UserDefaults.standard
        let savedPomodoro = savedSettings(prefix: "pomodoro.")
        registry.onlyForTesting = ["music", "pomodoro"]

        let list = (1...120).map { PlaylistTrack(index: $0, title: "Song number \($0)", artist: "Artist \($0 % 7)", duration: 200) }
        let a = NowPlaying(id: "AAAA", title: "Wait for You", artist: "Elliott Yamin", album: "Wait for You", duration: 261)
        bridge.injectForTesting(track: a, playing: true, position: 74, artwork: testCover(hue: 0.08), playlist: list, currentIndex: 42)
        await wait(0.8)
        check(notch.model.live?.id == "music", "playing music owns the live notch when nothing more important is on")
        check(AppModels.music.livePriority == 4, "music live priority is 4")
        if let w = notch.window { snapshot(w, "17-music-live") }

        let b = NowPlaying(id: "BBBB", title: "A Much Longer Song Title Than Usual", artist: "Someone Else", album: "", duration: 200)
        bridge.injectForTesting(track: b, playing: true, position: 0, artwork: testCover(hue: 0.6), playlist: list, currentIndex: 43)
        await wait(0.7)
        check(notch.model.pop?.kind == .music, "song change pops")
        check(notch.model.state(on: display) == .pop, "notch shows the song pop")
        if let w = notch.window { snapshot(w, "18-music-pop") }
        await wait(2.6)
        check(notch.model.pop == nil, "song pop goes away after 2.5 s")

        bridge.injectForTesting(track: b, playing: false, position: 30, playlist: list, currentIndex: 43)
        await wait(0.4)
        check(notch.model.live == nil, "paused music leaves the live notch")
        check(abs(bridge.currentPosition() - bridge.currentPosition(at: Date().addingTimeInterval(20))) < 0.01,
              "paused position stands still")
        bridge.injectForTesting(track: b, playing: true, position: 30, playlist: list, currentIndex: 43)
        check(bridge.currentPosition(at: Date().addingTimeInterval(10)) > 39, "playing position is worked out locally")

        notch.open()
        await wait(1.0)
        if let w = notch.window { snapshot(w, "19-music-card") }
        bridge.showListForTesting = true
        await wait(1.0)
        if let w = notch.window { snapshot(w, "20-music-playlist") }
        bridge.injectForTesting(track: b, playing: true, position: 30, playlist: [], currentIndex: nil)
        await wait(0.6)
        if let w = notch.window { snapshot(w, "21-music-playlist-unavailable") }
        bridge.showListForTesting = false
        notch.close()
        await wait(0.6)

        // Pomodoro sync: focus plays, a break pauses.
        defaults.set(true, forKey: PomodoroTimer.Keys.musicSync)
        let timer = AppModels.pomodoro.timer
        bridge.injectForTesting(track: b, playing: false, position: 30)
        timer.reset()
        timer.runForTesting(phase: .focus, secondsLeft: 60, paused: true)
        timer.start()
        check(bridge.isPlaying, "focus starting plays music when synced")
        timer.skip()
        timer.start()
        check(!bridge.isPlaying, "a break starting pauses music when synced")
        timer.reset()

        restoreSettings(savedPomodoro, prefix: "pomodoro.")
        timer.restore()
        bridge.injectForTesting(track: nil, playing: false)
        registry.onlyForTesting = nil
        await wait(0.6)
    }

    /// Header line (date, time, battery, next event) and the charger pop, fed made-up readings.
    private static func checkInfo() async {
        let notch = NotchWindowController.shared
        let info = AppModels.info
        log("— Info")
        check(info.livePriority == nil, "info never takes the live notch")
        info.battery.update(.init(percent: 64, charging: false, onPower: false))
        info.calendar.injectForTesting(.init(title: "Design review with the team", start: Date().addingTimeInterval(25 * 60),
                                             end: Date().addingTimeInterval(55 * 60)))
        check(InfoStrip.when(info.calendar.next!, now: Date()).hasPrefix("in 2"), "next event shows how soon it starts")
        notch.open()
        await wait(1.0)
        if let w = notch.window { snapshot(w, "22-info-header") }
        notch.close()
        await wait(0.6)

        info.battery.update(.init(percent: 65, charging: true, onPower: true))
        await wait(0.8)
        check(notch.model.pop?.kind == .info, "plugging in the charger pops")
        if let w = notch.window { snapshot(w, "23-info-charger-pop") }
        await wait(2.0)
        check(notch.model.pop == nil, "charger pop goes away after 2 s")
        info.battery.update(.init(percent: 65, charging: true, onPower: true))
        check(notch.model.pop == nil, "no pop without a new plug-in")

        info.calendar.injectForTesting(nil)
        info.battery.update(nil)
    }

    /// With Reduce Motion forced on, nothing repeats: the dragon in the open notch holds still.
    private static func checkReduceMotion() async {
        let notch = NotchWindowController.shared
        log("— Reduce Motion")
        let saved = savedSettings(prefix: "motion.")
        UserDefaults.standard.set(true, forKey: MotionPreference.forceKey)
        await wait(0.3)
        check(MotionPreference.shared.reduce, "forcing Reduce Motion turns it on")
        notch.open()
        await wait(1.0)
        if let w = notch.window { check(!(await dragonMoves(in: w)), "no repeating animation with Reduce Motion") }
        notch.close()
        await wait(0.6)
        restoreSettings(saved, prefix: "motion.")
        await wait(0.3)
        check(MotionPreference.shared.reduce == NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              "Reduce Motion back to the system setting")
    }

    /// Each Settings tab, drawn on black (system switches and pickers may show as placeholders).
    private static func renderSettings() {
        let original = UserDefaults.standard.object(forKey: "settingsTab")
        for tab in 0..<6 {
            UserDefaults.standard.set(tab, forKey: "settingsTab")
            let view = SettingsView()
                .environmentObject(DisplayModeController.shared)
                .frame(width: 344)
                .padding(14)
                .background(Color.black)
                .preferredColorScheme(.dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: out.appendingPathComponent("24-settings-\(tab).png"))
        }
        UserDefaults.standard.set(original, forKey: "settingsTab")
        log("saved 24-settings-*.png")
    }

    /// A stand-in album cover: a soft two-colour gradient.
    private static func testCover(hue: Double) -> NSImage {
        NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
            NSGradient(starting: NSColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1),
                       ending: NSColor(hue: hue + 0.15, saturation: 0.8, brightness: 0.4, alpha: 1))?.draw(in: rect, angle: -45)
            return true
        }
    }

    /// The module plumbing on its own: who wins the live notch, and in what order pops show.
    private static func checkCore() {
        let a = FakeModule(id: "a", priority: 4), b = FakeModule(id: "b", priority: 1), c = FakeModule(id: "c", priority: nil)
        check(PriorityResolver.resolve([a, b, c])?.id == "b", "resolver picks the smallest priority")
        check(PriorityResolver.resolve([c]) == nil, "resolver: nothing active means closed")
        check(PriorityResolver.resolve([FakeModule(id: "x", priority: 2), FakeModule(id: "y", priority: 2)])?.id == "x",
              "resolver: ties go to the first registered")
        check(PriorityResolver.resolve([a, b], order: ["a", "b"])?.id == "a", "a custom order beats the built-in priorities")
        check(PriorityResolver.resolve([a, b], order: ["b", "a"])?.id == "b", "custom order is followed both ways")

        let registry = AppModels.registry
        let savedModules = savedSettings(prefix: "modules.")
        let savedPomodoro = savedSettings(prefix: "pomodoro.")
        registry.onlyForTesting = ["pomodoro"]
        AppModels.pomodoro.timer.runForTesting(phase: .focus, secondsLeft: 300, paused: true)
        registry.resolve()
        check(registry.active?.id == "pomodoro", "enabled module takes the live notch")
        registry.setEnabled("pomodoro", false)
        check(registry.active == nil, "a switched-off module never takes the live notch")
        check(!registry.enabledModules.contains { $0.id == "pomodoro" }, "a switched-off module shows no card")
        registry.setEnabled("pomodoro", true)
        AppModels.pomodoro.timer.reset()
        restoreSettings(savedPomodoro, prefix: "pomodoro.")
        AppModels.pomodoro.timer.restore()
        registry.onlyForTesting = nil
        restoreSettings(savedModules, prefix: "modules.")
        registry.setOrder(UserDefaults.standard.stringArray(forKey: "modules.order"))

        let queue = PopQueue()
        queue.enqueue(NotchPop(kind: .music) { EmptyView() })
        queue.enqueue(NotchPop(kind: .music) { EmptyView() })
        queue.enqueue(NotchPop(kind: .claude) { EmptyView() })
        queue.enqueue(NotchPop(kind: .pomodoro) { EmptyView() })
        check(queue.current?.kind == .music && queue.pending.map(\.kind) == [.pomodoro, .claude, .music],
              "pop queue keeps the showing pop and orders the rest Pomodoro, Claude, music")
        queue.dismiss()
        check(queue.current?.kind == .pomodoro, "pop queue moves on to the next pop")
        queue.clear()
        queue.canShow = { false }
        queue.enqueue(NotchPop(kind: .claude) { EmptyView() })
        check(queue.current == nil, "no pops while expanded")
    }

    @MainActor
    private final class FakeModule: NotchModule {
        let id: String
        let livePriority: Int?
        let pops = AsyncStream<NotchPop> { $0.finish() }
        init(id: String, priority: Int?) { self.id = id; livePriority = priority }
        func liveLeading() -> AnyView { AnyView(EmptyView()) }
        func liveTrailing() -> AnyView { AnyView(EmptyView()) }
        func expandedCard() -> AnyView? { nil }
        func setVisible(_ visible: Bool) {}
    }

    // MARK: Helpers

    /// The app's own saved settings starting with `prefix` (not the registered defaults).
    private static func savedSettings(prefix: String) -> [String: Any] {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        return domain.filter { $0.key.hasPrefix(prefix) }
    }

    /// Puts settings starting with `prefix` back exactly as they were, removing any the test added.
    private static func restoreSettings(_ saved: [String: Any], prefix: String) {
        let defaults = UserDefaults.standard
        for key in savedSettings(prefix: prefix).keys where saved[key] == nil { defaults.removeObject(forKey: key) }
        for (key, value) in saved { defaults.set(value, forKey: key) }
    }

    private static func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private static func check(_ ok: Bool, _ what: String) {
        if !ok { failures += 1 }
        log("\(ok ? "PASS" : "FAIL")  \(what)")
    }

    private static func log(_ line: String) {
        report.append(line)
        print(line)
    }

    private static func clickStatusItem() async {
        StatusItemController.shared.statusButton?.performClick(nil)
        await wait(0.8)
    }

    private static func closePopover() async {
        StatusItemController.shared.close()
        await wait(0.4)
    }

    private static func popoverWindow() -> NSWindow? { StatusItemController.shared.panel }

    /// How many working menu bar icons this app has: status windows holding a button, placed in the menu bar.
    private static func visibleIcons() -> Int {
        let bars = NSApp.windows.filter { String(describing: type(of: $0)).contains("StatusBar") }
        log("   status windows: " + bars.map {
            "vis=\($0.isVisible) button=\(find(NSStatusBarButton.self, in: $0.contentView) != nil) frame=\(NSStringFromRect($0.frame))"
        }.joined(separator: ", "))
        return bars.filter { $0.isVisible && find(NSStatusBarButton.self, in: $0.contentView) != nil }.count
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for sub in view.subviews { if let match = find(type, in: sub) { return match } }
        return nil
    }

    /// Every dragon mood, large and at the sizes the app uses, on black.
    private static func renderDragons() {
        let moods: [DragonMood] = [.sleeping, .idle, .working, .happy]
        // The roar, frame by frame (one cycle is 2.6 s): building up, full fire, settling.
        let roar = [0.15, 0.4, 0.9, 1.5, 1.85].map { 2600.0 + $0 }
        let sheet = VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 24) { ForEach(moods.indices, id: \.self) { DragonView(mood: moods[$0], size: 160, at: 2600.5) } }
            HStack(spacing: 0) { ForEach(roar.indices, id: \.self) { DragonView(mood: .happy, size: 100, at: roar[$0], fireRoom: 0.6) } }
            HStack(spacing: 24) {
                ForEach(moods.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        DragonView(mood: moods[i], size: 44, at: 2601)
                        DragonView(mood: moods[i], size: 34, at: 2601)
                        DragonView(mood: moods[i], size: 26, at: 2601)
                    }
                    .frame(width: 160)
                }
            }
        }
        .padding(30)
        .background(Color.black)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: out.appendingPathComponent("0-dragons.png"))
        log("saved 0-dragons.png")
    }

    /// Captures the window twice, half a second apart, and checks that the header avatar (the dragon) changed.
    private static func dragonMoves(in window: NSWindow) async -> Bool {
        func capture() -> NSBitmapImageRep? {
            guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: rep)
            return rep
        }
        guard let a = capture() else { return false }
        await wait(0.5)
        guard let b = capture(), a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return false }
        // The avatar is the first thing on the left of the header: find the topmost opaque row, then scan below it.
        var top = 0
        while top < a.pixelsHigh - 1, (a.colorAt(x: a.pixelsWide / 2, y: top)?.alphaComponent ?? 0) < 0.5 { top += 1 }
        let scale = a.pixelsWide / Int(window.frame.width)
        let notchOffset = window === NotchWindowController.shared.window ? Int(NotchWindowController.shared.screens.first?.screen.notch.height ?? 0) - 8 : 0
        let x0 = (window.frame.width > 400 ? (Int(window.frame.width) - 376) / 2 : 0) * scale
        let y0 = top + notchOffset * scale
        var changed = 0
        for y in y0..<min(a.pixelsHigh, y0 + 70 * scale) {
            for x in x0..<min(a.pixelsWide, x0 + 70 * scale) where a.colorAt(x: x, y: y) != b.colorAt(x: x, y: y) {
                changed += 1
            }
        }
        log("   \(changed) pixels changed around the dragon")
        return changed > 20
    }

    private static func snapshot(_ window: NSWindow, _ name: String) {
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        // Composite on a desktop-like grey so the glass and black edges are visible in the picture.
        let size = view.bounds.size
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(srgbRed: 0.32, green: 0.34, blue: 0.38, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        rep.draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: out.appendingPathComponent("\(name).png"))
        log("saved \(name).png")
    }
}
