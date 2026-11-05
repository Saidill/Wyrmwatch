import SwiftUI

/// Colour of the Pomodoro's fire: the dragon's blue flame while focusing, a paler cyan while resting.
func emberColor(_ phase: PomodoroTimer.Phase) -> Color {
    phase.isBreak ? Palette.silverBright : Palette.silver
}

/// Time left as "24:59". Changes once a second, rolling digits; in the last 10 seconds it turns bright
/// and swells a touch on each tick. Nothing redraws while paused.
struct PomodoroDigits: View {
    /// "4:05", or "1:04:05" from an hour up.
    static func format(_ seconds: Int) -> String {
        seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @ObservedObject var timer: PomodoroTimer
    var size: CGFloat = 11
    var weight: Font.Weight = .regular
    var color: Color = Palette.text2
    /// Roll the digits on each tick (off in the live notch, where it's too small to see and costs a redraw).
    var rolling = true
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        if let end = timer.endDate {
            // Ticks line up with the end date, so the digits change exactly on each second.
            TimelineView(.periodic(from: end.addingTimeInterval(-100_000), by: 1)) { context in
                label(timer.remaining(at: context.date))
            }
        } else {
            label(timer.remaining())
        }
    }

    private func label(_ remaining: TimeInterval) -> some View {
        let seconds = Int(remaining.rounded(.up))
        let final = timer.isRunning && seconds <= 10
        return Text(Self.format(seconds))
            .font(.app(size, weight))
            .monospacedDigit()
            .foregroundStyle(final ? Palette.text : color)
            .contentTransition(rolling ? .numericText(countsDown: true) : .identity)
            .animation(rolling ? Motion.smooth : nil, value: seconds)
            .keyframeAnimator(initialValue: 1.0, trigger: final && rolling && !reduceMotion ? seconds : 0) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                CubicKeyframe(1.06, duration: 0.15)
                CubicKeyframe(1.0, duration: 0.3)
            }
    }
}

/// A small ring that empties as the phase runs (the live notch). Moves once a second; still while paused.
struct PhaseRing: View {
    @ObservedObject var timer: PomodoroTimer
    var diameter: CGFloat = 11
    /// Drawn for this moment by a parent's timeline, instead of running a timeline of its own.
    var at: Date?

    var body: some View {
        Group {
            if let at {
                ring(timer.fractionLeft(at: at))
            } else if let end = timer.endDate {
                TimelineView(.periodic(from: end.addingTimeInterval(-100_000), by: 1)) { context in
                    ring(timer.fractionLeft(at: context.date))
                }
            } else {
                ring(timer.fractionLeft())
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func ring(_ left: Double) -> some View {
        ZStack {
            Circle().stroke(Palette.track, lineWidth: 1.6)
            Circle()
                .trim(from: 0, to: left)
                .stroke(Palette.silver, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .opacity(timer.isPaused ? 0.6 : 1)
    }
}

/// The Focus page's progress: a row of fine ticks like a watch dial. Ticks already passed are silver,
/// the one being worked through is brighter and taller, the rest wait on the track colour.
/// Drawn in one Canvas, once a second.
struct TickScale: View {
    @ObservedObject var timer: PomodoroTimer
    var ticks = 60

    var body: some View {
        Group {
            if let end = timer.endDate {
                TimelineView(.periodic(from: end.addingTimeInterval(-100_000), by: 1)) { context in
                    scale(1 - timer.fractionLeft(at: context.date))
                }
            } else {
                scale(1 - timer.fractionLeft())
            }
        }
        .frame(height: 16)
        .opacity(timer.isPaused ? 0.6 : 1)
    }

    private func scale(_ done: Double) -> some View {
        Canvas { ctx, size in
            let step = size.width / CGFloat(ticks)
            let current = min(Int(done * Double(ticks)), ticks - 1)
            for i in 0..<ticks {
                // Every fifth tick is a little taller, like the hour marks on a dial.
                let major = i % 5 == 0
                let isCurrent = i == current
                let h: CGFloat = isCurrent ? size.height : (major ? size.height * 0.7 : size.height * 0.45)
                let x = step * (CGFloat(i) + 0.5) - 0.75
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: 1.5, height: h)
                let color: Color = isCurrent ? Palette.silverBright : (i < current ? Palette.silver : Palette.track)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 0.75), with: .color(color))
            }
        }
    }
}

/// One ember dot per focus session of the cycle; lit ones are done. The newest one pops in when lit.
struct EmberDots: View {
    let lit: Int
    var total: Int = 4
    var size: CGFloat = 6

    var body: some View {
        HStack(spacing: size * 0.9) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Circle()
                    .fill(i < lit ? Palette.silver : Palette.line)
                    .frame(width: size, height: size)
                    .scaleEffect(i < lit ? 1 : 0.8)
                    .animation(Motion.popIn, value: lit)
            }
        }
    }
}
