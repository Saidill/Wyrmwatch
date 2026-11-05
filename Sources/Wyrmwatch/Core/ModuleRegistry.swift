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
    /// Self-test only: treat every module as inactive, so the closed notch can be checked while Claude is busy.
    var mutedForTesting: Bool {
        get { onlyForTesting?.isEmpty == true }
        set { onlyForTesting = newValue ? [] : nil }
    }
    /// Self-test only: let just these modules win the live notch (nil = all).
    var onlyForTesting: Set<String>? {
        didSet { resolve() }
    }

    private static let disabledKey = "modules.disabled"
    private static let orderKey = "modules.order"

    /// Modules switched off in Settings: no live notch, no pops, no card.
    @Published private(set) var disabled = Set(UserDefaults.standard.stringArray(forKey: disabledKey) ?? [])
    /// The order chosen in Settings, or nil for the built-in priorities.
    @Published private(set) var customOrder = UserDefaults.standard.stringArray(forKey: orderKey)

    /// Modules that can take the live notch, in the order Settings shows them.
    var orderedIDs: [String] {
        let ids = modules.filter { $0.id != "info" }.map(\.id)
        guard let customOrder else { return ids }
        return customOrder.filter(ids.contains) + ids.filter { !customOrder.contains($0) }
    }

    var enabledModules: [any NotchModule] { modules.filter { !disabled.contains($0.id) } }

    func isEnabled(_ id: String) -> Bool { !disabled.contains(id) }

    func setEnabled(_ id: String, _ enabled: Bool) {
        if enabled { disabled.remove(id) } else { disabled.insert(id) }
        UserDefaults.standard.set(Array(disabled).sorted(), forKey: Self.disabledKey)
        resolve()
    }

    func setOrder(_ order: [String]?) {
        customOrder = order
        UserDefaults.standard.set(order, forKey: Self.orderKey)
        resolve()
    }

    static func title(for id: String) -> String {
        switch id {
        case "pomodoro": return "Pomodoro"
        case "claude": return "Claude"
        case "music": return "Music"
        case "info": return "Info"
        default: return id.capitalized
        }
    }

    func register(_ module: some NotchModule) {
        modules.append(module)
        // objectWillChange fires before the value changes, so resolve on the next turn of the run loop.
        module.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.resolve() } }
        }.store(in: &subscriptions)
        listeners.append(Task { [weak self] in
            for await pop in module.pops where self?.isEnabled(module.id) == true { self?.popQueue.enqueue(pop) }
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

    /// What the live notch shows: the winner, or the Pomodoro and the music taking turns when both are on.
    func liveRotation(fallback: any NotchModule) -> [any NotchModule] {
        let candidates = enabledModules.filter { (onlyForTesting?.contains($0.id) ?? true) && $0.livePriority != nil }
        let ids = Set(candidates.map(\.id))
        guard ids.contains("pomodoro"), ids.contains("music") else { return [fallback] }
        return candidates.filter { $0.id == "pomodoro" || $0.id == "music" }
            .sorted { ($0.id == "pomodoro" ? 0 : 1) < ($1.id == "pomodoro" ? 0 : 1) }
    }

    func resolve() {
        let candidates = enabledModules.filter { onlyForTesting?.contains($0.id) ?? true }
        let next = PriorityResolver.resolve(candidates, order: customOrder)
        if next?.id != active?.id { active = next }
    }
}
