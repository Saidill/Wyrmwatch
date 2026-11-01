import AppKit

/// Where the app lives: in the menu bar, in the MacBook notch, or in a notch drawn on screens without one.
enum DisplayMode: String, CaseIterable, Identifiable {
    case auto, notch, menuBar, allScreens
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .notch: return "Notch"
        case .menuBar: return "Menu bar"
        case .allScreens: return "All screens"
        }
    }
}

/// Picks the mode actually in use and switches live when screens come and go.
@MainActor
final class DisplayModeController: ObservableObject {
    static let shared = DisplayModeController()

    @Published var setting: DisplayMode {
        didSet {
            UserDefaults.standard.set(setting.rawValue, forKey: Settings.displayModeKey)
            update()
        }
    }
    /// True when the app is shown in a notch (real or virtual) rather than the menu bar.
    @Published private(set) var isNotch = false
    /// The built-in screen with a notch, if there is one.
    @Published private(set) var notchScreen: NSScreen?
    /// Self-test only: draw virtual notches even on a screen that has a real one.
    var forceVirtualForTesting = false {
        didSet { update() }
    }

    private init() {
        setting = UserDefaults.standard.string(forKey: Settings.displayModeKey).flatMap(DisplayMode.init) ?? .auto
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
        notchScreen = NSScreen.screens.first { $0.notchSize != nil }
        isNotch = !resolve(setting).isEmpty
        // The notch window refers back to `shared`, so build it once this initializer has returned.
        DispatchQueue.main.async { self.update() }
    }

    /// Flips between the menu bar and the notch (the header button).
    func toggle() {
        setting = isNotch ? .menuBar : (notchScreen != nil ? .notch : .auto)
    }

    private func update() {
        let targets = resolve(setting)
        notchScreen = NSScreen.screens.first { $0.notchSize != nil }
        let notch = !targets.isEmpty
        if notch != isNotch { isNotch = notch }
        StatusItemController.shared.setVisible(!notch)
        NotchWindowController.shared.show(on: targets)
    }

    /// Which screens get a notch, and whether it is the real one or drawn by the app.
    private func resolve(_ setting: DisplayMode) -> [NotchTarget] {
        let screens = NSScreen.screens
        func target(_ screen: NSScreen) -> NotchTarget {
            NotchTarget(screen: screen, isVirtual: forceVirtualForTesting || screen.notchSize == nil)
        }
        switch setting {
        case .menuBar:
            return []
        case .notch:
            // Only the real notch; with no notched screen there is nowhere to go but the menu bar.
            return screens.first { $0.notchSize != nil }.map { [target($0)] } ?? []
        case .auto:
            // The screen with the menu bar: its own notch, or a virtual one on an external monitor.
            return screens.first.map { [target($0)] } ?? []
        case .allScreens:
            return screens.map(target)
        }
    }
}
