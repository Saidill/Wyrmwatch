import SwiftUI

/// Home: one row, 96 pt tall. [cover 96 | player (flex) | 1 pt line | Focus and Claude (180)], 16 pt apart.
struct HomePage: View {
    @ObservedObject var bridge: MusicBridge
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var limits: PlanLimitClient
    var coverSpace: Namespace.ID?
    @AppStorage(NotchTab.storageKey) private var tab: NotchTab = .home

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            HomeCover(bridge: bridge, coverSpace: coverSpace)
                .frame(width: 96, height: 96)
                .probe("home.cover")
            Group {
                if bridge.track != nil {
                    player
                } else {
                    startMusic
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(Palette.line)
                .frame(width: 1)
                .probe("home.divider")
            side
                .frame(width: 180)
        }
        .frame(height: 96)
    }

    // MARK: Player

    private var player: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bridge.track?.title ?? "")
                        .font(.app(13.5, .semibold))
                        .foregroundStyle(Palette.text)
                    Text(bridge.track?.artist ?? "")
                        .font(.app(11.5))
                        .foregroundStyle(Palette.text2)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .probe("home.title")
                MusicVisualizer(playing: bridge.isPlaying, color: Palette.silver)
                    .padding(.top, 3)
                    .probe("home.visualizer")
            }
            .frame(height: 34, alignment: .top)
            Spacer(minLength: 0)
            SeekRow(bridge: bridge, probePrefix: "home.seek.")
                .frame(height: 14)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                GlyphButton(systemName: "list.bullet", help: "Playlist") { withAnimation(Motion.resize) { tab = .music } }
                    .probe("home.btn1")
                GlyphButton(systemName: "backward.fill", help: "Previous") { bridge.previous() }
                    .probe("home.btn2")
                GlyphButton(systemName: bridge.isPlaying ? "pause.fill" : "play.fill", size: 16, active: true,
                            help: bridge.isPlaying ? "Pause" : "Play") { bridge.playPause() }
                    .probe("home.btn3")
                GlyphButton(systemName: "forward.fill", help: "Next") { bridge.next() }
                    .probe("home.btn4")
                GlyphButton(systemName: bridge.favorite ? "heart.fill" : "heart", active: bridge.favorite,
                            help: "Favourite") { bridge.toggleFavorite() }
                    .probe("home.btn5")
            }
            .frame(height: 28)
        }
    }

    private var startMusic: some View {
        Button { bridge.startMusic() } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill").font(.system(size: 12, weight: .semibold))
                Text("Putar musik").font(.app(12.5, .medium)).lineLimit(1)
            }
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Capsule().fill(Palette.button))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .probe("home.startMusic")
    }

    // MARK: Focus and Claude

    private var side: some View {
        VStack(alignment: .leading, spacing: 0) {
            FocusMini(timer: timer) { withAnimation(Motion.resize) { tab = .focus } }
                .frame(height: 58)
            Spacer(minLength: 0)
            claude
        }
    }

    private var claude: some View {
        let percent = limits.fiveHourPercent
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Claude · sesi")
                    .font(.app(11))
                    .foregroundStyle(Palette.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .probe("home.claude.label")
                Spacer(minLength: 4)
                Text(percent.map { "\(Int($0.rounded()))%" } ?? "–")
                    .font(.app(11, .medium))
                    .foregroundStyle(Palette.level(percent ?? 0, base: Palette.text, warn: 80))
                    .monospacedDigit()
                    .fixedSize()
                    .probe("home.claude.percent")
            }
            ThinBar(fraction: (percent ?? 0) / 100, color: Palette.level(percent ?? 0, base: Palette.silver, warn: 80))
                .probe("home.claude.bar")
        }
    }
}

/// The Pomodoro in one 58 pt row: "Fokus n/N" and the time with pause and stop while running;
/// 25/5, 50/10 (start at once) and Atur (the full setup) while stopped. Used on Home and in the popover.
struct FocusMini: View {
    @ObservedObject var timer: PomodoroTimer
    let openSetup: () -> Void

    var body: some View {
        if timer.isActive { running } else { chips }
    }

    private var running: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(timer.phase == .focus ? "Fokus \(timer.sessionNumber)/\(timer.sessionsTarget)" : "Istirahat")
                    .font(.app(11))
                    .foregroundStyle(Palette.text2)
                    .lineLimit(1)
                    .probe("home.focus.label")
                PomodoroDigits(timer: timer, size: 28, weight: .regular, color: Palette.silverBright)
                    .lineLimit(1)
                    .fixedSize()
                    .probe("home.focus.time")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RoundButton(systemName: timer.isPaused ? "play.fill" : "pause.fill", help: timer.isPaused ? "Lanjut" : "Pause") {
                timer.toggle()
            }
            .probe("home.focus.pause")
            RoundButton(systemName: "xmark", help: "Stop") { timer.stopToSetup() }
                .probe("home.focus.close")
        }
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fokus")
                .font(.app(11))
                .foregroundStyle(Palette.text2)
                .probe("home.focus.label")
            HStack(spacing: 6) {
                NotchChip(title: "25/5") { timer.apply(.classic); timer.start() }
                    .probe("home.chip1")
                NotchChip(title: "50/10") { timer.apply(.long); timer.start() }
                    .probe("home.chip2")
                NotchChip(title: "Atur", action: openSetup)
                    .probe("home.chip3")
            }
        }
    }
}

/// The cover with a soft glow made of itself, blurred, behind it. Shares its identity with the live notch's
/// cover so it flies between them.
struct HomeCover: View {
    @ObservedObject var bridge: MusicBridge
    var coverSpace: Namespace.ID?

    var body: some View {
        ZStack {
            if let image = bridge.artwork {
                // Static glow: the image blurred once, never animated.
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 96, height: 96)
                    // Rounded before blurring, so the glow has no square corners.
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .scaleEffect(1.06)
                    .offset(y: 4)
                    .blur(radius: 16)
                    .opacity(0.6)
                    .allowsHitTesting(false)
            }
            CoverArt(image: bridge.artwork, id: bridge.track?.id ?? "", size: 96, radius: 16)
                .modifier(MatchedCover(space: coverSpace))
        }
    }
}

/// `matchedGeometryEffect` for the album cover, when a namespace is given.
struct MatchedCover: ViewModifier {
    let space: Namespace.ID?

    func body(content: Content) -> some View {
        if let space {
            content.matchedGeometryEffect(id: "cover", in: space)
        } else {
            content
        }
    }
}
