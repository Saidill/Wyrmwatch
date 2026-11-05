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
        let originalNotchTab = UserDefaults.standard.object(forKey: NotchTab.storageKey)
        notch.holdOpenForTesting = true
        // A real pointer resting on the notch would hold pops open; the timing checks must not depend on it.
        notch.model.registry.popQueue.isHovering = { false }
        await wait(1.5) // let the app finish launching

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
        UserDefaults.standard.set(originalNotchTab, forKey: NotchTab.storageKey)
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
            // Every tab again, on the virtual notch, with a song on.
            AppModels.music.bridge.injectForTesting(
                track: NowPlaying(id: "VIRT", title: "Wait for You", artist: "Elliott Yamin", album: "Wait for You", duration: 261),
                playing: true, position: 40, artwork: testCover(hue: 0.02),
                playlist: (1...30).map { PlaylistTrack(index: $0, title: "Song \($0)", artist: "", duration: 200) }, currentIndex: 4)
            await checkTabs("virtual")
            AppModels.music.bridge.injectForTesting(track: nil, playing: false)

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
        notch.model.registry.popQueue.clear()
        timer.runForTesting(phase: .focus, secondsLeft: 1.2)
        await wait(2.2)
        check(timer.phase == .shortBreak || timer.phase == .longBreak, "focus ending moves on to a break")
        check(timer.isRunning && abs(timer.remaining() - timer.duration(of: timer.phase)) < 3,
              "the break starts counting down by itself (\(Int(timer.remaining())) s left)")
        check(timer.todaySessions == before.0 + 1, "finished focus counts in today's stats")
        check(timer.completedInCycle == min(before.1 + 1, timer.sessionsTarget), "one more ember lit")
        check(pomodoroPopped(), "focus done pops")
        if let w = notch.window { snapshot(w, "13-pomodoro-focus-done") }
        notch.dismissPop()
        await wait(0.6)
        check(notch.model.live?.id == "pomodoro", "the break counts down in the live notch")

        timer.runForTesting(phase: .shortBreak, secondsLeft: 3 * 60)
        await wait(0.8)
        if let w = notch.window { snapshot(w, "14-pomodoro-break") }
        notch.model.registry.popQueue.clear()
        timer.runForTesting(phase: .shortBreak, secondsLeft: 1.2)
        await wait(2.2)
        check(timer.phase == .focus, "break ending goes back to focus")
        check(pomodoroPopped(), "break ending pops")
        if let w = notch.window { snapshot(w, "15-pomodoro-break-done") }
        notch.dismissPop()

        // Restart: a fresh clock reads the same end date back.
        timer.runForTesting(phase: .focus, secondsLeft: 600)
        let end = timer.endDate
        let reloaded = PomodoroTimer()
        check(reloaded.isRunning && reloaded.endDate.map { abs($0.timeIntervalSince(end!)) < 0.01 } == true,
              "Pomodoro picks up after a restart")
        // A phase that ran out while the app was closed is finished on launch.
        // Focus ran out 30 s before launch: the break has been running since then.
        UserDefaults.standard.set(PomodoroTimer.Phase.focus.rawValue, forKey: PomodoroTimer.Keys.phase)
        UserDefaults.standard.set(Date().addingTimeInterval(-30).timeIntervalSince1970, forKey: PomodoroTimer.Keys.endDate)
        let late = PomodoroTimer()
        check(late.isRunning && late.phase.isBreak && abs(late.remaining() - (late.duration(of: late.phase) - 30)) < 3,
              "a focus that ended while closed is in its break, counted from when it ended")
        // Ran out two hours ago: the break is long over too, so the next focus waits.
        UserDefaults.standard.set(PomodoroTimer.Phase.focus.rawValue, forKey: PomodoroTimer.Keys.phase)
        UserDefaults.standard.set(Date().addingTimeInterval(-7200).timeIntervalSince1970, forKey: PomodoroTimer.Keys.endDate)
        let later = PomodoroTimer()
        check(!later.isRunning && later.phase == .focus, "focus and break both over while closed: back to the setup")

        // The Focus page: setup while stopped, digits, fuse and controls while running.
        timer.stopToSetup()
        timer.task = "Write the PRD"
        timer.sessionsTarget = 4
        await snapshotExpanded(tab: .focus, "16-focus-setup")
        timer.runForTesting(phase: .focus, secondsLeft: 17 * 60 + 40)
        await snapshotExpanded(tab: .focus, "16-focus-running")
        let left = timer.remaining()
        timer.addFiveMinutes()
        check(abs(timer.remaining() - left - 300) < 1, "+5 min adds five minutes")
        check(timer.fractionLeft() <= 1, "fuse stays full or shorter after +5 min")
        timer.stopToSetup()
        check(!timer.isActive && timer.phase == .focus && timer.completedInCycle == 0, "Stop goes back to the setup")
        check(PomodoroTimer().task == "Write the PRD", "the setup (task, lengths) is kept for next time")

        // The session count decides when the long break comes.
        timer.sessionsTarget = 2
        timer.runForTesting(phase: .focus, secondsLeft: 0.6)
        await wait(1.4)
        check(timer.phase == .shortBreak, "after focus 1 of 2: a short break")
        notch.dismissPop()
        timer.runForTesting(phase: .focus, secondsLeft: 0.6)
        await wait(1.4)
        check(timer.phase == .longBreak, "after focus 2 of 2: the long break")
        notch.dismissPop()
        timer.stopToSetup()

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

        await snapshotExpanded(tab: .music, "19-music-page")
        bridge.injectForTesting(track: b, playing: true, position: 30, playlist: [], currentIndex: nil)
        await snapshotExpanded(tab: .music, "21-music-playlist-unavailable")

        // An Apple Music stream: the notification has no persistent ID, but the song must still show at once.
        bridge.injectForTesting(track: a, playing: true, position: 10)
        let stream: [AnyHashable: Any] = ["Name": "Out of the Blue", "Artist": "Michael Learns to Rock",
                                          "Album": "Strange Foreign Beauty", "Total Time": 244_466, "Player State": "Playing"]
        bridge.handleForTesting(stream)
        check(bridge.track?.title == "Out of the Blue" && bridge.isPlaying && abs((bridge.track?.duration ?? 0) - 244.5) < 1,
              "a streamed song (no persistent ID) shows up straight from the notification")
        let streamID = bridge.track?.id
        var paused = stream
        paused["Player State"] = "Paused"
        bridge.handleForTesting(paused)
        check(!bridge.isPlaying && bridge.track?.id == streamID, "pausing the stream is a pause, not a new song")
        notch.model.registry.popQueue.clear()
        bridge.injectForTesting(track: b, playing: true, position: 30, playlist: list, currentIndex: 43)

        // Pomodoro and music both on: the live notch takes turns between them.
        AppModels.pomodoro.timer.runForTesting(phase: .focus, secondsLeft: 600)
        await wait(0.4)
        let turns = registry.liveRotation(fallback: AppModels.music).map(\.id)
        check(turns == ["pomodoro", "music"], "live notch alternates Pomodoro and music (\(turns))")
        if let w = notch.window { snapshot(w, "17-live-alternating") }
        AppModels.pomodoro.timer.stopToSetup()

        bridge.injectForTesting(track: b, playing: true, position: 74, artwork: testCover(hue: 0.6), playlist: list, currentIndex: 43)
        await checkTabs("real", variants: true)

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

    /// The next calendar event (fed a made-up one); Info never takes the live notch and never pops.
    private static func checkInfo() async {
        let info = AppModels.info
        log("— Info")
        check(info.livePriority == nil, "info never takes the live notch")
        info.calendar.injectForTesting(.init(title: "Design review with the team", start: Date().addingTimeInterval(25 * 60),
                                             end: Date().addingTimeInterval(55 * 60)))
        check(NextEventLabel.when(info.calendar.next!, now: Date()).hasPrefix("in 2"), "next event shows how soon it starts")
        check(NextEventLabel.when(.init(title: "x", start: Date().addingTimeInterval(-60), end: Date().addingTimeInterval(600)),
                                  now: Date()) == "now", "an event under way shows as now")
        await snapshotExpanded(tab: .focus, "22-info-header")
        info.calendar.injectForTesting(nil)
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
        if let w = notch.window { check(!(await animationsRunning(in: w)), "no repeating animation with Reduce Motion") }
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

    /// A Pomodoro pop is showing or next in line (a real Claude pop may have arrived during the test).
    private static func pomodoroPopped() -> Bool {
        let queue = NotchWindowController.shared.model.registry.popQueue
        return queue.current?.kind == .pomodoro || queue.pending.contains { $0.kind == .pomodoro }
    }

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

    /// Whether anything in the window repeats: a Core Animation layer (status dot, working dots, visualizer)
    /// carrying an animation.
    private static func animationsRunning(in window: NSWindow) async -> Bool {
        await wait(0.3)
        func layers(_ layer: CALayer) -> [CALayer] { [layer] + (layer.sublayers ?? []).flatMap(layers) }
        guard let root = window.contentView?.layer else { return false }
        let animating = layers(root).filter { !($0.animationKeys() ?? []).isEmpty }
        log("   \(animating.count) animating layers")
        return !animating.isEmpty
    }

    /// Every tab of the open notch: 600 wide, the height following the page, nothing overlapping or spilling out,
    /// and a picture. With `variants`, Home is also checked with the Pomodoro running and with no music.
    private static func checkTabs(_ label: String, variants: Bool = false) async {
        let notch = NotchWindowController.shared
        guard let screen = notch.screens.first?.screen else { return }
        func verify(_ what: String, _ name: String) {
            let overlaps = LayoutProbe.overlaps(prefix: "")
            check(overlaps.isEmpty, "\(label): nothing overlaps on \(what)"
                  + (overlaps.isEmpty ? "" : " — " + overlaps.map { "\($0.0)×\($0.1)" }.joined(separator: ", ")))
            let outside = LayoutProbe.frames.filter { $0.value.minX < -0.5 || $0.value.maxX > ExpandedPanel.width + 0.5 }
            check(outside.isEmpty, "\(label): \(what) stays inside the panel" + (outside.isEmpty ? "" : " — \(outside.keys.sorted())"))
            check(!LayoutProbe.frames.isEmpty, "\(label): \(what) was measured")
            if let w = notch.window { snapshot(w, name) }
        }
        var heights: [NotchTab: CGFloat] = [:]
        for tab in NotchTab.allCases {
            UserDefaults.standard.set(tab.rawValue, forKey: NotchTab.storageKey)
            if !notch.model.expanded { notch.open(on: screen.display) }
            await wait(1.0)
            heights[tab] = notch.model.contentHeight
            let size = screen.size(for: .expanded, contentHeight: notch.model.contentHeight)
            check(abs(size.width - (ExpandedPanel.width + 20)) < 0.5 && notch.window?.frame.size == NotchWindowController.windowSize,
                  "\(label): \(tab.title) is 600 wide and the window never resizes")
            verify(tab.title, "tab-\(tab.rawValue)-\(label)")
        }
        check(abs((heights[.home] ?? 0) - HomePage.height) < 1, "\(label): Home cards are \(Int(HomePage.height)) pt tall (\(Int(heights[.home] ?? 0)))")
        check((heights[.music] ?? 0) > (heights[.home] ?? 0) + 10,
              "\(label): the notch height follows the page (home \(Int(heights[.home] ?? 0)), music \(Int(heights[.music] ?? 0)))")
        if variants {
            let timer = AppModels.pomodoro.timer
            UserDefaults.standard.set(NotchTab.home.rawValue, forKey: NotchTab.storageKey)
            timer.task = "A long task name that has to be cut off with an ellipsis somewhere"
            timer.runForTesting(phase: .focus, secondsLeft: 24 * 60 + 59)
            await wait(0.8)
            verify("Home with the Pomodoro running", "tab-home-focus-\(label)")
            UserDefaults.standard.set(NotchTab.focus.rawValue, forKey: NotchTab.storageKey)
            await wait(0.8)
            verify("Focus while running", "tab-focus-running-\(label)")
            timer.stopToSetup()
            AppModels.music.bridge.injectForTesting(track: nil, playing: false)
            UserDefaults.standard.set(NotchTab.home.rawValue, forKey: NotchTab.storageKey)
            await wait(0.8)
            check(LayoutProbe.frames["home.startMusic"] != nil, "\(label): Home offers Play music when nothing plays")
            verify("Home with no music", "tab-home-nomusic-\(label)")
        }
        notch.close()
        await wait(0.6)
    }

    /// Opens the notch on one page, saves a picture of it, and closes it again.
    private static func snapshotExpanded(tab: NotchTab, _ name: String, keepOpen: Bool = false) async {
        let notch = NotchWindowController.shared
        UserDefaults.standard.set(tab.rawValue, forKey: NotchTab.storageKey)
        if !notch.model.expanded { notch.open() }
        await wait(1.0)
        if let w = notch.window { snapshot(w, name) }
        if !keepOpen {
            notch.close()
            await wait(0.6)
        }
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
