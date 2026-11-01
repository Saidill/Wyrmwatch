import AppKit
import Combine
import SwiftUI

/// What the notch is showing. Shared by every screen's panel; the SwiftUI view animates between the states.
@MainActor
final class NotchModel: ObservableObject {
    enum State: Equatable { case closed, live, pop, expanded }

    let registry: ModuleRegistry
    /// The screen whose notch is open, if any. Only one panel may be expanded at a time.
    @Published var expandedOn: CGDirectDisplayID?
    /// Height of the full app content, measured by the view, so the shape fits it exactly.
    @Published var contentHeight: CGFloat = 300
    private var subscriptions: Set<AnyCancellable> = []

    init(registry: ModuleRegistry) {
        self.registry = registry
        // The state follows the active module and the pop queue.
        registry.objectWillChange.merge(with: registry.popQueue.objectWillChange)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
    }

    /// Whether the notch is open on any screen.
    var expanded: Bool { expandedOn != nil }
    /// The module that owns the live notch, if any.
    var live: (any NotchModule)? { registry.active }
    /// The pop showing right now, if any.
    var pop: NotchPop? { registry.popQueue.current }

    /// State of the notch on one screen.
    func state(on display: CGDirectDisplayID) -> State {
        if expandedOn == display { return .expanded }
        if pop != nil, expandedOn == nil { return .pop }
        return live != nil ? .live : .closed
    }

    /// State of the notch overall (expanded if it is open anywhere).
    var state: State {
        if expanded { return .expanded }
        if pop != nil { return .pop }
        return live != nil ? .live : .closed
    }
}

/// One screen's notch: the hardware notch, or a virtual one drawn on a screen without it.
@MainActor
final class NotchScreen: ObservableObject {
    let display: CGDirectDisplayID
    /// Size of the (real or virtual) notch.
    @Published var notch: CGSize
    /// Drawn by the app on a screen without a camera notch.
    @Published var isVirtual: Bool
    /// A fullscreen app is covering this screen, so the virtual notch keeps out of the way.
    @Published var coveredByFullscreen = false

    init(display: CGDirectDisplayID, notch: CGSize, isVirtual: Bool) {
        self.display = display
        self.notch = notch
        self.isVirtual = isVirtual
    }

    /// The small pill a closed virtual notch shrinks to, so it doesn't cover the menu bar.
    static let pill = CGSize(width: 120, height: 6)

    /// Outer size of the black shape (including the little flares at its top corners) in each state.
    func size(for state: NotchModel.State, contentHeight: CGFloat) -> CGSize {
        let flare = NotchShape.flare(for: state, virtual: isVirtual)
        switch state {
        case .closed:
            return isVirtual ? Self.pill : CGSize(width: notch.width + flare * 2, height: notch.height)
        case .live: return CGSize(width: notch.width + 100 + flare * 2, height: notch.height)
        // Just big enough for one row (a 44 pt picture and two lines of text, or a button).
        case .pop: return CGSize(width: 320 + flare * 2, height: notch.height + 58)
        // The same size on every page: wide rather than tall.
        case .expanded:
            return CGSize(width: ExpandedPanel.width + flare * 2, height: notch.height + 8 + ExpandedPanel.pageHeight + 14)
        }
    }
}

/// Borderless panel that floats over the menu bar and can take clicks without activating the app.
private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Where a notch goes: a screen, and whether the notch there is drawn by the app.
struct NotchTarget {
    let screen: NSScreen
    let isVirtual: Bool
}

/// Owns the notch windows (one per screen in use): placement, hover to open, pops, and click-through when closed.
@MainActor
final class NotchWindowController {
    static let shared = NotchWindowController()
    /// The window never resizes (that's what made things lag); the shape animates inside it.
    static let windowSize = CGSize(width: 640, height: 260)
    /// Settings: open when the pointer rests on the notch (otherwise only a click opens it).
    static let openOnHoverKey = "notch.openOnHover"

    let model = NotchModel(registry: AppModels.registry)
    private var popQueue: PopQueue { model.registry.popQueue }
    private var panels: [CGDirectDisplayID: (panel: NotchPanel, screen: NotchScreen)] = [:]
    /// The self-test can't move the real pointer, so it keeps the notch open itself.
    var holdOpenForTesting = false
    private var monitors: [Any] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var openTask: Task<Void, Never>?
    private var pointerTimer: Timer?
    /// When the pointer left the open panel; it closes once it has been away long enough.
    private var leftAt: Date?
    /// The screen the pointer is resting on the notch of, if any.
    private var hoveredDisplay: CGDirectDisplayID?
    private var hovering: Bool { hoveredDisplay != nil }

    private init() {
        UserDefaults.standard.register(defaults: [Self.openOnHoverKey: true])
        // Pops show only while a notch is on screen and not open; a pop stays while the pointer is on it.
        popQueue.canShow = { [weak self] in
            guard let self else { return false }
            return !self.panels.isEmpty && !self.model.expanded
        }
        popQueue.isHovering = { [weak self] in self?.hovering ?? false }
        model.$expandedOn.map { _ in () }.merge(with: popQueue.$current.map { _ in () }, model.registry.$active.map { _ in () })
            .sink { [weak self] _ in Task { @MainActor in self?.updateWindows() } }
            .store(in: &subscriptions)
        let spaces = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            spaces.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Give a space switch a moment to settle before looking at the windows on it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    MainActor.assumeIsolated { self?.updateFullscreen() }
                }
            }
        }
    }

    /// The panel on the screen that is (or was last) open, else the first one. Kept for the self-test.
    var window: NSWindow? {
        if let open = model.expandedOn, let entry = panels[open] { return entry.panel }
        return panels.values.sorted { $0.screen.display < $1.screen.display }.first?.panel
    }

    /// Every notch panel and its screen.
    var screens: [(window: NSWindow, screen: NotchScreen)] {
        panels.values.map { ($0.panel, $0.screen) }.sorted { $0.screen.display < $1.screen.display }
    }

    /// Shows a notch on each target; panels for screens no longer targeted are closed and released.
    func show(on targets: [NotchTarget]) {
        var keep = Set<CGDirectDisplayID>()
        for target in targets {
            guard let display = target.screen.displayID else { continue }
            let notch = target.isVirtual ? target.screen.virtualNotchSize : (target.screen.notchSize ?? target.screen.virtualNotchSize)
            keep.insert(display)
            let entry = panels[display] ?? makePanel(display: display, notch: notch, isVirtual: target.isVirtual)
            panels[display] = entry
            entry.screen.notch = notch
            entry.screen.isVirtual = target.isVirtual
            let size = Self.windowSize
            let frame = target.screen.frame
            entry.panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                                        width: size.width, height: size.height), display: true)
        }
        // Screens that went away (or aren't used any more): close the panel for good, not just hide it.
        for (display, entry) in panels where !keep.contains(display) {
            if model.expandedOn == display { close() }
            entry.panel.orderOut(nil)
            entry.panel.contentView = nil
            entry.panel.close()
            panels[display] = nil
        }
        if panels.isEmpty {
            stopMonitoring()
            close()
            popQueue.clear()
        } else {
            startMonitoring()
        }
        updateFullscreen()
        updateWindows()
    }

    private func makePanel(display: CGDirectDisplayID, notch: CGSize, isVirtual: Bool) -> (panel: NotchPanel, screen: NotchScreen) {
        let panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.windowSize),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true // so moves over the open panel reach the local monitor
        panel.isReleasedWhenClosed = false

        let screen = NotchScreen(display: display, notch: notch, isVirtual: isVirtual)
        let root = NotchView(model: model, screen: screen)
            .environmentObject(AppModels.sessions)
            .environmentObject(AppModels.usage)
            .environmentObject(AppModels.limits)
            .environmentObject(AppModels.recent)
            .environmentObject(DisplayModeController.shared)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = [] // keep the window a fixed size
        panel.contentView = host
        return (panel, screen)
    }

    // MARK: Pop

    /// Jump button on the pop.
    func jump(to session: LiveSession) {
        TerminalLauncher.focus(session)
        popQueue.dismiss()
    }

    /// A button on the pop was used: hide it and show the next one.
    func dismissPop() {
        popQueue.dismiss()
    }

    /// Clicking the pop opens the full app.
    func expand() {
        popQueue.clear()
        open(on: hoveredDisplay)
    }

    // MARK: Hover

    private func startMonitoring() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        // Monitors call back on the main thread, so handle the event right away instead of queueing it.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }) { monitors.append(global) }
        // A click on the closed notch (it lets clicks through, so this sees them) opens it at once.
        if let click = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clicked() }
        }) { monitors.append(click) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.checkPointer() }
            return event
        }) { monitors.append(local) }
    }

    private func stopMonitoring() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    /// The area that counts as "on the notch" right now, in screen coordinates (first panel, for the self-test).
    func activeRect() -> NSRect {
        guard let entry = panels.values.first(where: { $0.panel === window }) else { return .zero }
        return activeRect(entry.panel, entry.screen)
    }

    private func activeRect(_ panel: NSPanel, _ screen: NotchScreen) -> NSRect {
        guard panel.isVisible else { return .zero }
        let state = model.state(on: screen.display)
        let size = screen.size(for: state, contentHeight: model.contentHeight)
        let rect = NSRect(x: panel.frame.midX - size.width / 2, y: panel.frame.maxY - size.height,
                          width: size.width, height: size.height)
        if state == .expanded {
            // Open: generous slack all round, so it doesn't snap shut at the edge while you use it.
            return rect.insetBy(dx: -20, dy: -20)
        }
        if state == .closed, screen.isVirtual {
            // The pill is tiny: count the whole width a virtual notch would take, but still only the top strip.
            let width = screen.notch.width
            return NSRect(x: panel.frame.midX - width / 2, y: rect.minY, width: width, height: rect.height + 10)
        }
        // Closed: just the notch, never below it, so reaching for browser tabs under the notch can't open it.
        // It does reach past the top of the screen: a pointer pushed against the top edge sits exactly on it,
        // and `contains` treats the edge as outside.
        return NSRect(x: rect.minX - 6, y: rect.minY, width: rect.width + 12, height: rect.height + 10)
    }

    /// Called on every mouse move while closed, and on a short timer while open
    /// (an open panel takes the mouse, and macOS doesn't always report moves inside it).
    private func checkPointer() {
        let location = NSEvent.mouseLocation
        let under = panels.first { activeRect($0.value.panel, $0.value.screen).contains(location) }?.key
        if let under {
            leftAt = nil
            guard hoveredDisplay != under else { return }
            hoveredDisplay = under
            guard !model.expanded, model.pop == nil,
                  UserDefaults.standard.bool(forKey: Self.openOnHoverKey) else { return }
            // Open once the pointer has rested on the notch for a moment, so passing through doesn't open it,
            // and never while a button is held (dragging a tab or window along the top).
            openTask?.cancel()
            openTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, let self, self.hoveredDisplay == under, NSEvent.pressedMouseButtons == 0 else { return }
                self.open(on: under)
            }
        } else {
            hoveredDisplay = nil
            openTask?.cancel()
            guard model.expanded, !holdOpenForTesting else { return }
            // Close only after the pointer has stayed away for a moment, so a small overshoot doesn't shut it.
            let now = Date()
            if let leftAt {
                if now.timeIntervalSince(leftAt) > 0.3 { close() }
            } else {
                leftAt = now
            }
        }
    }

    private func clicked() {
        guard !model.expanded else { return }
        let location = NSEvent.mouseLocation
        guard let under = panels.first(where: { activeRect($0.value.panel, $0.value.screen).contains(location) })?.key else { return }
        openTask?.cancel()
        open(on: under)
    }

    /// Opens the notch on `display` (default: the screen under the pointer, else the first notch).
    func open(on display: CGDirectDisplayID? = nil) {
        let target = display.flatMap { panels[$0] != nil ? $0 : nil }
            ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }?.displayID.flatMap { panels[$0] != nil ? $0 : nil }
            ?? screens.first?.screen.display
        guard let target else { return }
        // Nothing pops while open; events are marked inside the panel instead.
        popQueue.clear()
        model.expandedOn = target
        leftAt = nil
        pointerTimer?.invalidate()
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
    }

    func close() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        leftAt = nil
        model.expandedOn = nil
    }

    // MARK: Visibility

    /// Puts each panel on screen or off (fullscreen), and lets clicks through unless something is open there.
    private func updateWindows() {
        for entry in panels.values {
            let state = model.state(on: entry.screen.display)
            // A fullscreen app hides the virtual notch, unless the Pomodoro fuse is burning.
            let hidden = entry.screen.isVirtual && entry.screen.coveredByFullscreen && model.live?.id != "pomodoro"
            if hidden {
                if entry.panel.isVisible { entry.panel.orderOut(nil) }
            } else if !entry.panel.isVisible {
                entry.panel.orderFrontRegardless()
            }
            entry.panel.ignoresMouseEvents = !(state == .expanded || state == .pop)
        }
    }

    /// Checks each virtual notch's screen for a fullscreen window of another app.
    private func updateFullscreen() {
        let fullscreen = Self.fullscreenDisplays()
        for entry in panels.values {
            let covered = entry.screen.isVirtual && fullscreen.contains(entry.screen.display)
            if entry.screen.coveredByFullscreen != covered { entry.screen.coveredByFullscreen = covered }
        }
        updateWindows()
    }

    /// Screens showing a normal-level window of another app that fills the whole screen.
    private static func fullscreenDisplays() -> Set<CGDirectDisplayID> {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        var result = Set<CGDirectDisplayID>()
        for window in info {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowOwnerPID as String] as? pid_t) != me,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { continue }
            for screen in NSScreen.screens {
                guard let id = screen.displayID else { continue }
                if CGDisplayBounds(id).equalTo(bounds) { result.insert(id) }
            }
        }
        return result
    }
}
