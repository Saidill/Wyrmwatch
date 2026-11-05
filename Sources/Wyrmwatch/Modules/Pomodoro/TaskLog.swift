import Foundation

/// What was worked on: minutes per task per day, kept on this Mac for 30 days, and the last few task names.
@MainActor
final class TaskLog: ObservableObject {
    static let shared = TaskLog()

    struct Entry: Codable, Equatable {
        let day: String
        let task: String
        var minutes: Double
    }

    @Published private(set) var entries: [Entry] = []
    /// The five most recent distinct names, newest first.
    @Published private(set) var recent: [String] = []

    private let defaults: UserDefaults
    private static let entriesKey = "focus.log"
    private static let recentKey = "focus.recentTasks"
    private static let keepDays = 30

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.entriesKey),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) { entries = saved }
        recent = defaults.stringArray(forKey: Self.recentKey) ?? []
        prune()
    }

    /// The label used for time without a task name.
    static let untitled = "No task"

    /// Adds `minutes` of work on `task` today.
    func add(minutes: Double, task: String) {
        guard minutes >= 0.5 else { return }
        let name = Self.clean(task) ?? Self.untitled
        let today = Self.dayKey(Date())
        if let i = entries.firstIndex(where: { $0.day == today && $0.task == name }) {
            entries[i].minutes += minutes
        } else {
            entries.append(Entry(day: today, task: name, minutes: minutes))
        }
        save()
    }

    /// Remembers `task` as recently used (shown as chips in the setup).
    func use(_ task: String) {
        guard let name = Self.clean(task) else { return }
        recent.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        recent.insert(name, at: 0)
        if recent.count > 5 { recent.removeLast(recent.count - 5) }
        defaults.set(recent, forKey: Self.recentKey)
    }

    /// Today's tasks with their minutes, longest first.
    var today: [(task: String, minutes: Int)] {
        let key = Self.dayKey(Date())
        return entries.filter { $0.day == key }.sorted { $0.minutes > $1.minutes }
            .map { ($0.task, Int($0.minutes.rounded())) }
    }

    private func prune() {
        let cutoff = Self.dayKey(Calendar.current.date(byAdding: .day, value: -Self.keepDays, to: Date()) ?? Date())
        let kept = entries.filter { $0.day >= cutoff }
        if kept.count != entries.count { entries = kept; save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.entriesKey) }
    }

    private static func clean(_ task: String) -> String? {
        let name = task.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : String(name.prefix(60))
    }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
