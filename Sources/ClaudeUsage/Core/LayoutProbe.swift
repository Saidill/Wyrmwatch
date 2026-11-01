import SwiftUI

/// Self-test only: records where named views end up in the open panel, so the test can check that
/// nothing overlaps. Does nothing outside the self-test.
@MainActor
enum LayoutProbe {
    nonisolated static let space = "panel"
    static var frames: [String: CGRect] = [:]
    static var enabled: Bool { SelfTest.isRequested }

    /// Leaf views whose frames intersect another's (touching edges don't count).
    static func overlaps(prefix: String) -> [(String, String)] {
        let items = frames.filter { $0.key.hasPrefix(prefix) && $0.value.width > 0 && $0.value.height > 0 }
            .sorted { $0.key < $1.key }
        var result: [(String, String)] = []
        for i in items.indices {
            for j in items.indices where j > i {
                let overlap = items[i].value.intersection(items[j].value)
                if !overlap.isNull, overlap.width > 0.5, overlap.height > 0.5 { result.append((items[i].key, items[j].key)) }
            }
        }
        return result
    }
}

private struct LayoutProbingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set by the open notch panel: only views inside it are recorded (the same pages also live in the popover).
    var layoutProbing: Bool {
        get { self[LayoutProbingKey.self] }
        set { self[LayoutProbingKey.self] = newValue }
    }
}

private struct Probe: ViewModifier {
    let name: String
    @Environment(\.layoutProbing) private var probing

    func body(content: Content) -> some View {
        if LayoutProbe.enabled, probing, !name.isEmpty {
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .named(LayoutProbe.space)) } action: { frame in
                MainActor.assumeIsolated { LayoutProbe.frames[name] = frame }
            }
            .onDisappear { MainActor.assumeIsolated { LayoutProbe.frames[name] = nil } }
        } else {
            content
        }
    }
}

extension View {
    /// Names this view for the self-test's overlap check.
    func probe(_ name: String) -> some View { modifier(Probe(name: name)) }
}
