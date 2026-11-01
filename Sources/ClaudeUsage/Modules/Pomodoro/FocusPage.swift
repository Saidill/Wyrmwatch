import SwiftUI

/// The Focus page. Running: [round button 42 | what's on | time 50 pt], progress underneath.
/// Stopped: the setup (presets, lengths, sessions, an optional task, Start).
struct FocusPage: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        ZStack(alignment: .topLeading) {
            if timer.isActive {
                FocusRunning(timer: timer)
                    .transition(.opacity.combined(with: .offset(y: 5)))
            } else {
                FocusSetup(timer: timer)
                    .transition(.opacity.combined(with: .offset(y: 5)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(Motion.page, value: timer.isActive)
    }
}

// MARK: - Running

private struct FocusRunning: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                RoundButton(systemName: timer.isPaused ? "play.fill" : "pause.fill", diameter: 42,
                            help: timer.isPaused ? "Lanjut" : "Pause") { timer.toggle() }
                    .probe("focus.button")
                VStack(alignment: .leading, spacing: 6) {
                    Text(subtitle)
                        .font(.app(13, .medium))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 6) {
                        TextAction(title: "+5 mnt") { timer.addFiveMinutes() }
                        TextAction(title: "Lewati") { timer.skip() }
                        TextAction(title: "Stop") { timer.stopToSetup() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .probe("focus.info")
                PomodoroDigits(timer: timer, size: 50, weight: .light, color: Palette.silverBright)
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(timer.isPaused ? 0.6 : 1)
                    .probe("focus.time")
            }
            TickScale(timer: timer)
                .probe("focus.progress")
        }
    }

    private var subtitle: String {
        let task = timer.task.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = switch timer.phase {
        case .focus: "Fokus \(timer.sessionNumber)/\(timer.sessionsTarget)"
        case .shortBreak: "Istirahat"
        case .longBreak: "Istirahat panjang"
        }
        let paused = timer.isPaused ? " · dijeda" : ""
        return (task.isEmpty ? head : "\(head) · \(task)") + paused
    }
}

private struct TextAction: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.app(11, .medium))
                .foregroundStyle(hovering ? Palette.text : Palette.text2)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(hovering ? Palette.buttonHi : Palette.button))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
    }
}

// MARK: - Setup

private struct FocusSetup: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                NotchChip(title: "Klasik 25/5", selected: timer.preset == .classic) { timer.apply(.classic) }
                    .frame(width: 104)
                NotchChip(title: "Dalam 50/10", selected: timer.preset == .long) { timer.apply(.long) }
                    .frame(width: 104)
                NotchChip(title: "Custom", selected: timer.preset == nil) {}
                    .frame(width: 80)
                Spacer(minLength: 0)
            }
            .probe("focus.presets")
            // In a row across the notch; stacked in the narrower menu bar popover.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { steppers; Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 8) { steppers }
            }
            .probe("focus.steppers")
            HStack(spacing: 10) {
                TextField("Tugas (opsional)", text: $timer.task)
                    .textFieldStyle(.plain)
                    .font(.app(12))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(Palette.button))
                    .onSubmit { timer.start() }
                Button { timer.start() } label: {
                    Label("Mulai", systemImage: "play.fill")
                        .font(.app(12, .semibold))
                        .foregroundStyle(Palette.onSilver)
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        .background(Capsule().fill(Palette.silver))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .probe("focus.start")
        }
    }

    @ViewBuilder private var steppers: some View {
        MinuteStepper(label: "Fokus", unit: "mnt", value: $timer.focusMinutes, range: PomodoroTimer.focusRange, step: 5)
        MinuteStepper(label: "Istirahat", unit: "mnt", value: $timer.shortBreakMinutes, range: PomodoroTimer.breakRange, step: 1)
        MinuteStepper(label: "Sesi", unit: "", value: $timer.sessionsTarget, range: PomodoroTimer.sessionsRange, step: 1)
    }
}

/// "Fokus  [−] 25 mnt [+]".
private struct MinuteStepper: View {
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
                    .frame(minWidth: unit.isEmpty ? 22 : 46)
                button("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + step) }
            }
            .background(Capsule().fill(Palette.button))
        }
        .animation(Motion.quick, value: value)
    }

    private func button(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(enabled ? Palette.text2 : Palette.text3)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
