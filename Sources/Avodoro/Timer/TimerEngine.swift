import Foundation
import Observation

/// The session state machine. Views only read its state and call its methods.
///
/// It never counts ticks: a running session stores its `endDate`, and the clock calls back
/// once when time is up.
@MainActor
@Observable
final class TimerEngine {
    enum Phase: Equatable, Sendable {
        case idle, running, paused, finishing
    }

    struct Configuration: Equatable, Sendable {
        var discardThreshold: TimeInterval = 60
        var defaultBreakMinutes = 5
        var askEnergy = true
        var pauseOnScreenLock = true
    }

    static let energyTimeout: TimeInterval = 120
    static let defaultFocusMinutes = 15

    var configuration: Configuration
    private(set) var session: Session?
    private(set) var finishing: FinishingSession?
    private(set) var selectedType: SessionType = .focus
    private(set) var selectedMinutes = TimerEngine.defaultFocusMinutes
    /// Editable while a session runs; the logged description is the text when the session finishes.
    var taskText = ""

    /// Called when time is up, for sound, notification and the completion animation.
    @ObservationIgnored var onComplete: (@MainActor (SessionType) -> Void)?

    @ObservationIgnored private let clock: any Clock
    @ObservationIgnored private let timeZone: () -> TimeZone
    @ObservationIgnored private let log: @MainActor (LogDay, LogEntry) -> Void
    @ObservationIgnored private var timeUpAction: (any ScheduledAction)?
    @ObservationIgnored private var energyTimeoutAction: (any ScheduledAction)?
    @ObservationIgnored private var lastFocusMinutes = TimerEngine.defaultFocusMinutes
    @ObservationIgnored private var lastFocusText = ""

    init(
        clock: any Clock,
        configuration: Configuration = Configuration(),
        timeZone: @escaping () -> TimeZone = { .current },
        log: @escaping @MainActor (LogDay, LogEntry) -> Void
    ) {
        self.clock = clock
        self.configuration = configuration
        self.timeZone = timeZone
        self.log = log
    }

    var now: Date { clock.now }

    var phase: Phase {
        if finishing != nil { return .finishing }
        switch session?.state {
        case .running: return .running
        case .paused: return .paused
        case nil: return .idle
        }
    }

    // MARK: Display

    func remaining(at now: Date) -> TimeInterval {
        if let session { return session.remaining(at: now) }
        if finishing != nil { return 0 }
        return TimeInterval(selectedMinutes * 60)
    }

    /// 0 at the start, 1 when time is up.
    func progress(at now: Date) -> Double {
        if let session { return 1 - session.remaining(at: now) / session.plannedSeconds }
        return finishing != nil ? 1 : 0
    }

    // MARK: Idle

    func select(type: SessionType) {
        guard phase == .idle else { return }
        selectedType = type
        selectedMinutes = type == .focus ? lastFocusMinutes : configuration.defaultBreakMinutes
    }

    func select(minutes: Int) {
        guard phase == .idle else { return }
        selectedMinutes = minutes
    }

    // MARK: Running

    func start() {
        switch phase {
        case .running, .paused: return
        case .finishing: commitFinishing(energy: nil)
        case .idle: break
        }
        let now = clock.now
        let endDate = now.addingTimeInterval(TimeInterval(selectedMinutes * 60))
        session = Session(
            type: selectedType,
            plannedMinutes: selectedMinutes,
            startDate: now,
            timeZone: timeZone().identifier,
            state: .running(endDate: endDate)
        )
        scheduleTimeUp(at: endDate)
    }

    func pause() {
        guard var session, case .running(let endDate) = session.state else { return }
        let now = clock.now
        session.state = .paused(remaining: max(0, endDate.timeIntervalSince(now)), since: now)
        self.session = session
        cancelTimeUp()
    }

    func resume() {
        guard var session, case .paused(let remaining, let since) = session.state else { return }
        let now = clock.now
        let endDate = now.addingTimeInterval(remaining)
        session.pausedSeconds += now.timeIntervalSince(since)
        session.state = .running(endDate: endDate)
        self.session = session
        scheduleTimeUp(at: endDate)
    }

    func togglePause() {
        phase == .running ? pause() : resume()
    }

    func stop() {
        guard let session else { return }
        let now = clock.now
        cancelTimeUp()
        let actual = session.plannedSeconds - session.remaining(at: now)
        guard actual >= configuration.discardThreshold else {
            self.session = nil
            return
        }
        var paused = session.pausedSeconds
        if case .paused(_, let since) = session.state {
            paused += now.timeIntervalSince(since)
        }
        finish(status: .stopped, end: now, actualSeconds: actual, pausedSeconds: paused)
    }

    /// Pauses a running session. Never resumes automatically.
    func systemWillSleep() {
        if phase == .running { pause() }
    }

    func screenDidLock() {
        if phase == .running && configuration.pauseOnScreenLock { pause() }
    }

    private func timeUp() {
        timeUpAction = nil
        guard let session, case .running(let endDate) = session.state else { return }
        finish(status: .completed, end: endDate, actualSeconds: session.plannedSeconds,
               pausedSeconds: session.pausedSeconds)
        onComplete?(session.type)
    }

    // MARK: Finishing

    func rate(energy: Int) {
        guard phase == .finishing, (1...5).contains(energy) else { return }
        commitFinishing(energy: energy)
    }

    func skipEnergy() {
        guard phase == .finishing else { return }
        commitFinishing(energy: nil)
    }

    private func finish(status: SessionStatus, end: Date, actualSeconds: TimeInterval, pausedSeconds: TimeInterval) {
        guard let session else { return }
        self.session = nil
        let (day, entry) = LogFormat.makeEntry(
            start: session.startDate,
            end: end,
            timeZone: TimeZone(identifier: session.timeZone) ?? timeZone(),
            description: taskText,
            type: session.type,
            plannedMinutes: session.plannedMinutes,
            actualSeconds: actualSeconds,
            pausedSeconds: pausedSeconds,
            status: status,
            energy: nil
        )
        if session.type == .focus && configuration.askEnergy {
            finishing = FinishingSession(day: day, entry: entry)
            energyTimeoutAction = clock.schedule(at: clock.now.addingTimeInterval(Self.energyTimeout)) { [weak self] in
                self?.commitFinishing(energy: nil)
            }
        } else {
            write(day: day, entry: entry)
        }
    }

    private func commitFinishing(energy: Int?) {
        guard var pending = finishing else { return }
        energyTimeoutAction?.cancel()
        energyTimeoutAction = nil
        finishing = nil
        pending.entry.energy = energy
        write(day: pending.day, entry: pending.entry)
    }

    private func write(day: LogDay, entry: LogEntry) {
        log(day, entry)
        suggestNext(after: entry)
    }

    /// After focus, suggest a break; after a break, suggest focus with the last preset and text.
    private func suggestNext(after entry: LogEntry) {
        switch entry.type {
        case .focus:
            lastFocusMinutes = entry.planned
            lastFocusText = taskText
            taskText = ""
            selectedType = .break
            selectedMinutes = configuration.defaultBreakMinutes
        case .break:
            selectedType = .focus
            selectedMinutes = lastFocusMinutes
            taskText = lastFocusText
        }
    }

    // MARK: Scheduling

    private func scheduleTimeUp(at date: Date) {
        cancelTimeUp()
        timeUpAction = clock.schedule(at: date) { [weak self] in self?.timeUp() }
    }

    private func cancelTimeUp() {
        timeUpAction?.cancel()
        timeUpAction = nil
    }
}
