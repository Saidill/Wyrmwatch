import AppKit
import SwiftUI

/// The Focus page. Left: the time card (task, time, controls) and today's tasks. Right: the mode
/// (Pomodoro | Timer), the task field with recent names, and the presets of the chosen mode.
struct FocusPage: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var log = TaskLog.shared
    /// The mode shown in the setup, kept between openings.
    @AppStorage("focus.pageMode") private var mode: PomodoroTimer.Mode = .pomodoro
    @State private var custom = false
    /// The Timer's chosen length, kept between launches.
    @AppStorage("timer.seconds") private var timerSeconds = 600

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 8) {
                timeCard
                    .frame(height: 120)
                    .probe("focus.time")
                TodayCard(log: log)
                    .probe("focus.today")
            }
            .frame(width: 200)
            .cardAppear(0)
            VStack(alignment: .leading, spacing: 8) {
                ModeSwitch(selection: $mode)
                    .probe("focus.mode")
                if !timer.isActive {
                    TaskField(task: $timer.task, recent: log.recent, onSubmit: startChosen)
                        .probe("focus.task")
                }
                if mode == .pomodoro { pomodoroPresets } else { timerPresets }
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
            HStack(spacing: 4) {
                Text(caption).cardLabel().fixedSize()
                if timer.isActive && (timer.mode == .countdown || timer.phase == .focus) {
                    InlineTaskName(task: $timer.task)
                }
            }
            Spacer(minLength: 4)
            PomodoroDigits(timer: timer, size: 38, weight: .semibold, color: Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(timer.isPaused ? 0.6 : 1)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                if timer.isActive {
                    CardButton(systemName: timer.isPaused ? "play.fill" : "pause.fill", active: true, height: 28,
                               help: timer.isPaused ? "Resume" : "Pause") { timer.toggle() }
                    CardButton(title: "+1", height: 28, help: "One more minute") { timer.addMinutes(1) }
                    CardButton(title: "+5", height: 28, help: "Five more minutes") { timer.addMinutes(5) }
                    CardButton(systemName: "stop.fill", height: 28, help: "Stop") { timer.stopToSetup() }
                } else {
                    CardButton(systemName: "play.fill", title: "Start", active: true, height: 28) { startChosen() }
                }
            }
        }
        .notchCard(active: timer.isRunning)
    }

    private var caption: String {
        if timer.isActive {
            let head = if timer.mode == .countdown { "Timer" } else {
                switch timer.phase {
                case .focus: "Focus \(timer.sessionNumber)/\(timer.sessionsTarget)"
                case .shortBreak: "Break"
                case .longBreak: "Long break"
                }
            }
            return head + (timer.isPaused ? " · paused" : "") + (timer.mode == .countdown || timer.phase == .focus ? " ·" : "")
        }
        return mode == .pomodoro ? "Focus \(timer.focusMinutes)/\(timer.shortBreakMinutes)" : "Timer"
    }

    private func startChosen() {
        if mode == .countdown { timer.startCountdown(seconds: timerSeconds) } else { timer.start() }
    }

    // MARK: Pomodoro

    private var pomodoroPresets: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                PresetButton(title: "25/5", selected: running(.classic)) { timer.startPomodoro(.classic) }
                PresetButton(title: "50/10", selected: running(.long)) { timer.startPomodoro(.long) }
                PresetButton(title: "90/15", selected: running(.extended)) { timer.startPomodoro(.extended) }
                PresetButton(title: "Custom", selected: custom) { withAnimation(Motion.resize) { custom.toggle() } }
            }
            .probe("focus.presets")
            if custom {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        MinuteStepper(label: "Focus", unit: "min", value: $timer.focusMinutes, range: PomodoroTimer.focusRange, step: 5)
                        MinuteStepper(label: "Break", unit: "min", value: $timer.shortBreakMinutes, range: PomodoroTimer.breakRange, step: 1)
                    }
                    HStack(spacing: 8) {
                        MinuteStepper(label: "Long", unit: "min", value: $timer.longBreakMinutes, range: PomodoroTimer.longBreakRange, step: 5)
                        MinuteStepper(label: "Sessions", unit: "", value: $timer.sessionsTarget, range: PomodoroTimer.sessionsRange, step: 1)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: -4)))
                .probe("focus.custom")
            }
        }
    }

    private func running(_ preset: PomodoroTimer.Preset) -> Bool {
        timer.isActive && timer.mode == .pomodoro && timer.preset == preset
    }

    // MARK: Timer

    private var timerPresets: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach([5, 10, 15, 30], id: \.self) { minutes in
                    PresetButton(title: "\(minutes) min", selected: runningTimer(minutes * 60)) {
                        timerSeconds = minutes * 60
                        timer.startCountdown(seconds: timerSeconds)
                    }
                }
            }
            .probe("focus.presets")
            HStack(spacing: 8) {
                DurationField(seconds: $timerSeconds)
                    .probe("focus.duration")
                Spacer(minLength: 0)
            }
        }
    }

    private func runningTimer(_ seconds: Int) -> Bool {
        timer.isActive && timer.mode == .countdown && Int(timer.phaseLength.rounded()) == seconds
    }
}

// MARK: - Task name

/// "What are you working on?" with the last five names as chips underneath.
private struct TaskField: View {
    @Binding var task: String
    let recent: [String]
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("What are you working on?", text: $task)
                .textFieldStyle(.plain)
                .font(.app(13))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Radius.shape(Radius.button).fill(Palette.button))
                .onSubmit(onSubmit)
            if !recent.isEmpty {
                HStack(spacing: 4) {
                    ForEach(recent, id: \.self) { name in
                        TaskChip(name: name, selected: name == task) { task = name }
                    }
                }
                .probe("focus.recent")
            }
        }
    }
}

private struct TaskChip: View {
    let name: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.app(11))
                .foregroundStyle(selected ? Palette.text : Palette.text2)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(selected || hovering ? Palette.buttonHi : Palette.card))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
    }
}

/// The running task's name; click it to rename it in place.
private struct InlineTaskName: View {
    @Binding var task: String
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            TextField("Task", text: $draft)
                .textFieldStyle(.plain)
                .font(.app(11))
                .foregroundStyle(Palette.text)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, now in if !now { commit() } }
                .onAppear { focused = true }
        } else {
            Text(task.isEmpty ? "Name this task" : task)
                .font(.app(11))
                .foregroundStyle(task.isEmpty ? Palette.text3 : Palette.text2)
                .lineLimit(1)
                .truncationMode(.tail)
                .contentShape(Rectangle())
                .onTapGesture {
                    draft = task
                    editing = true
                }
                .help("Rename this task")
        }
    }

    private func commit() {
        guard editing else { return }
        task = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        TaskLog.shared.use(task)
        editing = false
    }
}

// MARK: - Today

/// What was worked on today: each task with its minutes, longest first.
private struct TodayCard: View {
    @ObservedObject var log: TaskLog

    var body: some View {
        let rows = log.today
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Today").cardLabel()
                Spacer(minLength: 4)
                Text(Self.minutes(rows.reduce(0) { $0 + $1.minutes }))
                    .font(.app(11))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text2)
            }
            if rows.isEmpty {
                Text("Nothing yet")
                    .font(.app(13))
                    .foregroundStyle(Palette.text3)
            } else {
                ForEach(rows.prefix(4), id: \.task) { row in
                    HStack(spacing: 8) {
                        Text(row.task)
                            .font(.app(13))
                            .foregroundStyle(row.task == TaskLog.untitled ? Palette.text2 : Palette.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Text(Self.minutes(row.minutes))
                            .font(.app(13))
                            .monospacedDigit()
                            .foregroundStyle(Palette.text2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchCard()
    }

    static func minutes(_ total: Int) -> String {
        total >= 60 ? "\(total / 60)h \(total % 60)m" : "\(total)m"
    }
}

// MARK: - Controls

/// Pomodoro | Timer.
private struct ModeSwitch: View {
    @Binding var selection: PomodoroTimer.Mode
    @Namespace private var glide

    var body: some View {
        HStack(spacing: 0) {
            ForEach([PomodoroTimer.Mode.pomodoro, .countdown], id: \.self) { mode in
                Button { withAnimation(Motion.quick) { selection = mode } } label: {
                    Text(mode == .pomodoro ? "Pomodoro" : "Timer")
                        .font(.app(13, selection == mode ? .semibold : .regular))
                        .foregroundStyle(selection == mode ? Palette.text : Palette.text2)
                        .frame(maxWidth: .infinity, minHeight: 24)
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

/// A free length as h : m : s. Type in a field, or scroll over it to change it.
private struct DurationField: View {
    @Binding var seconds: Int

    var body: some View {
        HStack(spacing: 0) {
            DurationPart(value: part(3600, 24), range: 0...23) { set(hours: $0) }
            colon
            DurationPart(value: part(60, 60), range: 0...59) { set(minutes: $0) }
            colon
            DurationPart(value: part(1, 60), range: 0...59) { set(seconds: $0) }
        }
        .padding(.horizontal, 4)
        .frame(height: 28)
        .background(Radius.shape(Radius.button).fill(Palette.button))
        .help("Type a length, or scroll over a number")
    }

    private var colon: some View {
        Text(":").font(.app(13, .semibold)).foregroundStyle(Palette.text3)
    }

    private func part(_ unit: Int, _ modulo: Int) -> Int { seconds / unit % modulo }

    private func set(hours: Int? = nil, minutes: Int? = nil, seconds s: Int? = nil) {
        let h = hours ?? part(3600, 24), m = minutes ?? part(60, 60), sec = s ?? part(1, 60)
        seconds = max(1, h * 3600 + m * 60 + sec)
    }
}

/// One number of the duration: shows "05"; scrolling steps it, clicking types it.
private struct DurationPart: View {
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, now in if !now { commit() } }
                    .onAppear { focused = true }
            } else {
                Text(String(format: "%02d", value))
                    .contentTransition(.numericText())
                    .animation(Motion.quick, value: value)
                    .overlay(ScrollCatcher(onStep: step, onClick: begin))
            }
        }
        .font(.app(13, .semibold))
        .monospacedDigit()
        .foregroundStyle(Palette.text)
        .frame(width: 28)
    }

    private func step(_ delta: Int) {
        onChange(min(range.upperBound, max(range.lowerBound, value + delta)))
    }

    private func begin() {
        draft = String(value)
        editing = true
    }

    private func commit() {
        guard editing else { return }
        if let typed = Int(draft.filter(\.isNumber)) { onChange(min(range.upperBound, max(range.lowerBound, typed))) }
        editing = false
    }
}

/// Turns scroll-wheel movement over a view into ±1 steps (scrolling up adds), and a click into `onClick`.
private struct ScrollCatcher: NSViewRepresentable {
    let onStep: (Int) -> Void
    let onClick: () -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onStep = onStep
        view.onClick = onClick
    }

    final class CatcherView: NSView {
        var onStep: (Int) -> Void = { _ in }
        var onClick: () -> Void = {}
        private var pending: CGFloat = 0

        override func scrollWheel(with event: NSEvent) {
            // Trackpads send many small deltas; a step every 6 points feels like one notch of a wheel.
            pending += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 6 : event.scrollingDeltaY
            let steps = Int(pending)
            guard steps != 0 else { return }
            pending -= CGFloat(steps)
            onStep(event.isDirectionInvertedFromDevice ? -steps : steps)
        }

        override func mouseDown(with event: NSEvent) { onClick() }
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
        HStack(spacing: 4) {
            Text(label)
                .font(.app(11))
                .foregroundStyle(Palette.text2)
                .frame(width: 48, alignment: .leading)
            HStack(spacing: 0) {
                button("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - step) }
                Text(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
                    .font(.app(13))
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minWidth: unit.isEmpty ? 20 : 48)
                button("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + step) }
            }
            .background(Radius.shape(Radius.button).fill(Palette.button))
        }
        .animation(Motion.quick, value: value)
    }

    private func button(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Palette.text2 : Palette.text3)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
    }
}
