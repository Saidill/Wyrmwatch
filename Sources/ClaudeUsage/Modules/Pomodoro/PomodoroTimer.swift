import AppKit
import Combine

/// The Pomodoro clock. It keeps an end date rather than counting down, so it stays right through sleep,
/// and it saves itself to UserDefaults so a restart picks up where it left off.
@MainActor
final class PomodoroTimer: ObservableObject {
    enum Phase: String {
        case focus, shortBreak, longBreak
        var isBreak: Bool { self != .focus }
    }

    enum Event { case focusDone, breakDone }

    /// Ready-made lengths, in minutes.
    struct Preset: Equatable, Identifiable {
        let focus: Int
        let shortBreak: Int
        var id: String { "\(focus)/\(shortBreak)" }
        static let classic = Preset(focus: 25, shortBreak: 5)
        static let long = Preset(focus: 50, shortBreak: 10)
    }

    /// Focus sessions per cycle; the cycle ends with a long break.
    static let sessionsPerCycle = 4

    @Published private(set) var phase: Phase = .focus
    /// When the running phase ends; nil while stopped or paused.
    @Published private(set) var endDate: Date?
    /// Time left in a paused phase.
    @Published private(set) var pausedRemaining: TimeInterval?
    /// Focus sessions finished in the current cycle (the lit ember dots).
    @Published private(set) var completedInCycle = 0
    @Published private(set) var todaySessions = 0
    @Published private(set) var todayMinutes = 0

    @Published var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: Keys.focus) } }
    @Published var shortBreakMinutes: Int { didSet { defaults.set(shortBreakMinutes, forKey: Keys.shortBreak) } }
    @Published var longBreakMinutes: Int { didSet { defaults.set(longBreakMinutes, forKey: Keys.longBreak) } }

    /// Fires when a phase runs out (not when it is skipped).
    let events = PassthroughSubject<Event, Never>()
    /// Fires when a phase starts or resumes.
    let starts = PassthroughSubject<Phase, Never>()

    private let defaults: UserDefaults
    private var timer: Timer?
    private var wakeObserver: Any?

    enum Keys {
        static let focus = "pomodoro.focusMinutes"
        static let shortBreak = "pomodoro.shortBreakMinutes"
        static let longBreak = "pomodoro.longBreakMinutes"
        static let sound = "pomodoro.sound"
        static let haptic = "pomodoro.haptic"
        static let musicSync = "pomodoro.musicSync"
        static let phase = "pomodoro.phase"
        static let endDate = "pomodoro.endDate"
        static let paused = "pomodoro.pausedRemaining"
        static let cycle = "pomodoro.completedInCycle"
        static let statsDay = "pomodoro.statsDay"
        static let statsSessions = "pomodoro.statsSessions"
        static let statsMinutes = "pomodoro.statsMinutes"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.focus: 25, Keys.shortBreak: 5, Keys.longBreak: 15,
                                     Keys.sound: true, Keys.haptic: true, Keys.musicSync: false])
        focusMinutes = defaults.integer(forKey: Keys.focus)
        shortBreakMinutes = defaults.integer(forKey: Keys.shortBreak)
        longBreakMinutes = defaults.integer(forKey: Keys.longBreak)
        restore()
        // A timer can't fire while the Mac sleeps; check the end date as soon as it wakes.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    // MARK: State

    var isRunning: Bool { endDate != nil }
    var isPaused: Bool { pausedRemaining != nil }
    /// Running or paused: the Pomodoro owns the live notch.
    var isActive: Bool { isRunning || isPaused }

    var preset: Preset? {
        [Preset.classic, .long].first { $0.focus == focusMinutes && $0.shortBreak == shortBreakMinutes }
    }

    func duration(of phase: Phase) -> TimeInterval {
        let minutes = switch phase {
        case .focus: focusMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
        return TimeInterval(max(minutes, 1) * 60)
    }

    /// Seconds left in the current phase at `date`.
    func remaining(at date: Date = Date()) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(date)) }
        return pausedRemaining ?? duration(of: phase)
    }

    /// How much of the phase is left, 1 → 0.
    func fractionLeft(at date: Date = Date()) -> Double {
        min(max(remaining(at: date) / duration(of: phase), 0), 1)
    }

    // MARK: Controls

    /// Starts the current phase, or resumes it when paused.
    func start() {
        let left = pausedRemaining ?? duration(of: phase)
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(left)
        save()
        schedule()
        starts.send(phase)
    }

    func pause() {
        guard let endDate else { return }
        pausedRemaining = max(1, endDate.timeIntervalSinceNow)
        self.endDate = nil
        timer?.invalidate()
        save()
    }

    func toggle() { isRunning ? pause() : start() }

    /// Stops and rewinds the current phase.
    func reset() {
        stop()
        save()
    }

    /// Moves straight on to the next phase without counting this one, and leaves it ready to start.
    func skip() {
        stop()
        phase = phase.isBreak ? .focus : (completedInCycle >= Self.sessionsPerCycle ? .longBreak : .shortBreak)
        if phase == .focus, completedInCycle >= Self.sessionsPerCycle { completedInCycle = 0 }
        save()
    }

    func apply(_ preset: Preset) {
        focusMinutes = preset.focus
        shortBreakMinutes = preset.shortBreak
        if !isActive { save() }
    }

    /// Self-test only: puts the clock a few seconds from the end of the phase.
    func runForTesting(phase: Phase, secondsLeft: TimeInterval, paused: Bool = false) {
        stop()
        self.phase = phase
        if paused { pausedRemaining = secondsLeft } else { endDate = Date().addingTimeInterval(secondsLeft); schedule() }
        save()
    }

    // MARK: Ending a phase

    private func stop() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        pausedRemaining = nil
    }

    private func schedule() {
        timer?.invalidate()
        guard let endDate else { return }
        // One timer at the end, not one a second: the digits redraw themselves on their own schedule.
        let timer = Timer(fire: endDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Finishes the phase if its end date has passed.
    private func check() {
        guard let endDate, endDate <= Date() else {
            schedule()
            return
        }
        finish()
    }

    private func finish() {
        let finished = phase
        stop()
        rollDay()
        if finished == .focus {
            todaySessions += 1
            todayMinutes += Int((duration(of: .focus) / 60).rounded())
            completedInCycle = min(completedInCycle + 1, Self.sessionsPerCycle)
            phase = completedInCycle >= Self.sessionsPerCycle ? .longBreak : .shortBreak
        } else {
            if finished == .longBreak { completedInCycle = 0 }
            phase = .focus
        }
        save()
        events.send(finished == .focus ? .focusDone : .breakDone)
    }

    /// Starts today's stats afresh on a new day.
    private func rollDay() {
        let today = Self.dayKey(Date())
        if defaults.string(forKey: Keys.statsDay) != today {
            defaults.set(today, forKey: Keys.statsDay)
            todaySessions = 0
            todayMinutes = 0
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: Saving

    private func save() {
        defaults.set(phase.rawValue, forKey: Keys.phase)
        defaults.set(endDate?.timeIntervalSince1970, forKey: Keys.endDate)
        defaults.set(pausedRemaining, forKey: Keys.paused)
        defaults.set(completedInCycle, forKey: Keys.cycle)
        defaults.set(todaySessions, forKey: Keys.statsSessions)
        defaults.set(todayMinutes, forKey: Keys.statsMinutes)
        if defaults.string(forKey: Keys.statsDay) == nil { defaults.set(Self.dayKey(Date()), forKey: Keys.statsDay) }
    }

    /// Picks up the saved clock. A phase that ended while the app was closed is finished now.
    func restore() {
        timer?.invalidate()
        phase = defaults.string(forKey: Keys.phase).flatMap(Phase.init) ?? .focus
        completedInCycle = defaults.integer(forKey: Keys.cycle)
        let end = defaults.object(forKey: Keys.endDate) as? Double
        endDate = end.map(Date.init(timeIntervalSince1970:))
        pausedRemaining = defaults.object(forKey: Keys.paused) as? Double
        if defaults.string(forKey: Keys.statsDay) == Self.dayKey(Date()) {
            todaySessions = defaults.integer(forKey: Keys.statsSessions)
            todayMinutes = defaults.integer(forKey: Keys.statsMinutes)
        } else {
            todaySessions = 0
            todayMinutes = 0
        }
        if endDate != nil { check() }
    }
}
