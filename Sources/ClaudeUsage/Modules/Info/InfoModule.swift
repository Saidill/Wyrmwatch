import Combine
import SwiftUI

/// The basics: date and time, battery, the next calendar event (in the expanded header),
/// and a short pop when the charger is plugged in. Never takes the live notch.
@MainActor
final class InfoModule: NotchModule {
    let id = "info"
    let battery: BatteryMonitor
    let calendar: CalendarSource
    let pops: AsyncStream<NotchPop>
    private let popSink: AsyncStream<NotchPop>.Continuation
    private var subscriptions: Set<AnyCancellable> = []

    enum Keys {
        static let chargerPop = "info.chargerPop"
    }

    init(battery: BatteryMonitor, calendar: CalendarSource) {
        self.battery = battery
        self.calendar = calendar
        (pops, popSink) = AsyncStream.makeStream(of: NotchPop.self)
        UserDefaults.standard.register(defaults: [Keys.chargerPop: true])
        battery.pluggedIn.sink { [weak self] reading in
            guard let self, UserDefaults.standard.bool(forKey: Keys.chargerPop) else { return }
            self.popSink.yield(NotchPop(kind: .info, duration: 2) { ChargerPop(reading: reading) })
        }.store(in: &subscriptions)
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

/// Battery symbol filled to the level, bolt while charging.
struct BatteryGlyph: View {
    let reading: BatteryMonitor.Reading
    var height: CGFloat = 9

    var body: some View {
        let width = height * 2.1
        let color: Color = reading.charging || reading.onPower ? Palette.silver
            : reading.percent <= 10 ? Palette.rose : reading.percent <= 20 ? Palette.amber : Palette.text2
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.28, style: .continuous)
                    .strokeBorder(Palette.text3, lineWidth: 1)
                RoundedRectangle(cornerRadius: height * 0.16, style: .continuous)
                    .fill(color)
                    .frame(width: max(1.5, (width - 3) * CGFloat(reading.percent) / 100))
                    .padding(1.5)
                if reading.charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: height * 0.75, weight: .bold))
                        .foregroundStyle(Palette.onSilver)
                        .frame(width: width)
                }
            }
            .frame(width: width, height: height)
            RoundedRectangle(cornerRadius: 1).fill(Palette.text3).frame(width: 1.5, height: height * 0.4)
        }
        .animation(Motion.smooth, value: reading)
    }
}

/// One quiet line under the header: date and time, battery, next event.
struct InfoStrip: View {
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var calendar: CalendarSource

    var body: some View {
        // Redraws once a minute, on the minute.
        TimelineView(.everyMinute) { context in
            HStack(spacing: 10) {
                Text(context.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .foregroundStyle(Palette.text2)
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
                if let reading = battery.reading {
                    HStack(spacing: 4) {
                        BatteryGlyph(reading: reading)
                        Text("\(reading.percent)%").monospacedDigit()
                    }
                    .foregroundStyle(Palette.text2)
                }
                Spacer(minLength: 4)
                if let event = calendar.next {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Palette.amber)
                        Text(event.title)
                            .foregroundStyle(Palette.text2)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(Self.when(event, now: context.date))
                            .foregroundStyle(Palette.text3)
                            .monospacedDigit()
                            .fixedSize()
                    }
                    .help(event.title)
                }
            }
            .font(.app(11))
            .padding(.horizontal, 4)
            .frame(height: 16)
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

/// The charger went in: a filling battery and the level, for a moment.
private struct ChargerPop: View {
    let reading: BatteryMonitor.Reading
    @State private var filled = false

    var body: some View {
        HStack(spacing: 12) {
            BatteryGlyph(reading: BatteryMonitor.Reading(percent: filled ? reading.percent : 0,
                                                          charging: true, onPower: true), height: 16)
            Text("Charging")
                .font(.app(13, .medium))
                .foregroundStyle(Palette.text)
            Spacer()
            Text("\(reading.percent)%")
                .font(.app(15, .medium))
                .foregroundStyle(Palette.silver)
                .monospacedDigit()
        }
        .padding(.top, 2)
        .onAppear { withAnimation(Motion.contentIn) { filled = true } }
    }
}
