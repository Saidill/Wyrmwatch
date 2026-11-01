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

/// Left of the camera: the dragon keeping watch while focusing, coiled asleep while resting.
private struct PomodoroLiveDragon: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        DragonView(mood: timer.phase.isBreak ? .sleeping : .guarding, size: 26, animated: false)
            .padding(.top, 2)
            .opacity(timer.isPaused ? 0.6 : 1)
            .transformEnvironment(\.animationsPaused) { paused in paused = paused || timer.isPaused }
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

/// Focus is over: the dragon breathes blue fire, and one more of the four embers lights up.
private struct FocusDonePop: View {
    @ObservedObject var timer: PomodoroTimer
    @State private var lit = 0

    var body: some View {
        HStack(spacing: 4) {
            DragonView(mood: .happy, size: 44, fireRoom: 0.6)
            VStack(alignment: .leading, spacing: 6) {
                Text("Focus done")
                    .font(.app(13, .medium))
                    .foregroundStyle(Palette.text)
                EmberDots(lit: lit, total: timer.sessionsTarget)
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
            DragonView(mood: awake ? .guarding : .sleeping, size: 40)
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
    @State private var setup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if setup && !timer.isActive {
                FocusPage(timer: timer)
                NotchChip(title: "Close") { withAnimation(Motion.page) { setup = false } }
                    .frame(width: 80)
            } else {
                FocusMini(timer: timer) { withAnimation(Motion.page) { setup = true } }
                    .frame(height: 58)
            }
        }
        .card()
    }
}
