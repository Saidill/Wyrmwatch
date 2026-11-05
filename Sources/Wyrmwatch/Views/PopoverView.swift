import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var sessions: SessionMonitor
    @EnvironmentObject var usage: UsageTracker
    @EnvironmentObject var limits: PlanLimitClient
    @EnvironmentObject var recent: RecentSessionStore
    @EnvironmentObject var display: DisplayModeController
    /// Shown as the Claude page of the open notch: limits on the left, sessions / recent / usage on the right,
    /// at the panel's fixed size.
    var inNotch = false
    @State private var showSettings = false
    @AppStorage("popoverTab") private var tab = 0 // 0 = now, 1 = recent, 2 = usage
    @State private var range = 0 // 0 = today, 1 = week
    @State private var hoveredBar: Int?
    @State private var refreshTurns = 0.0
    /// Measured height of the current tab's content; the popover shrinks to fit it.
    @State private var contentHeight: CGFloat = 300
    private let maxContentHeight: CGFloat = 470
    /// The menu bar window. It doesn't follow SwiftUI size changes by itself, so `fitWindow` resizes it.
    @State private var window: NSWindow?

    var body: some View {
        let _ = Perf.count("claude page redraw")
        Group {
            if inNotch {
                claudePage
            } else {
                menuBarWindow
            }
        }
        .onAppear {
            usage.refresh()
            Task { await limits.refreshIfStale() }
            if tab == 1 { loadRecent() }
        }
        .onChange(of: tab) { _, t in if t == 1 { loadRecent() } }
        .preferredColorScheme(.dark)
    }

    /// The popover as it appears from the menu bar: a rounded sheet of frosted glass that shrinks to fit.
    private var menuBarWindow: some View {
        let sheet = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return content
            .background(GeometryReader { geo in
                Color.clear.preference(key: PopoverHeightKey.self, value: geo.size.height)
            })
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Palette.bg)
            .background(GlassBackground())
            .overlay { ConfettiView(trigger: sessions.finishCount) }
            .clipShape(sheet)
            .overlay(sheet.strokeBorder(Palette.rim, lineWidth: 1))
            .background(WindowReader { w in
                guard window !== w else { return }
                // Let the glass show through the window itself.
                w.isOpaque = false
                w.backgroundColor = .clear
                window = w
            })
            .onPreferenceChange(PopoverHeightKey.self) { fitWindow(height: $0) }
            .onChange(of: window) { _, _ in fitWindow(height: popoverHeight) }
    }

    /// The Claude page in the open notch: session and week side by side with the forecast, then
    /// Now / Recent / Usage, each scrolling in its own height.
    private var claudePage: some View {
        let session = limits.windows.first { $0.id == "five_hour" }
        let week = limits.windows.first { $0.id == "seven_day" }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                BigNumberCard(label: "Session", number: session.map { "\(Int($0.utilization.rounded()))%" } ?? "–",
                              detail: session?.resetsAt.map(formatReset) ?? limits.error ?? "",
                              warn: (session?.utilization ?? 0) >= 90, fraction: (session?.utilization ?? 0) / 100)
                    .probe("claude.session")
                    .cardAppear(0)
                BigNumberCard(label: "Week", number: week.map { "\(Int($0.utilization.rounded()))%" } ?? "–",
                              detail: week?.resetsAt.map(formatReset) ?? "",
                              warn: (week?.utilization ?? 0) >= 90, fraction: (week?.utilization ?? 0) / 100)
                    .probe("claude.week")
                    .cardAppear(1)
                BigNumberCard(label: "Sessions running", number: "\(sessions.sessions.count)",
                              detail: sessions.waitingCount > 0 ? "\(sessions.waitingCount) waiting for you"
                                  : sessions.busyCount > 0 ? "\(sessions.busyCount) working" : "Nothing working",
                              working: sessions.busyCount > 0, waiting: sessions.waitingCount > 0, active: sessions.busyCount > 0)
                    .probe("claude.running")
                    .cardAppear(2)
            }
            .frame(height: 96)
            PillToggle(options: ["Now", "Recent", "Usage"], selection: $tab, fill: true)
                .probe("claude.tabs")
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch tab {
                    case 1: recentCard
                    case 2: tokensCard
                    default: sessionsCard
                    }
                }
                .id(tab)
                .transition(.opacity.combined(with: .offset(y: 5)))
            }
            .frame(height: 128)
            .probe("claude.list")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var content: some View {
        // Header and tabs pinned on top; the body is exactly as tall as its content (scrolling past a max),
        // so there is no empty space and nothing floats in the middle.
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                header
                if !showSettings {
                    InfoHeaderLine(registry: AppModels.registry)
                    ModuleCardsRow(registry: AppModels.registry)
                    PillToggle(options: ["Now", "Recent", "Usage"], selection: $tab, fill: true)
                }
            }
            .padding([.horizontal, .top], 14)

            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .top) {
                    if showSettings {
                        SettingsView()
                            .transition(pageTransition)
                    } else {
                        VStack(spacing: 12) {
                            switch tab {
                            case 1: recentCard
                            case 2: tokensCard
                            default:
                                limitsCard
                                sessionsCard
                            }
                        }
                        .id(tab)
                        .transition(pageTransition)
                    }
                }
                .padding([.horizontal, .bottom], 14)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .top)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                })
            }
            .frame(height: min(contentHeight, maxContentHeight))
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        }
        .frame(width: 344)
        .fixedSize(horizontal: false, vertical: true)
    }

    @State private var popoverHeight: CGFloat = 0

    /// How one page of the popover gives way to the next. The old page leaves at once, so the window
    /// resizes a single time, and the new one fades up into place.
    private var pageTransition: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .identity)
    }

    /// Resizes the window to the content, keeping its top edge under the menu bar.
    private func fitWindow(height: CGFloat) {
        popoverHeight = height
        guard let window, height > 0 else { return }
        var frame = window.frame
        let newHeight = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: frame.width, height: height)).height
        guard abs(newHeight - frame.height) > 0.5 else { return }
        frame.origin.y = frame.maxY - newHeight
        frame.size.height = newHeight
        window.setFrame(frame, display: true, animate: false)
    }

    private func loadRecent() {
        recent.load(excluding: Set(sessions.sessions.compactMap(\.sessionId)))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Radius.shape(Radius.button).fill(Palette.card)
                WyrmSlot(state: WyrmState.current(sessions: sessions, idleFor: ExpandedPanel.userIdleTime), look: nil, size: 28)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text(showSettings ? "Settings" : "Claude")
                    .font(.app(16, .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .contentTransition(.opacity)
                Text(statusLine)
                    .font(.app(11))
                    .foregroundStyle(Palette.text2)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(Motion.smooth, value: statusLine)
            }
            Spacer()
            if !showSettings {
                IconButton(systemName: "arrow.clockwise", help: "Refresh", rotation: refreshTurns) {
                    withAnimation(.smooth(duration: 0.8)) { refreshTurns += 360 }
                    usage.refresh()
                    if tab == 1 { loadRecent() }
                    Task { await limits.refresh() }
                }
            }
            if !showSettings {
                IconButton(systemName: display.isNotch ? "menubar.rectangle" : "rectangle.topthird.inset.filled",
                           help: display.isNotch ? "Show in the menu bar" : "Show in the notch") {
                    display.toggle()
                }
            }
            IconButton(systemName: showSettings ? "xmark" : "gearshape.fill", help: "Settings") {
                withAnimation(Motion.smooth) { showSettings.toggle() }
            }
        }
        .padding(.horizontal, 2)
    }


    private var statusLine: String {
        let busy = sessions.busyCount
        let waiting = sessions.waitingCount
        if sessions.sessions.isEmpty { return "No sessions running" }
        if busy > 0 { return busy == 1 ? "1 session working" : "\(busy) sessions working" }
        if waiting > 0 { return waiting == 1 ? "1 waiting for you" : "\(waiting) waiting for you" }
        return "Nothing working"
    }

    // MARK: Limits

    private var limitsCard: some View {
        let session = limits.windows.first { $0.id == "five_hour" }
        let week = limits.windows.first { $0.id == "seven_day" }
        let extras = limits.windows.filter { !["five_hour", "seven_day"].contains($0.id) }

        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Plan limits") {
                if let error = limits.error {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Palette.text2)
                        .help(error)
                }
            }
            if limits.windows.isEmpty {
                Text(limits.error ?? "Checking your limits…")
                    .font(.app(13))
                    .foregroundStyle(Palette.text2)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    LimitBar(title: "Session", percent: session?.utilization,
                             subtitle: session?.resetsAt.map(formatReset) ?? "")
                    if let forecast = limits.forecast {
                        ForecastLine(forecast: forecast)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
                .animation(Motion.smooth, value: limits.forecast)
                LimitBar(title: "Week", percent: week?.utilization,
                         subtitle: week?.resetsAt.map(formatReset) ?? "")
                ForEach(extras) { w in
                    Chip(label: w.title, value: "\(Int(w.utilization.rounded()))%",
                         color: Palette.level(w.utilization, base: Palette.steel))
                }
            }
        }
        .card()
    }

    // MARK: Sessions

    private var sessionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Sessions") {
                if !sessions.sessions.isEmpty {
                    Text("\(sessions.sessions.count)")
                        .font(.app(11, .semibold))
                        .foregroundStyle(Palette.text)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.glass))
                        .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 0.5))
                        .contentTransition(.numericText())
                }
            }
            if sessions.sessions.isEmpty {
                HStack(spacing: 8) {
                    Text("Start `claude` in a terminal and it shows up here.")
                        .font(.app(13))
                        .foregroundStyle(Palette.text2)
                }
                .padding(.vertical, 4)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 2) {
                        ForEach(sessions.sessions) { session in
                            SessionRow(session: session, now: context.date)
                        }
                    }
                }
            }
        }
        .card()
    }

    // MARK: Recent

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Pick up where you left off")
            if recent.items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(Palette.text3)
                    Text(recent.loaded ? "No past sessions yet." : "Looking for past sessions…")
                        .font(.app(13))
                        .foregroundStyle(Palette.text2)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 2) {
                    ForEach(recent.items) { RecentRow(session: $0) }
                }
            }
        }
        .card()
    }

    // MARK: Tokens

    private var tokensCard: some View {
        let week = range == 1
        let summary = week ? usage.lastSevenDays : usage.today
        let values = week ? usage.weekByDay : usage.todayByHour
        let models = week ? usage.weekByModel : usage.todayByModel
        let hour = Calendar.current.component(.hour, from: Date())

        let bigNumber = hoveredBar.map { values.indices.contains($0) ? values[$0] : 0 } ?? summary.total
        let caption: String = {
            guard let i = hoveredBar else { return week ? "tokens this week" : "tokens today" }
            return week ? "on \(weekdayLabels[i])" : String(format: "at %02d:00", i)
        }()

        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Tokens") {
                PillToggle(options: ["Today", "Week"], selection: $range)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatTokens(bigNumber))
                    .font(.app(34, .ultraLight))
                    .foregroundStyle(hoveredBar == nil ? AnyShapeStyle(Palette.text) : AnyShapeStyle(Palette.silverGradient))
                    .contentTransition(.numericText())
                    .animation(Motion.quick, value: bigNumber)
                Text(caption)
                    .font(.app(13))
                    .foregroundStyle(Palette.text2)
            }

            InteractiveBars(
                values: values,
                labels: week ? weekdayLabels : ["00", "06", "12", "18"],
                current: week ? 6 : hour,
                future: week ? nil : hour + 1,
                hovered: $hoveredBar
            )
            .id(range) // regrow the bars when switching ranges

            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Chip(label: "Output", value: formatTokens(summary.output), color: Palette.silver)
                    Chip(label: "Input", value: formatTokens(summary.input), color: Palette.silver)
                }
                GridRow {
                    Chip(label: "Cache", value: formatTokens(summary.cacheRead + summary.cacheWrite), color: Palette.text3)
                    Chip(label: "Replies", value: summary.messages.formatted(), color: .white)
                }
            }

            if !models.isEmpty {
                Text(modelLine(models))
                    .font(.app(11))
                    .foregroundStyle(Palette.text3)
            }
        }
        .card()
    }

    private func modelLine(_ models: [ModelUsage]) -> String {
        let total = max(models.reduce(0) { $0 + $1.summary.total }, 1)
        return models.prefix(3).map {
            "\(prettyModelName($0.model)) \(Int((Double($0.summary.total) / Double(total) * 100).rounded()))%"
        }.joined(separator: "  ·  ")
    }

    private var weekdayLabels: [String] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).map { i in
            cal.date(byAdding: .day, value: i - 6, to: today)!.formatted(.dateTime.weekday(.abbreviated))
        }
    }
}

// MARK: - Session row

/// One big number in a card: a label, the number (38 pt), and a line of detail; optional 4 pt bar and status dot.
struct BigNumberCard: View {
    let label: String
    let number: String
    var detail: String = ""
    var warn = false
    var fraction: Double?
    var working = false
    var waiting = false
    var active = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(label).cardLabel()
                Spacer(minLength: 4)
                ClaudeStatusDot(working: working, waiting: waiting)
            }
            Spacer(minLength: 2)
            Text(number)
                .bigNumber()
                .foregroundStyle(warn ? Palette.red : Palette.text)
                .contentTransition(.numericText())
                .animation(Motion.smooth, value: number)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let fraction {
                ThinBar(fraction: fraction, color: warn ? Palette.red : Palette.silver).padding(.top, 2)
            }
            Spacer(minLength: 4)
            Text(detail).cardLabel()
        }
        .notchCard(active: active)
    }
}

/// Date, time and next event under the header, unless Info is switched off.
struct InfoHeaderLine: View {
    @ObservedObject var registry: ModuleRegistry

    var body: some View {
        if registry.isEnabled("info") {
            InfoStrip(calendar: AppModels.info.calendar)
        }
    }
}

/// The modules' own cards side by side (Pomodoro, Now Playing), between the header and the Claude tabs.
struct ModuleCardsRow: View {
    @ObservedObject var registry: ModuleRegistry

    var body: some View {
        let cards = registry.enabledModules.compactMap { module in module.expandedCard().map { (module.id, $0) } }
        if !cards.isEmpty {
            VStack(spacing: 8) {
                ForEach(cards, id: \.0) { $0.1 }
            }
        }
    }
}

struct SessionRow: View {
    let session: LiveSession
    let now: Date
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Palette.glass)
                    .overlay(Circle().strokeBorder(session.isBusy ? AnyShapeStyle(Palette.silverGradient) : AnyShapeStyle(Palette.line),
                                                   lineWidth: 1))
                    .frame(width: 32, height: 32)
                if session.isBusy {
                    WorkingBadge(hovering: hovering)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: session.isWaiting ? "questionmark" : "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(session.isWaiting ? Palette.text : Palette.silver)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayName)
                    .font(.app(13, .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(detail)
                    .font(.app(11))
                    .foregroundStyle(session.isBusy || session.isWaiting ? Palette.silver : Palette.text3)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.text3)
                .opacity(hovering ? 1 : 0)
                .offset(x: hovering ? 0 : -6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? Palette.hover : .clear)
        )
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
        .onTapGesture { TerminalLauncher.focus(session) }
        .contextMenu {
            Button("Jump to session") { TerminalLauncher.focus(session) }
            Button("Show in Finder") { TerminalLauncher.revealInFinder(session) }
        }
        .animation(Motion.smooth, value: session.isBusy)
        .help("Jump to this session · \(session.folder)")
    }

    private var detail: String {
        let elapsed = session.statusSince.map { formatClock(now.timeIntervalSince($0)) } ?? ""
        if session.isBusy { return "Working · \(elapsed)" }
        if session.isWaiting { return "Waiting for you · \(elapsed)" }
        return "Done · \(session.shortFolder)"
    }
}

private struct PopoverHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Hands back the NSWindow a SwiftUI view lives in.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Recent row

struct RecentRow: View {
    let session: RecentSession
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: hovering ? "play.fill" : "bubble.left")
                .font(.system(size: 11, weight: hovering ? .semibold : .regular))
                .foregroundStyle(hovering ? Palette.onSilver : Palette.silver)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .background(Circle().fill(hovering ? AnyShapeStyle(Palette.silverGradient) : AnyShapeStyle(Palette.glass)))
                .overlay(Circle().strokeBorder(Palette.line, lineWidth: hovering ? 0 : 1))

            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.app(13, .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text("\(session.shortFolder) · \(session.lastActive.formatted(.relative(presentation: .named)))")
                    .font(.app(11))
                    .foregroundStyle(Palette.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if hovering {
                Text("Resume")
                    .font(.app(11))
                    .foregroundStyle(Palette.silver)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? Palette.hover : .clear)
        )
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
        .onTapGesture { TerminalLauncher.resume(sessionId: session.id, cwd: session.cwd) }
        .contextMenu {
            Button("Resume in Terminal") { TerminalLauncher.resume(sessionId: session.id, cwd: session.cwd) }
            if let cwd = session.cwd {
                Button("Show in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: cwd)) }
                Button("Copy resume command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("cd '\(cwd)' && claude --resume \(session.id)", forType: .string)
                }
            }
        }
        .help("Resume in a new Terminal window")
    }
}

// MARK: - Forecast

/// One line under the session bar saying where the limit is heading at the current pace.
struct ForecastLine: View {
    let forecast: LimitForecast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .regular))
                .contentTransition(.symbolEffect(.replace))
            Text(text)
                .contentTransition(.opacity)
        }
        .font(.app(11))
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Based on how fast your session limit has filled over the last 30 minutes.")
    }

    private var minutesLeft: Double? {
        if case .hitsLimit(let at) = forecast { return at.timeIntervalSinceNow / 60 }
        return nil
    }

    private var symbol: String {
        switch forecast {
        case .idle: return "pause.circle"
        case .makesIt: return "checkmark.circle"
        case .hitsLimit: return "hourglass"
        }
    }

    private var text: String {
        switch forecast {
        case .idle: return "Steady, no usage in the last few minutes"
        case .makesIt: return "On pace to last until the reset"
        case .hitsLimit(let at): return "At this pace, full at \(at.formatted(date: .omitted, time: .shortened))"
        }
    }

    private var color: Color {
        guard let minutesLeft else { return forecast == .idle ? Palette.text3 : Palette.steel }
        return minutesLeft < 30 ? Palette.red : Palette.text2
    }
}

// MARK: - Formatting

func formatTokens(_ n: Int) -> String {
    let d = Double(n)
    switch d {
    case 1_000_000_000...: return String(format: "%.2fB", d / 1_000_000_000)
    case 1_000_000...: return String(format: "%.1fM", d / 1_000_000)
    case 1_000...: return String(format: "%.1fK", d / 1_000)
    default: return "\(n)"
    }
}

/// 2:54, 15:03, 1:02:10
func formatClock(_ t: TimeInterval) -> String {
    let s = max(0, Int(t))
    if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) }
    return String(format: "%d:%02d", s / 60, s % 60)
}

func formatReset(_ date: Date) -> String {
    let s = date.timeIntervalSinceNow
    if s <= 0 { return "resetting now" }
    if s < 24 * 3600 {
        let h = Int(s) / 3600, m = Int(s) % 3600 / 60
        return h > 0 ? "resets in \(h)h \(m)m" : "resets in \(m)m"
    }
    return "resets " + date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
}
