import Combine
import SwiftUI

/// Claude Code in the notch: working sessions and the session limit in the live notch,
/// a "finished" pop when a session is done.
@MainActor
final class ClaudeModule: NotchModule {
    let id = "claude"
    let pops: AsyncStream<NotchPop>
    private let popSink: AsyncStream<NotchPop>.Continuation
    private let sessions: SessionMonitor
    private let limits: PlanLimitClient
    private var subscriptions: Set<AnyCancellable> = []

    init(sessions: SessionMonitor, limits: PlanLimitClient) {
        self.sessions = sessions
        self.limits = limits
        (pops, popSink) = AsyncStream.makeStream(of: NotchPop.self)
        // Our priority follows the sessions and the limit.
        sessions.objectWillChange.merge(with: limits.objectWillChange)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        sessions.$finishCount.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.sessionFinished() } }
        }.store(in: &subscriptions)
    }

    var livePriority: Int? {
        if sessions.busyCount > 0 { return 2 }
        guard let percent = limits.fiveHourPercent else { return nil }
        if percent >= 90 { return 3 }
        let threshold = UserDefaults.standard.integer(forKey: Settings.limitThresholdKey)
        if threshold > 0, percent >= Double(threshold) { return 5 }
        return nil
    }

    func liveLeading() -> AnyView {
        AnyView(ClaudeLiveDragon(sessions: sessions))
    }

    func liveTrailing() -> AnyView {
        AnyView(ClaudeLiveLimit(limits: limits))
    }

    /// The Claude panel is the Now / Recent / Usage tabs, not a card.
    func expandedCard() -> AnyView? { nil }

    func setVisible(_ visible: Bool) {}

    /// Sends the "finished" pop. Also used by the self-test.
    func pop(_ session: LiveSession) {
        popSink.yield(NotchPop(kind: .claude, duration: 5) { ClaudeFinishedPop(session: session) })
    }

    private func sessionFinished() {
        guard let session = sessions.lastFinished else { return }
        pop(session)
    }
}

/// Dragon on the left of the live notch: working while a session runs, otherwise watching.
private struct ClaudeLiveDragon: View {
    @ObservedObject var sessions: SessionMonitor

    var body: some View {
        DragonView(mood: sessions.busyCount > 0 ? .working : .idle, size: 26, animated: false)
            .padding(.top, 2)
    }
}

/// Session limit on the right of the live notch: a mini ring and the percentage.
private struct ClaudeLiveLimit: View {
    @ObservedObject var limits: PlanLimitClient

    var body: some View {
        HStack(spacing: 4) {
            MiniRing(fraction: (limits.fiveHourPercent ?? 0) / 100)
            Text(limits.fiveHourPercent.map { "\(Int($0.rounded()))%" } ?? "")
                .font(.app(10, .medium))
                .foregroundStyle(Palette.text2)
                .monospacedDigit()
        }
    }
}

/// Tiny session-limit ring for the live notch: silver, amber from 80%, rose from 90%,
/// where it also gives a single pulse every 4 seconds.
private struct MiniRing: View {
    let fraction: Double
    @Environment(\.animationsPaused) private var paused

    var body: some View {
        let percent = fraction * 100
        let critical = percent >= 90
        TimelineView(.animation(minimumInterval: 4, paused: paused || !critical)) { timeline in
            ring(color: Palette.level(percent, base: Palette.silver, warn: 80))
                .keyframeAnimator(initialValue: 1.0,
                                  trigger: critical ? Int(timeline.date.timeIntervalSinceReferenceDate / 4) : 0) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(1.25, duration: 0.25)
                    SpringKeyframe(1.0, duration: 0.35)
                }
        }
        .frame(width: 12, height: 12)
        .animation(Motion.smooth, value: fraction)
    }

    private func ring(color: Color) -> some View {
        ZStack {
            Circle().stroke(Palette.line, lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// "Done" card that drops out of the notch when a session finishes.
private struct ClaudeFinishedPop: View {
    let session: LiveSession
    @State private var checked = false

    var body: some View {
        HStack(spacing: 4) {
            // Room on the right for its fire.
            DragonView(mood: .happy, size: 44, fireRoom: 0.6)
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(Palette.onSilver)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Palette.silverGradient))
                        .overlay(Circle().strokeBorder(.black, lineWidth: 1.5))
                        .offset(x: 30)
                }
                .scaleEffect(checked ? 1 : 0.6)
                .opacity(checked ? 1 : 0)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.displayName) finished")
                    .font(.app(13, .medium))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(session.shortFolder.isEmpty ? "Waiting for you" : session.shortFolder)
                    .font(.app(11))
                    .foregroundStyle(Palette.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { NotchWindowController.shared.jump(to: session) } label: {
                Text("Jump")
                    .font(.app(11, .medium))
                    .foregroundStyle(Palette.onSilver)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Palette.silverGradient))
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { NotchWindowController.shared.expand() }
        .onAppear { withAnimation(Motion.popIn.delay(0.08)) { checked = true } }
    }
}
