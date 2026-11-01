/// Picks which module owns the live notch: the active one with the smallest priority.
/// Ties go to the module registered first.
@MainActor
enum PriorityResolver {
    static func resolve(_ modules: [any NotchModule]) -> (any NotchModule)? {
        var best: (module: any NotchModule, priority: Int)?
        for module in modules {
            guard let p = module.livePriority else { continue }
            if best == nil || p < best!.priority { best = (module, p) }
        }
        return best?.module
    }
}
