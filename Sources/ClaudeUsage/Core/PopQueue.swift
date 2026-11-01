import Combine
import Foundation

/// Shows pops one at a time. Pops that arrive while one is showing wait their turn, ordered by kind
/// (Pomodoro, then Claude, then music). Nothing pops while the notch is expanded.
@MainActor
final class PopQueue: ObservableObject {
    @Published private(set) var current: NotchPop?
    private(set) var pending: [NotchPop] = []
    private var hideTask: Task<Void, Never>?

    /// Whether the pointer is on the notch; a pop stays while it is.
    var isHovering: () -> Bool = { false }
    /// Whether pops may show right now (not while expanded, not while the notch is hidden).
    var canShow: () -> Bool = { true }

    func enqueue(_ pop: NotchPop) {
        guard canShow() else { return }
        // Stable insert: after everything of the same or a more important kind.
        let index = pending.firstIndex { pop.kind < $0.kind } ?? pending.endIndex
        pending.insert(pop, at: index)
        if current == nil { advance() }
    }

    /// Hides the current pop now (a button on it was used) and moves on to the next one.
    func dismiss() {
        hideTask?.cancel()
        current = nil
        advance()
    }

    /// Drops the current pop and everything waiting (the notch opened or went away).
    func clear() {
        hideTask?.cancel()
        pending.removeAll()
        current = nil
    }

    private func advance() {
        guard !pending.isEmpty, canShow() else {
            pending.removeAll()
            return
        }
        let next = pending.removeFirst()
        current = next
        scheduleHide(after: next.duration)
    }

    private func scheduleHide(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            // Stay open while the pointer is on it.
            if self.isHovering() { self.scheduleHide(after: 1) } else { self.dismiss() }
        }
    }
}
