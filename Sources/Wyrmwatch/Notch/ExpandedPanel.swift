import SwiftUI

/// Pages of the open notch, picked in the header's tabs. (Settings opens from a right-click on the notch or
/// the menu bar icon instead.)
enum NotchTab: String, CaseIterable, Identifiable {
    case home, focus, music, claude
    var id: String { rawValue }
    static let storageKey = "notchTab"

    var title: String {
        switch self {
        case .home: return "Home"
        case .focus: return "Focus"
        case .music: return "Music"
        case .claude: return "Claude"
        }
    }

    @ViewBuilder func icon(lineWidth: CGFloat = 1.5) -> some View {
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        switch self {
        case .home: HomeIcon().stroke(style: style)
        case .focus: FocusIcon().stroke(style: style)
        case .music: MusicIcon().stroke(style: style)
        case .claude: ClaudeIcon().stroke(style: style)
        }
    }
}

/// The open notch. The header is a three-column grid split by the camera: the tabs on the left, the physical
/// notch's width in the middle (where the mascot sits), the active tab's name and the clock on the right.
/// Below it, one page of cards; the notch grows or shrinks to fit it.
struct ExpandedPanel: View {
    static let width: CGFloat = 620
    /// Never taller than this (long lists scroll inside their page).
    static let maxPageHeight: CGFloat = 300

    let notch: CGSize
    var coverSpace: Namespace.ID?
    /// Reports the page's height so the shape can follow it.
    let onPageHeight: (CGFloat) -> Void
    @AppStorage(NotchTab.storageKey) private var tab: NotchTab = .home
    @EnvironmentObject var sessions: SessionMonitor
    @EnvironmentObject var limits: PlanLimitClient

    var body: some View {
        VStack(spacing: 8) {
            header

            ZStack(alignment: .topLeading) {
                page
                    .id(tab)
                    .transition(.opacity.animation(Motion.page))
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onPageHeight(min($0, Self.maxPageHeight)) }
        }
        .padding(.horizontal, 16)
        .frame(width: Self.width, alignment: .top)
        .coordinateSpace(name: LayoutProbe.space)
        .environment(\.layoutProbing, true)
    }

    /// The dragon and the tabs on the left, the camera in the middle (left empty: a real camera hides whatever
    /// is there), the clock on the right. A ground line runs under all of it; the dragon stands on it.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                WyrmSlot(state: wyrmState, size: notch.height - 2)
                    .offset(y: 1 + (notch.height - 2) * WyrmSlot.groundGap)
                    .probe("header.dragon")
                TabBar(selection: $tab).probe("header.tabs")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notch.width, height: notch.height)
            TimelineView(.everyMinute) { context in
                // Two digits each: in some regions "minute" alone drops the leading zero ("01.8").
                Text(context.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                    .font(.app(11))
                    .foregroundStyle(Palette.text2)
                    .monospacedDigit()
                    .fixedSize()
            }
            .probe("header.right")
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: notch.height)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1).offset(y: 1) }
    }

    private var wyrmState: WyrmState {
        WyrmState.current(sessions: sessions, idleFor: Self.userIdleTime)
    }

    /// Seconds since the last keyboard or mouse input.
    static var userIdleTime: TimeInterval {
        [CGEventType.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    @ViewBuilder
    private var page: some View {
        switch tab {
        case .home:
            HomePage(bridge: AppModels.music.bridge, timer: AppModels.pomodoro.timer, limits: limits, sessions: sessions,
                     coverSpace: coverSpace)
        case .focus:
            FocusPage(timer: AppModels.pomodoro.timer)
        case .music:
            MusicPage(bridge: AppModels.music.bridge, coverSpace: coverSpace)
        case .claude:
            PopoverView(inNotch: true)
        }
    }
}

/// Four icon tabs (16 pt icons in 28 × 28), no boxes: the active one is bone-white with a short bar on the
/// header's ground line under it.
private struct TabBar: View {
    @Binding var selection: NotchTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NotchTab.allCases) { tab in
                Button { withAnimation(Motion.quick) { selection = tab } } label: {
                    tab.icon()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(selection == tab ? Palette.text : Palette.text2)
                        .frame(width: 28, height: 28)
                        .overlay(alignment: .bottom) {
                            if selection == tab { Rectangle().fill(Palette.text).frame(width: 16, height: 2).offset(y: 4) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .help(tab.title)
                .accessibilityLabel(tab.title)
            }
        }
    }
}
