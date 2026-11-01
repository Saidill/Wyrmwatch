import SwiftUI

/// Black shape that grows out of the camera notch: small outward flares at the top corners, rounded bottom.
struct NotchShape: Shape {
    var flare: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, radius) }
        set { flare = newValue.first; radius = newValue.second }
    }

    static func flare(for state: NotchModel.State, virtual: Bool = false) -> CGFloat {
        // The closed virtual notch is a plain pill.
        if virtual, state == .closed { return 0 }
        return state == .closed || state == .live ? 6 : 10
    }

    static func radius(for state: NotchModel.State) -> CGFloat {
        switch state {
        case .closed, .live: return 10
        case .pop: return 22
        case .expanded: return 26
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let f = min(flare, w / 4), r = min(radius, (h - f) / 2, (w - 2 * f) / 2)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: f, y: f), control: CGPoint(x: f, y: 0))
        p.addLine(to: CGPoint(x: f, y: h - r))
        p.addQuadCurve(to: CGPoint(x: f + r, y: h), control: CGPoint(x: f, y: h))
        p.addLine(to: CGPoint(x: w - f - r, y: h))
        p.addQuadCurve(to: CGPoint(x: w - f, y: h - r), control: CGPoint(x: w - f, y: h))
        p.addLine(to: CGPoint(x: w - f, y: f))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - f, y: 0))
        p.closeSubpath()
        return p
    }
}

struct NotchView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var screen: NotchScreen
    @EnvironmentObject var limits: PlanLimitClient
    @EnvironmentObject var usage: UsageTracker
    @ObservedObject private var motion = MotionPreference.shared
    /// Whether the open panel is built: only around being open.
    @State private var mounted = false

    /// Growing states use the opening curve, shrinking ones the closing curve (a plain fade with Reduce Motion).
    private func morph(to state: NotchModel.State) -> Animation {
        Motion.adapt(state == .closed || state == .live ? Motion.close : Motion.open, motion.reduce)
    }

    var body: some View {
        let state = model.state(on: screen.display)
        let size = screen.size(for: state, contentHeight: model.contentHeight)
        let flare = NotchShape.flare(for: state, virtual: screen.isVirtual)
        let shape = NotchShape(flare: flare, radius: NotchShape.radius(for: state))

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(.black)

                ZStack(alignment: .top) {
                    // The full app is only built while open (and briefly at launch, to learn its height): kept hidden,
                    // it still redrew on every session update, which cost a lot of CPU while closed.
                    // The open panel is only built while open: kept hidden, it redrew on every session update
                    // and cost a lot of CPU while closed.
                    if mounted || state == .expanded {
                        ExpandedPanel(notch: screen.notch)
                            // Eases in a beat after the shape starts opening, settling down from slightly smaller.
                            .opacity(state == .expanded ? 1 : 0)
                            .scaleEffect(state == .expanded || motion.reduce ? 1 : 0.94, anchor: .top)
                            .offset(y: state == .expanded || motion.reduce ? 0 : -10)
                            .animation(Motion.adapt(state == .expanded ? Motion.contentIn : Motion.contentOut, motion.reduce),
                                       value: state)
                            .allowsHitTesting(state == .expanded)
                            .environment(\.animationsPaused, state != .expanded || motion.reduce)
                    }

                    if state == .live, let live = model.live {
                        LiveRow(module: live, notch: screen.notch)
                            .transition(.opacity.animation(Motion.liveIn))
                    }
                    if state == .pop, let pop = model.pop {
                        pop.content
                            .padding(.horizontal, 16)
                            .padding(.top, screen.notch.height + 6)
                            .id(pop.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -8)).animation(Motion.contentIn),
                                removal: .opacity.animation(Motion.contentOut)))
                    }
                }
                .padding(.horizontal, flare)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
            }
            .frame(width: size.width, height: size.height)
            .animation(morph(to: state), value: state)
            .animation(morph(to: state), value: size)
            Spacer(minLength: 0)
        }
        .frame(width: NotchWindowController.windowSize.width, height: NotchWindowController.windowSize.height,
               alignment: .top)
        .preferredColorScheme(.dark)
        .followsReduceMotion()
        .onChange(of: state == .expanded) { _, open in
            if open {
                mounted = true
            } else {
                // Keep it while it fades out and the shape closes, then let it go.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if model.state(on: screen.display) != .expanded { mounted = false }
                }
            }
            guard open else { return }
            usage.refresh()
            Task { await limits.refreshIfStale() }
        }
        .onChange(of: model.state, initial: true) { _, state in model.registry.setVisible(state != .closed) }
    }
}

/// The active module either side of the camera: its visual on the left, its number on the right.
/// Switching module swaps the content in place (old one up and out, new one up from below); the width stays.
private struct LiveRow: View {
    let module: any NotchModule
    let notch: CGSize

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                module.liveLeading()
                    .frame(width: 50)
                Spacer(minLength: notch.width)
                module.liveTrailing()
                    .frame(width: 50)
            }
            .overlay(alignment: .bottom) {
                // Inside the rounded bottom corners.
                module.liveAccent()?
                    .frame(width: notch.width + 100 - 24, height: 6)
            }
            .id(module.id)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)),
                                    removal: .opacity.combined(with: .offset(y: -6))))
        }
        .animation(Motion.smooth, value: module.id)
        // Exactly as wide as the live shape, so the two sides sit just either side of the notch.
        .frame(width: notch.width + 100, height: notch.height)
        .clipped()
    }
}

