import Combine
import SwiftUI

/// The next calendar event, shown in the expanded header. Never takes the live notch and never pops.
@MainActor
final class InfoModule: NotchModule {
    let id = "info"
    let calendar: CalendarSource
    let pops: AsyncStream<NotchPop>

    init(calendar: CalendarSource) {
        self.calendar = calendar
        pops = AsyncStream { $0.finish() }
    }

    var livePriority: Int? { nil }
    func liveLeading() -> AnyView { AnyView(EmptyView()) }
    func liveTrailing() -> AnyView { AnyView(EmptyView()) }
    /// Lives in the header, not as a card.
    func expandedCard() -> AnyView? { nil }

    func setVisible(_ visible: Bool) {
        // Catch up on anything that changed while the notch was shut.
        if visible { calendar.refresh() }
    }
}

/// Next event as "Design review · in 25m", or nothing when there's none (or no calendar access).
struct NextEventLabel: View {
    @ObservedObject var calendar: CalendarSource
    let now: Date

    var body: some View {
        if let event = calendar.next {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.silver)
                Text(event.title)
                    .foregroundStyle(Palette.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(Self.when(event, now: now))
                    .foregroundStyle(Palette.text3)
                    .monospacedDigit()
                    .fixedSize()
            }
            .help(event.title)
        }
    }

    /// "now", "in 25m", or the start time.
    static func when(_ event: CalendarSource.Upcoming, now: Date) -> String {
        if event.start <= now { return "now" }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        if minutes < 60 { return "in \(max(minutes, 1))m" }
        return event.start.formatted(date: .omitted, time: .shortened)
    }
}

/// One quiet line under the menu bar popover's header: date and time, next event.
struct InfoStrip: View {
    @ObservedObject var calendar: CalendarSource

    var body: some View {
        // Redraws once a minute, on the minute.
        TimelineView(.everyMinute) { context in
            HStack(spacing: 8) {
                Text(context.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .foregroundStyle(Palette.text2)
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
                Spacer(minLength: 4)
                NextEventLabel(calendar: calendar, now: context.date)
            }
            .font(.app(11))
            .padding(.horizontal, 4)
            .frame(height: 16)
        }
    }
}
