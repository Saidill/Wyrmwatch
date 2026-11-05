import AppKit
import Combine
import SwiftUI

/// Pomodoro "Ember": every focus session is an ember the dragon keeps alight. Wins the live notch while running.
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

    func liveLeading() -> AnyView { AnyView(PomodoroLiveDragon(timer: timer)) }
    func liveTrailing() -> AnyView { AnyView(PomodoroLiveTime(timer: timer)) }
    /// The menu bar popover's Focus card: the compact row, opening the full setup only when asked.
    func expandedCard() -> AnyView? { AnyView(FocusCard(timer: timer)) }
    func setVisible(_ visible: Bool) {}

    /// Sends the pop for a finished phase. Also used by the self-test.
    func pop(_ event: PomodoroTimer.Event) {
        switch event {
        case .focusDone:
            popSink.yield(NotchPop(kind: .pomodoro, duration: 8) { FocusDonePop(timer: self.timer) })
        case .breakDone:
            popSink.yield(NotchPop(kind: .pomodoro, duration: 8) { BreakDonePop(timer: self.timer) })
        case .countdownDone:
            popSink.yield(NotchPop(kind: .pomodoro, duration: 8) { TimesUpPop() })
        }
    }

    private func phaseEnded(_ event: PomodoroTimer.Event) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: PomodoroTimer.Keys.haptic) {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        // A short alarm, so the end of a phase is noticed even when looking elsewhere.
        if defaults.bool(forKey: PomodoroTimer.Keys.sound) { Notifier.shared.playAlarm() }
        if DisplayModeController.shared.isNotch {
            pop(event)
        } else {
            switch event {
            case .focusDone: Notifier.shared.notify(title: "Focus done", body: "Your break has started.")
            case .breakDone: Notifier.shared.notify(title: "Break over", body: "Ready to focus again?")
            case .countdownDone: Notifier.shared.notify(title: "Time's up", body: "Your countdown has finished.")
            }
        }
    }
}

// MARK: - Live

/// Left of the camera: the dragon keeping watch while focusing, coiled asleep while resting.
private struct PomodoroLiveDragon: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        FocusIcon()
            .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .foregroundStyle(Palette.text2)
            .frame(width: 13, height: 13)
            .opacity(timer.isPaused ? 0.6 : 1)
    }
}

/// Right of the camera: time left.
private struct PomodoroLiveTime: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        HStack(spacing: 4) {
            PhaseRing(timer: timer, diameter: 10)
            PomodoroDigits(timer: timer, size: 10.5, color: Palette.silverBright, rolling: false)
                .fixedSize()
        }
        .opacity(timer.isPaused ? 0.6 : 1)
    }
}

// MARK: - Pops

private struct PopButton: View {
    let title: String
    var primary = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.app(11.5, .medium))
                .foregroundStyle(primary ? Palette.onSilver : Palette.text)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(primary ? Palette.silver : (hovering ? Palette.buttonHi : Palette.button)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
    }
}

/// Focus is over and the break is already counting down: the dragon breathes fire, one more session dot lights up.
private struct FocusDonePop: View {
    @ObservedObject var timer: PomodoroTimer
    @State private var lit = 0

    var body: some View {
        HStack(spacing: 4) {
            PopIcon(systemName: "checkmark")
            VStack(alignment: .leading, spacing: 4) {
                Text("Focus done")
                    .font(.app(13, .medium))
                    .foregroundStyle(Palette.text)
                HStack(spacing: 6) {
                    Text(timer.phase == .longBreak ? "Long break" : "Break")
                        .font(.app(11))
                        .foregroundStyle(Palette.text2)
                    PomodoroDigits(timer: timer, size: 11, color: Palette.silverBright)
                        .fixedSize()
                }
                EmberDots(lit: lit, total: timer.sessionsTarget, size: 5)
            }
            Spacer(minLength: 6)
            PopButton(title: "Skip break", primary: false) {
                timer.skip()
                NotchWindowController.shared.dismissPop()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { NotchWindowController.shared.expand() }
        .onAppear {
            // The dots appear as they were, then the new one lights up.
            lit = max(timer.completedInCycle - 1, 0)
            withAnimation(Motion.popIn.delay(0.35)) { lit = timer.completedInCycle }
        }
    }
}

/// The break is over: the dragon wakes up and asks to go again.
private struct BreakDonePop: View {
    @ObservedObject var timer: PomodoroTimer
    @State private var awake = false

    var body: some View {
        HStack(spacing: 10) {
            PopIcon(systemName: "timer")
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


/// Focus in the menu bar popover: one compact row, so the popover never outgrows the screen.
private struct FocusCard: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timer.isActive ? (timer.phase.isBreak ? "Break" : "Focus \(timer.sessionNumber)/\(timer.sessionsTarget)") : "Focus")
                    .cardLabel()
                PomodoroDigits(timer: timer, size: 28, weight: .semibold, color: Palette.text)
                    .tracking(-1)
                    .opacity(timer.isPaused ? 0.6 : 1)
            }
            Spacer(minLength: 6)
            if timer.isActive {
                CardButton(systemName: timer.isPaused ? "play.fill" : "pause.fill", active: true) { timer.toggle() }
                    .frame(width: 44)
                CardButton(systemName: "stop.fill") { timer.stopToSetup() }
                    .frame(width: 44)
            } else {
                PresetButton(title: "25/5") { timer.startPomodoro(.classic) }.frame(width: 64)
                PresetButton(title: "50/10") { timer.startPomodoro(.long) }.frame(width: 64)
            }
        }
        .card()
    }
}

/// The icon at the start of a pop: a symbol on a #2C2C2E tile.
struct PopIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Palette.text)
            .frame(width: 40, height: 40)
            .background(Radius.shape(Radius.button).fill(Palette.button))
            .padding(.trailing, 8)
    }
}

/// A countdown has finished.
private struct TimesUpPop: View {
    var body: some View {
        HStack(spacing: 4) {
            PopIcon(systemName: "timer")
            Text("Time's up")
                .font(.app(13, .medium))
                .foregroundStyle(Palette.text)
            Spacer(minLength: 6)
            PopButton(title: "OK", primary: false) { NotchWindowController.shared.dismissPop() }
        }
        .contentShape(Rectangle())
        .onTapGesture { NotchWindowController.shared.expand() }
    }
}
