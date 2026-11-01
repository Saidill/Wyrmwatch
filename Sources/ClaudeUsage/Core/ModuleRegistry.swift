import Combine
import Foundation

/// All notch modules, which of them owns the live notch right now, and the queue their pops go into.
@MainActor
final class ModuleRegistry: ObservableObject {
    private(set) var modules: [any NotchModule] = []
    /// The module shown in the live notch, or nil when nothing is active (closed).
    @Published private(set) var active: (any NotchModule)?
    let popQueue = PopQueue()
    private var subscriptions: Set<AnyCancellable> = []
    private var listeners: [Task<Void, Never>] = []
    private var visible = false

    func register(_ module: some NotchModule) {
        modules.append(module)
        // objectWillChange fires before the value changes, so resolve on the next turn of the run loop.
        module.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.resolve() } }
        }.store(in: &subscriptions)
        listeners.append(Task { [weak self] in
            for await pop in module.pops { self?.popQueue.enqueue(pop) }
        })
        resolve()
    }

    func module(id: String) -> (any NotchModule)? { modules.first { $0.id == id } }

    /// Tells every module whether the notch content is on screen.
    func setVisible(_ visible: Bool) {
        guard visible != self.visible else { return }
        self.visible = visible
        modules.forEach { $0.setVisible(visible) }
    }

    func resolve() {
        let next = PriorityResolver.resolve(modules)
        if next?.id != active?.id { active = next }
    }
}
