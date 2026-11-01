import SwiftUI

/// Pages of the open notch, picked in the header's tab bar.
enum NotchTab: String, CaseIterable, Identifiable {
    case home, focus, music, claude
    var id: String { rawValue }
    static let storageKey = "notchTab"

    var title: String {
        switch self {
        case .home: return "Home"
        case .focus: return "Fokus"
        case .music: return "Musik"
        case .claude: return "Claude"
        }
    }

    @ViewBuilder var icon: some View {
        let style = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
        switch self {
        case .home: HomeIcon().stroke(style: style)
        case .focus: FocusIcon().stroke(style: style)
        case .music: MusicIcon().stroke(style: style)
        case .claude: ClaudeIcon().stroke(style: style)
        }
    }
}

/// The open notch. The header is split by the camera into three columns (left | the physical notch | right):
/// the dragon and date on the left, the tabs on the right. Below it, one page; the notch grows or shrinks to fit it.
struct ExpandedPanel: View {
    static let width: CGFloat = 600
    /// Never taller than this (long lists scroll inside their page).
    static let maxPageHeight: CGFloat = 260

    let notch: CGSize
    var coverSpace: Namespace.ID?
    /// Reports the page's height so the shape can follow it.
    let onPageHeight: (CGFloat) -> Void
    @AppStorage(NotchTab.storageKey) private var tab: NotchTab = .home
    @EnvironmentObject var sessions: SessionMonitor
    @EnvironmentObject var limits: PlanLimitClient

    var body: some View {
        let _ = Perf.count("panel redraw")
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                left
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .probe("header.left")
                // The camera.
                Color.clear.frame(width: notch.width)
                TabBar(selection: $tab)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .probe("header.tabs")
            }
            .frame(height: notch.height)

            ZStack(alignment: .topLeading) {
                page
                    .id(tab)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 5)).animation(Motion.page),
                                            removal: .opacity.animation(Motion.page)))
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            // Measured at its own height, before the cap below stretches it.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onPageHeight(min($0, Self.maxPageHeight)) }
            .frame(height: nil, alignment: .top)
        }
        .padding(.horizontal, 18)
        .frame(width: Self.width, alignment: .top)
        .coordinateSpace(name: LayoutProbe.space)
        .environment(\.layoutProbing, true)
    }

    private var left: some View {
        HStack(spacing: 8) {
            DragonView(mood: dragonMood, size: 22)
            TimelineView(.everyMinute) { context in
                Text(Self.stamp(context.date))
                    .font(.app(12, .medium))
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(AppModels.info.calendar.next.map { "Next: \($0.title)" } ?? "")
            }
        }
    }

    /// "Min 1 Nov · 18.52".
    static func stamp(_ date: Date) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "id_ID")
        day.dateFormat = "EEE d MMM"
        let time = DateFormatter()
        time.locale = Locale(identifier: "id_ID")
        time.dateFormat = "HH.mm"
        return "\(day.string(from: date)) · \(time.string(from: date))"
    }

    private var dragonMood: DragonMood {
        let pomodoro = AppModels.pomodoro.timer
        if sessions.celebrating { return .happy }
        if pomodoro.isRunning, pomodoro.phase == .focus { return .guarding }
        if sessions.busyCount > 0 { return .working }
        return sessions.sessions.isEmpty ? .sleeping : .idle
    }

    @ViewBuilder
    private var page: some View {
        switch tab {
        case .home:
            HomePage(bridge: AppModels.music.bridge, timer: AppModels.pomodoro.timer, limits: limits, coverSpace: coverSpace)
        case .focus:
            FocusPage(timer: AppModels.pomodoro.timer)
        case .music:
            MusicPage(bridge: AppModels.music.bridge)
        case .claude:
            PopoverView(inNotch: true)
        }
    }
}

/// Four icon tabs (17 pt icons on 38 × 26 buttons); the active capsule glides between them.
private struct TabBar: View {
    @Binding var selection: NotchTab
    @Namespace private var glide

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.allCases) { tab in
                tab.icon
                    .frame(width: 17, height: 17)
                    .foregroundStyle(selection == tab ? Palette.text : Palette.text2)
                    .frame(width: 38, height: 26)
                    .background {
                        if selection == tab {
                            Capsule().fill(Palette.track).matchedGeometryEffect(id: "tab", in: glide)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(Motion.resize) { selection = tab } }
                    .help(tab.title)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(.isButton)
            }
        }
    }
}
