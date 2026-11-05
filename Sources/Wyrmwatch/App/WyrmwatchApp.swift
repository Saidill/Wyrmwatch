import SwiftUI

@main
struct WyrmwatchApp: App {
    init() {
        // Build step: draw the app icon and quit before anything else starts.
        IconRenderer.renderIfRequested()
        // The app used to be "ClaudeUsage"; bring its settings along once.
        SettingsMigration.runOnce()
        // Black theme: keep window chrome, tooltips and system controls dark too.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        // The menu bar icon and the notch are AppKit windows, managed by the display mode.
        _ = DisplayModeController.shared
        SelfTest.startIfRequested()
        Diagnose.startIfRequested()
        Perf.startIfRequested()
    }

    var body: some Scene {
        // Everything lives in the menu bar icon or the notch; this app has no regular windows.
        SwiftUI.Settings { EmptyView() }
    }
}

/// The app's name as the bundle has it.
enum AppInfo {
    static var name: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Wyrmwatch" }
}

/// One copy of each model, shared by the menu bar popover and the notch.
@MainActor
enum AppModels {
    static let sessions = SessionMonitor()
    static let usage = UsageTracker()
    static let limits = PlanLimitClient()
    static let recent = RecentSessionStore()

    static let claude = ClaudeModule(sessions: sessions, limits: limits)
    static let pomodoro = PomodoroModule(timer: PomodoroTimer())
    static let music = MusicModule(bridge: MusicBridge(offline: SelfTest.isRequested || Perf.isRequested), pomodoro: pomodoro.timer)
    static let info = InfoModule(calendar: CalendarSource(live: !SelfTest.isRequested && !Perf.isRequested))
    /// Every notch module, in tie-break order.
    static let registry: ModuleRegistry = {
        let registry = ModuleRegistry()
        registry.register(pomodoro)
        registry.register(claude)
        registry.register(music)
        registry.register(info)
        return registry
    }()
}

enum MenuBarMode: String, CaseIterable, Identifiable {
    case tasks, fiveHour
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tasks: return "Working sessions"
        case .fiveHour: return "Session limit %"
        }
    }
}

enum Settings {
    static let soundKey = "soundName"
    static let notifyKey = "notificationsEnabled"
    static let soundEnabledKey = "soundEnabled"
    static let menuBarModeKey = "menuBarMode"
    static let limitAlertsKey = "limitAlertsEnabled"
    static let limitThresholdKey = "limitAlertThreshold"
    static let resetPingKey = "resetPingEnabled"
    static let displayModeKey = "displayMode"
}

/// Copies settings saved under the app's old bundle ID (com.saidilhalim.claudeusage) the first time Wyrmwatch runs,
/// without overwriting anything Wyrmwatch already has.
enum SettingsMigration {
    private static let oldDomain = "com.saidilhalim.claudeusage"
    private static let doneKey = "migratedFromClaudeUsage"

    static func runOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)
        guard let old = UserDefaults.standard.persistentDomain(forName: oldDomain) else { return }
        let mine = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        for (key, value) in old where mine[key] == nil { defaults.set(value, forKey: key) }
    }
}
