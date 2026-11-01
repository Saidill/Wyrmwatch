import SwiftUI

/// One feature living in the notch (Claude, Pomodoro, Music, Info).
/// The registry shows the active module with the smallest `livePriority` in the live notch,
/// and queues the pops it sends.
@MainActor
protocol NotchModule: ObservableObject {
    var id: String { get }
    /// nil = not active; the smaller, the more it wins the live notch.
    var livePriority: Int? { get }
    /// Left of the camera: an icon or small visual.
    func liveLeading() -> AnyView
    /// Right of the camera: a number or indicator.
    func liveTrailing() -> AnyView
    /// Card shown in the expanded notch, if the module has one.
    func expandedCard() -> AnyView?
    /// One-off events that ask for a pop.
    var pops: AsyncStream<NotchPop> { get }
    /// Whether the module's views are on screen, so it can stop anything that repeats.
    func setVisible(_ visible: Bool)
}

/// A short card that drops out of the notch for a moment.
struct NotchPop: Identifiable {
    /// Who sent it. When several arrive together they are shown in this order.
    enum Kind: Int, Comparable {
        case pomodoro, claude, music, info
        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    let id = UUID()
    let kind: Kind
    /// How long it stays (longer while the pointer is on it).
    var duration: Double = 5
    let content: AnyView

    init(kind: Kind, duration: Double = 5, @ViewBuilder content: () -> some View) {
        self.kind = kind
        self.duration = duration
        self.content = AnyView(content())
    }
}
