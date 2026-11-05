import SwiftUI

/// Home: three cards side by side, all 118 pt tall, 8 pt apart, widths 1 : 1.25 : 1 — Claude, Music, Focus.
/// One big number (or the song) per card.
struct HomePage: View {
    @ObservedObject var bridge: MusicBridge
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var limits: PlanLimitClient
    @ObservedObject var sessions: SessionMonitor
    var coverSpace: Namespace.ID?
    static let height: CGFloat = 118

    var body: some View {
        GeometryReader { geo in
            let unit = (geo.size.width - 16) / 3.25
            HStack(spacing: 8) {
                ClaudeCard(limits: limits, sessions: sessions)
                    .frame(width: unit)
                    .probe("home.claude")
                    .cardAppear(0)
                MusicCard(bridge: bridge, coverSpace: coverSpace)
                    .frame(width: unit * 1.25)
                    .probe("home.music")
                    .cardAppear(1)
                FocusCard(timer: timer)
                    .frame(width: unit)
                    .probe("home.focus")
                    .cardAppear(2)
            }
        }
        .frame(height: Self.height)
    }
}

// MARK: - Claude

/// "Claude · session" (with a red dot and "working" while busy), the session limit as the big number,
/// and one status line: what Claude is doing, and when the limit resets.
private struct ClaudeCard: View {
    @ObservedObject var limits: PlanLimitClient
    @ObservedObject var sessions: SessionMonitor

    var body: some View {
        let percent = limits.fiveHourPercent
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Claude · session").cardLabel()
                Spacer(minLength: 4)
                if sessions.busyCount > 0 || sessions.waitingCount > 0 {
                    HStack(spacing: 4) {
                        ClaudeStatusDot(working: sessions.busyCount > 0, waiting: sessions.waitingCount > 0)
                        Text(sessions.busyCount > 0 ? "working" : "waiting").font(.app(10.5)).foregroundStyle(Palette.text2)
                    }
                    .fixedSize()
                }
            }
            Spacer(minLength: 2)
            Text(percent.map { "\(Int($0.rounded()))%" } ?? "–")
                .bigNumber()
                .foregroundStyle(Palette.level(percent ?? 0, base: Palette.text))
                .contentTransition(.numericText())
                .animation(Motion.smooth, value: percent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ThinBar(fraction: (percent ?? 0) / 100, color: Palette.level(percent ?? 0, base: Palette.silver))
                .padding(.top, 2)
            Spacer(minLength: 6)
            Text(statusLine).cardLabel()
        }
        .notchCard()
    }

    /// "Editing HomePage.swift · resets in 3h 20m", or the project name when there's no activity to show.
    private var statusLine: String {
        let active = sessions.sessions.first { $0.isWaiting } ?? sessions.sessions.first { $0.isBusy }
        let what: String? = active.map { session in
            session.isWaiting ? "Waiting for you" : (sessions.activity[session.pid] ?? session.displayName)
        } ?? sessions.sessions.first?.displayName
        let reset = limits.windows.first { $0.id == "five_hour" }?.resetsAt.map(formatReset)
        return [what, reset].compactMap { $0 }.joined(separator: " · ").ifEmpty("No session running")
    }
}

// MARK: - Music

/// Cover (46 pt), title and artist; the song's progress; previous, play/pause, next. "Play music" when nothing plays.
private struct MusicCard: View {
    @ObservedObject var bridge: MusicBridge
    var coverSpace: Namespace.ID?
    @Environment(\.animationsPaused) private var paused

    var body: some View {
        Group {
            if let track = bridge.track {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        CoverArt(image: bridge.artwork, id: track.id, size: 46, radius: Radius.preset)
                            .modifier(MatchedCover(space: coverSpace))
                            .probe("home.cover")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).songTitle()
                            Text(track.artist).cardLabel()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .probe("home.title")
                    }
                    Spacer(minLength: 6)
                    TimelineView(.animation(minimumInterval: 1, paused: paused || !bridge.isPlaying)) { context in
                        ThinBar(fraction: bridge.currentPosition(at: context.date) / max(track.duration, 1))
                    }
                    .frame(height: 4)
                    .probe("home.progress")
                    Spacer(minLength: 6)
                    GeometryReader { geo in
                        let unit = (geo.size.width - 12) / 3.3
                        HStack(spacing: 6) {
                            CardButton(systemName: "backward.fill", help: "Previous") { bridge.previous() }
                                .frame(width: unit)
                            CardButton(systemName: bridge.isPlaying ? "pause.fill" : "play.fill", active: true,
                                       help: bridge.isPlaying ? "Pause" : "Play") { bridge.playPause() }
                                .frame(width: unit * 1.3)
                            CardButton(systemName: "forward.fill", help: "Next") { bridge.next() }
                                .frame(width: unit)
                        }
                    }
                    .frame(height: 30)
                    .probe("home.controls")
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Music").cardLabel()
                    Spacer(minLength: 0)
                    CardButton(systemName: "play.fill", title: "Play music", active: true, height: 34) { bridge.startMusic() }
                        .probe("home.startMusic")
                }
            }
        }
        .notchCard()
    }
}

// MARK: - Focus

/// "Focus n/N" or "Break", the time left as the big number, then pause/resume and Stop.
/// When stopped: "Focus" and the 25/5 and 50/10 presets.
private struct FocusCard: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if timer.isActive {
                Text(label).cardLabel()
                Spacer(minLength: 2)
                PomodoroDigits(timer: timer, size: 38, weight: .semibold, color: Palette.text)
                    .tracking(-1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(timer.isPaused ? 0.6 : 1)
                    .probe("home.focus.time")
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    CardButton(systemName: timer.isPaused ? "play.fill" : "pause.fill", active: true,
                               help: timer.isPaused ? "Resume" : "Pause") { timer.toggle() }
                    CardButton(systemName: "stop.fill", help: "Stop") { timer.stopToSetup() }
                }
                .probe("home.focus.buttons")
            } else {
                Text("Focus").cardLabel()
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    PresetButton(title: "25/5") { timer.startPomodoro(.classic) }
                    PresetButton(title: "50/10") { timer.startPomodoro(.long) }
                }
                .probe("home.focus.presets")
            }
        }
        .notchCard()
    }

    private var label: String {
        if timer.mode == .countdown { return "Timer" }
        switch timer.phase {
        case .focus: return "Focus \(timer.sessionNumber)/\(timer.sessionsTarget)"
        case .shortBreak: return "Break"
        case .longBreak: return "Long break"
        }
    }
}

/// `matchedGeometryEffect` for the album cover, when a namespace is given.
struct MatchedCover: ViewModifier {
    let space: Namespace.ID?

    func body(content: Content) -> some View {
        if let space {
            content.matchedGeometryEffect(id: "cover", in: space)
        } else {
            content
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
