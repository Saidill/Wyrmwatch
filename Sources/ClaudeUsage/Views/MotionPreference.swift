import AppKit
import SwiftUI

/// Whether to keep motion to a minimum: the system's Reduce Motion, or the app's own switch to force it.
/// With it on, springs become a short fade and nothing repeats.
@MainActor
final class MotionPreference: ObservableObject {
    static let shared = MotionPreference()
    static let forceKey = "motion.forceReduce"

    @Published private(set) var reduce = false

    private init() {
        update()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    private func update() {
        let next = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || UserDefaults.standard.bool(forKey: Self.forceKey)
        if next != reduce { reduce = next }
    }
}

extension Motion {
    /// `animation`, or the plain short fade when motion is reduced.
    static func adapt(_ animation: Animation, _ reduce: Bool) -> Animation {
        reduce ? reduced : animation
    }
}

private struct FollowsReduceMotion: ViewModifier {
    @ObservedObject private var motion = MotionPreference.shared

    func body(content: Content) -> some View {
        content
            .environment(\.reduceMotion, motion.reduce)
            .transformEnvironment(\.animationsPaused) { paused in paused = paused || motion.reduce }
    }
}

private struct ReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The app-wide Reduce Motion (system setting or the app's own switch).
    var reduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }
}

extension View {
    /// Stops every repeating animation below while motion is reduced.
    func followsReduceMotion() -> some View { modifier(FollowsReduceMotion()) }
}

private struct AnimationsPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Stops every repeating animation (status dot, working dots, visualizer, mascot) while out of sight,
    /// e.g. the notch content when the notch is closed.
    var animationsPaused: Bool {
        get { self[AnimationsPausedKey.self] }
        set { self[AnimationsPausedKey.self] = newValue }
    }
}
