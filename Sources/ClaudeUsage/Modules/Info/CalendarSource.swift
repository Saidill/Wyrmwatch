import EventKit
import Foundation

/// The next calendar event in the coming day. If calendar access is refused, it simply stays empty.
@MainActor
final class CalendarSource: ObservableObject {
    struct Upcoming: Equatable {
        let title: String
        let start: Date
        let end: Date
    }

    @Published private(set) var next: Upcoming?
    @Published private(set) var authorized = false

    private let store = EKEventStore()
    private var observer: Any?
    private let live: Bool

    init(live: Bool = true) {
        self.live = live
        guard live else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        requestAccess()
    }

    /// Asks once (the system remembers the answer), then loads the next event.
    func requestAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            authorized = true
            refresh()
        case .notDetermined:
            Task {
                let granted = (try? await store.requestFullAccessToEvents()) ?? false
                authorized = granted
                if granted { refresh() }
            }
        default:
            authorized = false
            next = nil
        }
    }

    /// Finds the next timed event that hasn't ended yet, within 24 hours.
    func refresh() {
        guard live, authorized else { return }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(24 * 3600), calendars: nil)
        let event = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
            .min { $0.startDate < $1.startDate }
        let upcoming = event.map { Upcoming(title: $0.title ?? "Event", start: $0.startDate, end: $0.endDate) }
        if upcoming != next { next = upcoming }
    }

    func injectForTesting(_ upcoming: Upcoming?) {
        authorized = upcoming != nil
        next = upcoming
    }
}
