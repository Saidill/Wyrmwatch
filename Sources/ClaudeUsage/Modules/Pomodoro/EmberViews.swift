import SwiftUI

/// Colour of the Pomodoro's fire: amber while focusing, cold silver-blue while resting.
func emberColor(_ phase: PomodoroTimer.Phase) -> Color {
    phase.isBreak ? Palette.frost : Palette.amber
}

/// Time left as "24:59". Changes once a second, rolling digits; in the last 10 seconds it turns bright
/// and swells a touch on each tick. Nothing redraws while paused.
struct PomodoroDigits: View {
    @ObservedObject var timer: PomodoroTimer
    var size: CGFloat = 11
    var color: Color = Palette.text2
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
        return Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
            .font(.app(size, .medium))
            .monospacedDigit()
            .foregroundStyle(final ? Palette.text : color)
            .contentTransition(.numericText(countsDown: true))
            .animation(Motion.smooth, value: seconds)
            .keyframeAnimator(initialValue: 1.0, trigger: final && !reduceMotion ? seconds : 0) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                CubicKeyframe(1.06, duration: 0.15)
                CubicKeyframe(1.0, duration: 0.3)
            }
    }
}

/// A glowing ember. It flickers gently (opacity 0.75–1 over 2 s) unless still.
struct Ember: View {
    var color: Color
    var size: CGFloat = 4
    var still = false
    @Environment(\.animationsPaused) private var paused

    var body: some View {
        // A slow 2 s flicker needs no more than 15 fps.
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: paused || still)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let flicker = still ? 1 : 0.875 + 0.125 * sin(t * .pi)
            Canvas { ctx, canvas in
                let r = canvas.width / 2
                let center = CGPoint(x: r, y: r)
                // Soft halo, then a hot core.
                ctx.fill(Path(ellipseIn: CGRect(origin: .zero, size: canvas)),
                         with: .radialGradient(Gradient(colors: [color.opacity(0.55), color.opacity(0)]),
                                               center: center, startRadius: 0, endRadius: r))
                let core = r * 0.45
                ctx.fill(Path(ellipseIn: CGRect(x: r - core, y: r - core, width: core * 2, height: core * 2)),
                         with: .color(.white.opacity(0.9)))
            }
            .opacity(flicker)
        }
        .frame(width: size * 2.5, height: size * 2.5)
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

/// The burning fuse along the bottom of the live notch: drawn out from the centre when the phase starts,
/// then burning down towards the centre from both ends, with an ember at each end.
struct EmberFuse: View {
    @ObservedObject var timer: PomodoroTimer
    @Environment(\.reduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        Group {
            if let end = timer.endDate {
                TimelineView(.periodic(from: end.addingTimeInterval(-100_000), by: 1)) { context in
                    fuse(timer.fractionLeft(at: context.date))
                }
            } else {
                fuse(timer.fractionLeft())
            }
        }
        // Paused: everything dims and stands still.
        .opacity(timer.isPaused ? 0.6 : 1)
        .onAppear { withAnimation(Motion.adapt(Motion.fuse, reduceMotion)) { drawn = true } }
    }

    private func fuse(_ fraction: Double) -> some View {
        GeometryReader { geo in
            let color = emberColor(timer.phase)
            let length = max(geo.size.width * fraction * (drawn ? 1 : 0), 0)
            ZStack {
                Capsule()
                    .fill(color)
                    .frame(width: length, height: 1.5)
                HStack(spacing: 0) {
                    Ember(color: color, size: 2.5, still: timer.isPaused)
                    Spacer(minLength: 0)
                    Ember(color: color, size: 2.5, still: timer.isPaused)
                }
                .frame(width: length + 6)
                .opacity(drawn ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(Motion.smooth, value: timer.phase)
        }
    }
}

/// Large progress ring for the expanded card, with an ember riding the tip of the arc.
struct EmberRing: View {
    @ObservedObject var timer: PomodoroTimer
    var size: CGFloat = 60

    var body: some View {
        Group {
            if let end = timer.endDate {
                TimelineView(.periodic(from: end.addingTimeInterval(-100_000), by: 1)) { context in
                    ring(timer.fractionLeft(at: context.date))
                }
            } else {
                ring(timer.fractionLeft())
            }
        }
        .frame(width: size, height: size)
    }

    private func ring(_ fraction: Double) -> some View {
        let color = emberColor(timer.phase)
        let line: CGFloat = 4
        return ZStack {
            Circle().stroke(Palette.line, lineWidth: line)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if timer.isActive {
                Ember(color: color, size: 3.5, still: timer.isPaused)
                    .offset(y: -size / 2)
                    .rotationEffect(.degrees(360 * fraction))
            }
            PomodoroDigits(timer: timer, size: 13, color: Palette.text)
        }
        .opacity(timer.isPaused ? 0.6 : 1)
        .animation(Motion.smooth, value: fraction)
        .animation(Motion.smooth, value: timer.phase)
    }
}

/// Four ember dots: how many focus sessions of this cycle are done. The newest one pops in when lit.
struct EmberDots: View {
    let lit: Int
    var size: CGFloat = 6

    var body: some View {
        HStack(spacing: size * 0.9) {
            ForEach(0..<PomodoroTimer.sessionsPerCycle, id: \.self) { i in
                Circle()
                    .fill(i < lit ? Palette.amber : Palette.line)
                    .frame(width: size, height: size)
                    .scaleEffect(i < lit ? 1 : 0.8)
                    .animation(Motion.popIn, value: lit)
            }
        }
    }
}
