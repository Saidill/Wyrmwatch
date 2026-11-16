import AppKit
import SwiftUI

/// What the mascot is doing.
enum WyrmState: String, CaseIterable {
    case hidden, peek, working, alert, done, sleep

    /// What the app is up to, as the mascot sees it: Claude busy → working, Claude waiting for you → alert,
    /// a session just finished → done, nothing for a long while → sleep, anything else → peek.
    @MainActor
    static func current(sessions: SessionMonitor, idleFor: TimeInterval) -> WyrmState {
        if let forTesting { return forTesting }
        if sessions.celebrating { return .done }
        if sessions.waitingCount > 0 { return .alert }
        if sessions.busyCount > 0 { return .working }
        return idleFor > 5 * 60 ? .sleep : .peek
    }
}

extension WyrmState {
    /// The self-test puts the mascot in each state in turn.
    @MainActor static var forTesting: WyrmState?
}

/// Where the mascot appears: the header of the open notch, the left of the live notch and the menu bar popover.
/// It plays the dragon's sprite sheets (`DragonSpriteView`); `size` is its height, the width follows the sprite.
struct WyrmSlot: View {
    var state: WyrmState
    var size: CGFloat = 24
    /// The sprite faces right; this turns it round.
    var facingLeft = false
    @Environment(\.animationsPaused) private var paused
    @Environment(\.reduceMotion) private var reduceMotion

    /// Width over height of the dragon.
    static var aspect: CGFloat { DragonAtlas.shared?.aspect ?? 1 }
    /// The empty strip under the dragon's feet, as a share of its height (to stand it on a line).
    static let groundGap: CGFloat = 0.08

    var body: some View {
        if state == .hidden || DragonAtlas.shared == nil {
            Color.clear.frame(width: 0, height: 0)
        } else {
            DragonSpriteView(state: state, running: !paused && !reduceMotion, facingLeft: facingLeft)
                .frame(width: (size * Self.aspect).rounded(), height: size)
                .allowsHitTesting(false)
                .accessibilityLabel("Dragon, \(state.rawValue)")
        }
    }
}
