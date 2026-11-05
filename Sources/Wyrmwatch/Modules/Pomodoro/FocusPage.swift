import SwiftUI

/// The Focus page: on the left a 200 pt card with the time (46 pt) and pause / +5; on the right the mode
/// (Pomodoro | Countdown) and a 3 × 2 grid of presets. Custom opens steppers for the chosen mode.
struct FocusPage: View {
    @ObservedObject var timer: PomodoroTimer
    @State private var mode: PomodoroTimer.Mode = .pomodoro
    @State private var custom = false
    @State private var countdownMinutes = 10

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            timeCard
                .frame(width: 200, height: 118)
                .probe("focus.time")
                .cardAppear(0)
            VStack(alignment: .leading, spacing: 8) {
                ModeSwitch(selection: $mode)
                    .probe("focus.mode")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    PresetButton(title: "25/5", selected: running(.pomodoro, .classic)) { timer.startPomodoro(.classic) }
                    PresetButton(title: "50/10", selected: running(.pomodoro, .long)) { timer.startPomodoro(.long) }
                    PresetButton(title: "90/15", selected: running(.pomodoro, .extended)) { timer.startPomodoro(.extended) }
                    PresetButton(title: "05:00", selected: runningCountdown(5)) { timer.startCountdown(minutes: 5) }
                    PresetButton(title: "15:00", selected: runningCountdown(15)) { timer.startCountdown(minutes: 15) }
                    PresetButton(title: "Custom", selected: custom) { withAnimation(Motion.resize) { custom.toggle() } }
                }
                .probe("focus.presets")
                if custom {
                    customRow
                        .transition(.opacity.combined(with: .offset(y: -5)))
                        .probe("focus.custom")
                }
            }
            .frame(maxWidth: .infinity)
            .cardAppear(1)
        }
        .onAppear { mode = timer.isActive ? timer.mode : mode }
        .onChange(of: timer.mode) { _, next in if timer.isActive { mode = next } }
    }

    // MARK: Time card

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption).cardLabel()
            Spacer(minLength: 2)
            PomodoroDigits(timer: timer, size: 46, weight: .semibold, color: Palette.text)
                .tracking(-1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(timer.isPaused ? 0.6 : 1)
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                if timer.isActive {
                    CardButton(systemName: timer.isPaused ? "play.fill" : "pause.fill", active: true,
                               help: timer.isPaused ? "Resume" : "Pause") { timer.toggle() }
                } else {
                    CardButton(systemName: "play.fill", title: "Start", active: true) { startChosen() }
                }
                CardButton(title: "+5", help: "Five more minutes") { addFive() }
            }
        }
        .notchCard()
    }

    private var caption: String {
        if timer.isActive {
            if timer.mode == .countdown { return "Timer" + (timer.isPaused ? " · paused" : "") }
            let task = timer.task.trimmingCharacters(in: .whitespacesAndNewlines)
            let head = switch timer.phase {
            case .focus: "Focus \(timer.sessionNumber)/\(timer.sessionsTarget)"
            case .shortBreak: "Break"
            case .longBreak: "Long break"
            }
            return [head, task.isEmpty ? nil : task, timer.isPaused ? "paused" : nil].compactMap { $0 }.joined(separator: " · ")
        }
        return mode == .pomodoro ? "Focus \(timer.focusMinutes)/\(timer.shortBreakMinutes)" : "Countdown"
    }

    private func startChosen() {
        if mode == .countdown { timer.startCountdown(minutes: countdownMinutes) } else { timer.start() }
    }

    private func addFive() {
        if timer.isActive {
            timer.addFiveMinutes()
        } else if mode == .countdown {
            countdownMinutes = min(countdownMinutes + 5, 180)
        } else {
            timer.focusMinutes = min(timer.focusMinutes + 5, PomodoroTimer.focusRange.upperBound)
        }
    }

    private func running(_ mode: PomodoroTimer.Mode, _ preset: PomodoroTimer.Preset) -> Bool {
        timer.isActive && timer.mode == mode && timer.preset == preset
    }

    private func runningCountdown(_ minutes: Int) -> Bool {
        timer.isActive && timer.mode == .countdown && Int(timer.phaseLength.rounded()) == minutes * 60
    }

    // MARK: Custom

    @ViewBuilder private var customRow: some View {
        HStack(spacing: 12) {
            if mode == .pomodoro {
                MinuteStepper(label: "Focus", unit: "min", value: $timer.focusMinutes, range: PomodoroTimer.focusRange, step: 5)
                MinuteStepper(label: "Break", unit: "min", value: $timer.shortBreakMinutes, range: PomodoroTimer.breakRange, step: 1)
                MinuteStepper(label: "×", unit: "", value: $timer.sessionsTarget, range: PomodoroTimer.sessionsRange, step: 1)
            } else {
                MinuteStepper(label: "Minutes", unit: "min", value: $countdownMinutes, range: 1...180, step: 1)
            }
            Spacer(minLength: 0)
            CardButton(systemName: "play.fill", title: "Start", active: true) {
                startChosen()
                withAnimation(Motion.resize) { custom = false }
            }
            .frame(width: 90)
        }
    }
}

/// Pomodoro | Countdown.
private struct ModeSwitch: View {
    @Binding var selection: PomodoroTimer.Mode
    @Namespace private var glide

    var body: some View {
        HStack(spacing: 2) {
            ForEach([PomodoroTimer.Mode.pomodoro, .countdown], id: \.self) { mode in
                Button { withAnimation(Motion.quick) { selection = mode } } label: {
                    Text(mode == .pomodoro ? "Pomodoro" : "Countdown")
                        .font(.app(11.5, .medium))
                        .foregroundStyle(selection == mode ? Palette.text : Palette.text2)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background {
                            if selection == mode {
                                Radius.shape(Radius.tab).fill(Palette.buttonHi).matchedGeometryEffect(id: "mode", in: glide)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(2)
        .background(Radius.shape(Radius.button).fill(Palette.card))
    }
}

/// "Focus  [−] 25 min [+]".
struct MinuteStepper: View {
    let label: String
    let unit: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.app(11))
                .foregroundStyle(Palette.text2)
            HStack(spacing: 0) {
                button("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - step) }
                Text(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
                    .font(.app(12, .medium))
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minWidth: unit.isEmpty ? 20 : 44)
                button("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + step) }
            }
            .background(Radius.shape(Radius.button).fill(Palette.button))
        }
        .animation(Motion.quick, value: value)
    }

    private func button(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(enabled ? Palette.text2 : Palette.text3)
                .frame(width: 24, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
    }
}
