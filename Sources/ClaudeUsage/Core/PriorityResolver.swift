/// Picks which module owns the live notch: the active one with the smallest priority.
/// Ties go to the module registered first. With a custom `order` (set in Settings), a module earlier in the
/// order always wins over a later one, and its own priority only breaks ties.
@MainActor
enum PriorityResolver {
    static func resolve(_ modules: [any NotchModule], order: [String]? = nil) -> (any NotchModule)? {
        var best: (module: any NotchModule, rank: (Int, Int))?
        for module in modules {
            guard let p = module.livePriority else { continue }
            let position = order?.firstIndex(of: module.id) ?? (order == nil ? 0 : Int.max)
            let rank = (position, p)
            if best == nil || rank < best!.rank { best = (module, rank) }
        }
        return best?.module
    }
}
