import SwiftUI

/// The Focus page. Set up while nothing runs (presets, lengths, sessions, an optional task, Start);
/// once running, big digits, the session count and task, the blue fuse across the page, and controls.
struct FocusPage: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        ZStack {
            if timer.isActive {
                FocusRunning(timer: timer)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            } else {
                FocusSetup(timer: timer)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Motion.smooth, value: timer.isActive)
    }
}

// MARK: - Setup

private struct FocusSetup: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                PresetChip(title: "Klasik 25/5", selected: timer.preset == .classic) { timer.apply(.classic) }
                PresetChip(title: "Dalam 50/10", selected: timer.preset == .long) { timer.apply(.long) }
                PresetChip(title: "Custom", selected: timer.preset == nil) {}
                Spacer(minLength: 0)
            }
            // In a row across the notch; stacked in the narrower menu bar popover.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { steppers; Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 8) { steppers }
            }
            HStack(spacing: 10) {
                TextField("Tugas (opsional)", text: $timer.task)
                    .textFieldStyle(.plain)
                    .font(.app(12))
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.glass))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.rim, lineWidth: 1))
                    .onSubmit { timer.start() }
                Button { timer.start() } label: {
                    Label("Mulai", systemImage: "play.fill")
                        .font(.app(12, .semibold))
                        .foregroundStyle(Palette.onSilver)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Palette.silver))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension FocusSetup {
    @ViewBuilder fileprivate var steppers: some View {
        MinuteStepper(label: "Fokus", unit: "mnt", value: $timer.focusMinutes, range: PomodoroTimer.focusRange, step: 5)
        MinuteStepper(label: "Istirahat", unit: "mnt", value: $timer.shortBreakMinutes, range: PomodoroTimer.breakRange, step: 1)
        MinuteStepper(label: "Sesi", unit: "", value: $timer.sessionsTarget, range: PomodoroTimer.sessionsRange, step: 1)
    }
}

private struct PresetChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Text(title)
            .font(.app(11, .medium))
            .foregroundStyle(selected ? Palette.onSilver : Palette.text2)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(selected ? Palette.silver.opacity(0.85) : Palette.glass))
            .overlay(Capsule().strokeBorder(Palette.rim, lineWidth: selected ? 0 : 1))
            .contentShape(Capsule())
            .onTapGesture { withAnimation(Motion.smooth, action) }
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
                .foregroundStyle(Palette.text3)
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
            .background(Capsule().fill(Palette.glass))
            .overlay(Capsule().strokeBorder(Palette.rim, lineWidth: 1))
        }
        .animation(Motion.quick, value: value)
    }

    private func button(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(enabled ? Palette.text2 : Palette.text3.opacity(0.5))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Running

private struct FocusRunning: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    readout
                    Spacer(minLength: 8)
                    buttons
                }
                VStack(alignment: .leading, spacing: 10) {
                    readout
                    buttons
                }
            }
            Spacer(minLength: 0)
            EmberFuse(timer: timer, anchor: .leading, thickness: 3)
                .frame(height: 12)
        }
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 4) {
            PomodoroDigits(timer: timer, size: 44, weight: .light, color: Palette.text)
                .opacity(timer.isPaused ? 0.6 : 1)
            Text(subtitle)
                .font(.app(12))
                .foregroundStyle(Palette.text2)
                .lineLimit(1)
            EmberDots(lit: timer.completedInCycle, total: timer.sessionsTarget)
        }
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            RunButton(title: "+5 mnt", symbol: "plus") { timer.addFiveMinutes() }
            RunButton(title: timer.isPaused ? "Lanjut" : "Pause",
                      symbol: timer.isPaused ? "play.fill" : "pause.fill", primary: true) { timer.toggle() }
            RunButton(title: "Lewati", symbol: "forward.end.fill") { timer.skip() }
            RunButton(title: "Stop", symbol: "stop.fill") { timer.stopToSetup() }
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

private struct RunButton: View {
    let title: String
    let symbol: String
    var primary = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).font(.app(9.5, .medium)).lineLimit(1)
            }
            .foregroundStyle(primary ? Palette.onSilver : (hovering ? Palette.text : Palette.text2))
            .frame(width: 56, height: 46)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(primary ? Palette.silver : (hovering ? Palette.hover : Palette.glass)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.rim, lineWidth: primary ? 0 : 1))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
    }
}
