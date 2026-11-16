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

    /// Tabs on the left, the camera in the middle, the clock on the right. Where the dragon goes depends on the
    /// design: in the camera gap today (hidden by a real camera); in the directions under review it moves out:
    /// Obsidian puts it before the tabs, Hearth walks it along a ground line under the header, Vault perches it
    /// on the top edge of the last card.
    private var header: some View {
        let design = Design.active
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                switch design {
                case .obsidian:
                    WyrmSlot(state: wyrmState, size: min(notch.height - 4, 26)).probe("header.dragon")
                case .hearth:
                    // Standing on the ground line.
                    WyrmSlot(state: wyrmState, size: notch.height - 2)
                        .offset(y: 1 + (notch.height - 2) * WyrmSlot.groundGap)
                        .probe("header.dragon")
                default:
                    EmptyView()
                }
                TabBar(selection: $tab).probe("header.tabs")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The camera.
            Group {
                if design == .current { WyrmSlot(state: wyrmState, size: min(notch.height - 4, 28)) }
            }
            .frame(width: notch.width, height: notch.height)
            HStack(spacing: 8) {
                TimelineView(.everyMinute) { context in
                    // Two digits each: in some regions "minute" alone drops the leading zero ("01.8").
                    Text(context.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                        .font(.app(11))
                        .foregroundStyle(Palette.text2)
                        .monospacedDigit()
                        .fixedSize()
                }
                .probe("header.right")
                if design == .vault {
                    // Perched on the top edge of the card below (8 pt under the header), facing in.
                    let size = notch.height + 8
                    WyrmSlot(state: wyrmState, size: size, facingLeft: true)
                        .frame(height: notch.height, alignment: .bottom)
                        .offset(y: 8 + size * WyrmSlot.groundGap)
                        .probe("header.dragon")
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: notch.height)
        .overlay(alignment: .bottom) {
            if design == .hearth { Rectangle().fill(Palette.hairline).frame(height: 1).offset(y: 1) }
        }
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

/// Four 28 × 28 icon tabs (16 pt icons, radius 8): #1C1C1E with grey icons, the active one #3A3A3C and white.
/// Hearth draws no boxes: just the icons, with a short bar on the ground line under the active one.
private struct TabBar: View {
    @Binding var selection: NotchTab

    var body: some View {
        let design = Design.active
        HStack(spacing: design == .hearth ? 4 : 8) {
            ForEach(NotchTab.allCases) { tab in
                Button { withAnimation(Motion.quick) { selection = tab } } label: {
                    tab.icon()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(selection == tab ? Palette.text : Palette.text2)
                        .frame(width: 28, height: 28)
                        .background {
                            switch design {
                            case .current, .obsidian:
                                Radius.shape(Radius.tab).fill(selection == tab ? Palette.buttonHi : Palette.card)
                            case .vault:
                                ControlPlate(radius: Radius.tab, on: selection == tab)
                            case .hearth:
                                EmptyView()
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if design == .hearth, selection == tab {
                                Rectangle().fill(Palette.text).frame(width: 16, height: 2).offset(y: 4)
                            }
                        }
                        .contentShape(Radius.shape(Radius.tab))
                }
                .buttonStyle(.pressable)
                .help(tab.title)
                .accessibilityLabel(tab.title)
            }
        }
    }
}
