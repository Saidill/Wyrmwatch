import AppKit
import RiveRuntime
import SwiftUI

/// What the mascot is doing. The names match the inputs of the mascot's Rive state machine.
enum WyrmState: String, CaseIterable {
    case hidden, peek, working, alert, done, sleep

    /// What the app is up to, as the mascot sees it: Claude busy → working, Claude waiting for you → alert,
    /// a session just finished → done, nothing for a long while → sleep, anything else → peek.
    @MainActor
    static func current(sessions: SessionMonitor, idleFor: TimeInterval) -> WyrmState {
        if sessions.celebrating { return .done }
        if sessions.waitingCount > 0 { return .alert }
        if sessions.busyCount > 0 { return .working }
        return idleFor > 5 * 60 ? .sleep : .peek
    }
}

/// Where the mascot appears: the gap in the header beside the camera, and the left of the live notch.
/// It plays `wyrm.riv` (from the app's Resources) with Rive when that file is there, and shows nothing
/// otherwise — the app never draws a mascot of its own.
struct WyrmSlot: View {
    var state: WyrmState
    /// Where the pointer is, roughly −1…1 on each axis, for the mascot to look at (nil: straight ahead).
    var look: CGPoint?
    var size: CGFloat = 26
    @Environment(\.animationsPaused) private var paused

    /// Whether a mascot file ships with the app.
    static let fileURL = Bundle.main.url(forResource: "wyrm", withExtension: "riv")
    static var available: Bool { fileURL != nil }

    var body: some View {
        if Self.available, state != .hidden {
            WyrmRive(state: state, look: look, running: !paused)
                .frame(width: size, height: size)
                .allowsHitTesting(false)
                .accessibilityLabel("Wyrm, \(state.rawValue)")
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

/// The Rive player. One input per state (a boolean with the state's name, only the current one true),
/// plus "lookX" / "lookY" numbers. Paused whenever the notch hides it.
private struct WyrmRive: View {
    let state: WyrmState
    let look: CGPoint?
    let running: Bool
    @StateObject private var model = WyrmModel()

    var body: some View {
        model.view
            .onAppear { model.apply(state: state, look: look, running: running) }
            .onChange(of: state) { _, _ in model.apply(state: state, look: look, running: running) }
            .onChange(of: look) { _, _ in model.apply(state: state, look: look, running: running) }
            .onChange(of: running) { _, _ in model.apply(state: state, look: look, running: running) }
    }
}

@MainActor
private final class WyrmModel: ObservableObject {
    private let rive: RiveViewModel?

    init() {
        rive = WyrmSlot.available ? RiveViewModel(fileName: "wyrm", extension: ".riv", in: .main, autoPlay: false) : nil
    }

    var view: AnyView { rive.map { AnyView($0.view()) } ?? AnyView(EmptyView()) }

    func apply(state: WyrmState, look: CGPoint?, running: Bool) {
        guard let rive else { return }
        for other in WyrmState.allCases { rive.setInput(other.rawValue, value: other == state) }
        rive.setInput("lookX", value: Double(look?.x ?? 0))
        rive.setInput("lookY", value: Double(look?.y ?? 0))
        running ? rive.play() : rive.pause()
    }
}
