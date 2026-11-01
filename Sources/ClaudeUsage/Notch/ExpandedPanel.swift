import SwiftUI

/// Pages of the open notch, picked in the header's tab bar.
enum NotchTab: String, CaseIterable, Identifiable {
    case focus, music, claude, settings
    var id: String { rawValue }
    static let storageKey = "notchTab"

    var symbol: String {
        switch self {
        case .focus: return "flame.fill"
        case .music: return "music.note"
        case .claude: return "sparkle"
        case .settings: return "gearshape.fill"
        }
    }

    var title: String {
        switch self {
        case .focus: return "Fokus"
        case .music: return "Music"
        case .claude: return "Claude"
        case .settings: return "Settings"
        }
    }
}

/// The open notch: a header in the band beside the camera (wyrm, date, time, next event | tab bar),
/// and below it one page. Every page has the same size, so switching pages never moves the shape.
struct ExpandedPanel: View {
    /// Height of the page area under the header band.
    static let pageHeight: CGFloat = 150
    static let width: CGFloat = 600

    let notch: CGSize
    @AppStorage(NotchTab.storageKey) private var tab: NotchTab = .focus
    @EnvironmentObject var sessions: SessionMonitor

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: notch.height)
            page
                .frame(height: Self.pageHeight)
                .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .frame(width: Self.width, alignment: .top)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                WyrmView(mood: wyrmMood, size: 24)
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Text(context.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                .foregroundStyle(Palette.text2)
                            Text(context.date.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(Palette.text)
                                .monospacedDigit()
                        }
                        .font(.app(11.5, .medium))
                        EventLine(now: context.date)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The camera sits here.
            Spacer(minLength: notch.width + 12)
            TabBar(selection: $tab)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var wyrmMood: WyrmMood {
        let pomodoro = AppModels.pomodoro.timer
        if pomodoro.isRunning, pomodoro.phase == .focus { return .guarding }
        if sessions.celebrating { return .happy }
        if sessions.busyCount > 0 { return .working }
        return sessions.sessions.isEmpty ? .sleeping : .idle
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        ZStack(alignment: .topLeading) {
            switch tab {
            case .focus: FocusPage(timer: AppModels.pomodoro.timer)
            case .music: MusicPage(bridge: AppModels.music.bridge)
            case .claude: PopoverView(inNotch: true)
            case .settings:
                ScrollView(.vertical, showsIndicators: false) { SettingsView() }
            }
        }
        .id(tab)
        .transition(.opacity)
        .animation(Motion.smooth, value: tab)
    }
}

/// The next calendar event, small, under the date (only when Info is on and there is one).
private struct EventLine: View {
    let now: Date
    @ObservedObject private var registry = AppModels.registry

    var body: some View {
        if registry.isEnabled("info") {
            NextEventLabel(calendar: AppModels.info.calendar, now: now)
                .font(.app(9.5))
        }
    }
}

/// Icon tabs on the right of the header.
private struct TabBar: View {
    @Binding var selection: NotchTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.allCases) { tab in
                Image(systemName: tab.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selection == tab ? Palette.blue : Palette.text3)
                    .frame(width: 30, height: 22)
                    .background(Capsule().fill(selection == tab ? Palette.blue.opacity(0.18) : .clear))
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(Motion.smooth) { selection = tab } }
                    .help(tab.title)
            }
        }
        .padding(2)
        .background(Capsule().fill(Palette.glass))
    }
}
