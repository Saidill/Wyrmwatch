import AppKit
import Combine
import SwiftUI

/// Pomodoro "Ember": every focus session is an ember the wyrm keeps alight. Wins the live notch while running.
@MainActor
final class PomodoroModule: NotchModule {
    let id = "pomodoro"
    let timer: PomodoroTimer
    let pops: AsyncStream<NotchPop>
    private let popSink: AsyncStream<NotchPop>.Continuation
    private var subscriptions: Set<AnyCancellable> = []

    init(timer: PomodoroTimer) {
        self.timer = timer
        (pops, popSink) = AsyncStream.makeStream(of: NotchPop.self)
        timer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        timer.events.sink { [weak self] event in self?.phaseEnded(event) }.store(in: &subscriptions)
    }

    var livePriority: Int? { timer.isActive ? 1 : nil }

    func liveLeading() -> AnyView { AnyView(PomodoroLiveWyrm(timer: timer)) }
    func liveTrailing() -> AnyView { AnyView(PomodoroLiveTime(timer: timer)) }
    func liveAccent() -> AnyView? { AnyView(EmberFuse(timer: timer)) }
    func expandedCard() -> AnyView? { AnyView(PomodoroCard(timer: timer)) }
    func setVisible(_ visible: Bool) {}

    /// Sends the pop for a finished phase. Also used by the self-test.
    func pop(_ event: PomodoroTimer.Event) {
        switch event {
        case .focusDone:
            popSink.yield(NotchPop(kind: .pomodoro, duration: 8) { FocusDonePop(timer: self.timer) })
        case .breakDone:
            popSink.yield(NotchPop(kind: .pomodoro, duration: 8) { BreakDonePop(timer: self.timer) })
        }
    }

    private func phaseEnded(_ event: PomodoroTimer.Event) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: PomodoroTimer.Keys.haptic) {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        if defaults.bool(forKey: PomodoroTimer.Keys.sound) { Notifier.shared.playSound() }
        if DisplayModeController.shared.isNotch {
            pop(event)
        } else {
            switch event {
            case .focusDone: Notifier.shared.notify(title: "Focus done", body: "Time for a break.")
            case .breakDone: Notifier.shared.notify(title: "Break over", body: "Ready to focus again?")
            }
        }
    }
}

// MARK: - Live

/// Left of the camera: the wyrm keeping watch while focusing, coiled asleep while resting.
private struct PomodoroLiveWyrm: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        WyrmView(mood: timer.phase.isBreak ? .sleeping : .guarding, size: 26)
            .padding(.top, 2)
            .opacity(timer.isPaused ? 0.6 : 1)
            .transformEnvironment(\.animationsPaused) { paused in paused = paused || timer.isPaused }
    }
}

/// Right of the camera: time left.
private struct PomodoroLiveTime: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        PomodoroDigits(timer: timer, size: 11, color: emberColor(timer.phase))
            .opacity(timer.isPaused ? 0.6 : 1)
    }
}

// MARK: - Pops

private struct PopButton: View {
    let title: String
    var primary = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.app(11, .medium))
                .foregroundStyle(primary ? Palette.onSilver : Palette.text2)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(primary ? AnyShapeStyle(Palette.silverGradient) : AnyShapeStyle(Palette.glass)))
                .overlay(Capsule().strokeBorder(Palette.rim, lineWidth: primary ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// Focus is over: the wyrm breathes blue fire, and one more of the four embers lights up.
private struct FocusDonePop: View {
    @ObservedObject var timer: PomodoroTimer
    @State private var lit = 0

    var body: some View {
        HStack(spacing: 4) {
            WyrmView(mood: .happy, size: 44, fireRoom: 0.6)
            VStack(alignment: .leading, spacing: 6) {
                Text("Focus done")
                    .font(.app(13, .medium))
                    .foregroundStyle(Palette.text)
                EmberDots(lit: lit)
            }
            Spacer(minLength: 6)
            PopButton(title: "Start break") {
                timer.start()
                NotchWindowController.shared.dismissPop()
            }
            PopButton(title: "Skip", primary: false) {
                timer.skip()
                NotchWindowController.shared.dismissPop()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { NotchWindowController.shared.expand() }
        .onAppear {
            // The dots appear as they were, then the new one lights up.
            lit = max(timer.completedInCycle - 1, 0)
            if timer.completedInCycle == 0 { lit = PomodoroTimer.sessionsPerCycle - 1 }
            withAnimation(Motion.popIn.delay(0.35)) {
                lit = timer.completedInCycle == 0 ? PomodoroTimer.sessionsPerCycle : timer.completedInCycle
            }
        }
    }
}

/// The break is over: the wyrm wakes up and asks to go again.
private struct BreakDonePop: View {
    @ObservedObject var timer: PomodoroTimer
    @State private var awake = false

    var body: some View {
        HStack(spacing: 10) {
            WyrmView(mood: awake ? .guarding : .sleeping, size: 40)
            Text("Ready to focus again?")
                .font(.app(13, .medium))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
            Spacer(minLength: 6)
            PopButton(title: "Focus") {
                timer.start()
                NotchWindowController.shared.dismissPop()
            }
            PopButton(title: "Later", primary: false) { NotchWindowController.shared.dismissPop() }
        }
        .contentShape(Rectangle())
        .onTapGesture { NotchWindowController.shared.expand() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { withAnimation(Motion.smooth) { awake = true } }
        }
    }
}

// MARK: - Card

/// The Pomodoro card in the expanded notch: ring, embers, presets, controls and today's tally.
struct PomodoroCard: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Pomodoro") {
                Text(phaseLabel)
                    .font(.app(10.5, .medium))
                    .foregroundStyle(emberColor(timer.phase))
            }
            HStack(spacing: 10) {
                EmberRing(timer: timer, size: 54)
                VStack(alignment: .leading, spacing: 6) {
                    EmberDots(lit: timer.completedInCycle)
                    Text("\(timer.todaySessions) today")
                        .font(.app(10.5))
                        .foregroundStyle(Palette.text2)
                    Text("\(timer.todayMinutes) min focus")
                        .font(.app(10.5))
                        .foregroundStyle(Palette.text3)
                }
                .monospacedDigit()
                .lineLimit(1)
            }
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                IconButton(systemName: timer.isRunning ? "pause.fill" : "play.fill",
                           help: timer.isRunning ? "Pause" : "Start") { timer.toggle() }
                IconButton(systemName: "arrow.counterclockwise", help: "Reset") { timer.reset() }
                IconButton(systemName: "forward.end.fill", help: "Skip") { timer.skip() }
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                presetChip("25/5", PomodoroTimer.Preset.classic)
                presetChip("50/10", PomodoroTimer.Preset.long)
                presetChip("Custom", nil)
            }
            .disabled(timer.isActive)
            .opacity(timer.isActive ? 0.5 : 1)
        }
        .card(fillHeight: true)
    }

    private var phaseLabel: String {
        let base = switch timer.phase {
        case .focus: "Focus"
        case .shortBreak: "Break"
        case .longBreak: "Long break"
        }
        return timer.isPaused ? "\(base) · paused" : base
    }

    private func presetChip(_ title: String, _ preset: PomodoroTimer.Preset?) -> some View {
        let selected = timer.preset == preset
        return Text(title)
            .font(.app(10, .medium))
            .foregroundStyle(selected ? Palette.onSilver : Palette.text2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(selected ? AnyShapeStyle(Palette.silverGradient) : AnyShapeStyle(Palette.glass)))
            .contentShape(Capsule())
            .onTapGesture {
                // Custom lengths are set in Settings; the chip only shows they're in use.
                guard let preset else { return }
                withAnimation(Motion.smooth) { timer.apply(preset) }
            }
            .help(preset == nil ? "Set custom lengths in Settings" : "\(preset!.focus) min focus, \(preset!.shortBreak) min break")
    }
}
