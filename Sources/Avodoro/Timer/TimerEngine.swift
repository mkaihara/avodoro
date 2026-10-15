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
        /// After a crash: asking whether to log the unfinished session.
        case recovering
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
    /// An unfinished session found at launch, waiting for "Log it" or "Discard".
    private(set) var recovered: RecoveryRecord?
    private(set) var selectedType: SessionType = .focus
    private(set) var selectedMinutes = TimerEngine.defaultFocusMinutes
    /// Editable while a session runs; the logged description is the text when the session finishes.
    var taskText = ""
    /// Set after a break restores the previous task text, so the view selects it on the next focus
    /// and typing replaces it.
    private(set) var selectsTaskTextOnNextFocus = false

    /// Called when time is up (never on Stop), for sound and notification, with the session's
    /// type and its task text as it was when time ran out.
    @ObservationIgnored var onComplete: (@MainActor (SessionType, String) -> Void)?
    /// Counts sessions whose time ran out. The pit's completion motion watches it.
    private(set) var completionCount = 0
    /// Called after every state change, so the active session can be saved for crash recovery.
    @ObservationIgnored var onStateChange: (@MainActor () -> Void)?

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
        if recovered != nil { return .recovering }
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

    /// Returns true once after a break restored the task text.
    func consumeTaskTextSelection() -> Bool {
        defer { selectsTaskTextOnNextFocus = false }
        return selectsTaskTextOnNextFocus
    }

    // MARK: Running

    func start() {
        switch phase {
        case .running, .paused: return
        case .finishing: commitFinishing(energy: nil)
        case .recovering: logRecovered()
        case .idle: break
        }
        selectsTaskTextOnNextFocus = false
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
        changed()
    }

    func pause() {
        guard var session, case .running(let endDate) = session.state else { return }
        let now = clock.now
        session.state = .paused(remaining: max(0, endDate.timeIntervalSince(now)), since: now)
        self.session = session
        cancelTimeUp()
        changed()
    }

    func resume() {
        guard var session, case .paused(let remaining, let since) = session.state else { return }
        let now = clock.now
        let endDate = now.addingTimeInterval(remaining)
        session.pausedSeconds += now.timeIntervalSince(since)
        session.state = .running(endDate: endDate)
        self.session = session
        scheduleTimeUp(at: endDate)
        changed()
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
            changed()
            return
        }
        var paused = session.pausedSeconds
        if case .paused(_, let since) = session.state {
            paused += now.timeIntervalSince(since)
        }
        finish(status: .stopped, end: now, actualSeconds: actual, pausedSeconds: paused)
        changed()
    }

    /// Drops a running or paused session without logging it (Quit → Discard).
    func discard() {
        guard session != nil else { return }
        cancelTimeUp()
        session = nil
        changed()
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
        // Captured first: writing a break's line restores the previous focus text.
        let description = taskText
        finish(status: .completed, end: endDate, actualSeconds: session.plannedSeconds,
               pausedSeconds: session.pausedSeconds)
        completionCount += 1
        changed()
        onComplete?(session.type, description)
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
        changed()
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
            selectsTaskTextOnNextFocus = !taskText.isEmpty
        }
    }

    // MARK: Recovery

    /// What to save so the session survives a crash; nil when there is nothing to lose.
    func snapshot(heartbeat: Date) -> RecoveryRecord? {
        if let recovered { return recovered }
        guard session != nil || finishing != nil else { return nil }
        return RecoveryRecord(session: session, finishing: finishing, taskText: taskText, heartbeat: heartbeat)
    }

    /// At launch. A session that had already finished (energy question open) is written at once;
    /// an unfinished one waits for `logRecovered()` or `discardRecovered()`.
    func restore(_ record: RecoveryRecord) {
        guard phase == .idle else { return }
        taskText = record.taskText
        if let finishing = record.finishing {
            write(day: finishing.day, entry: finishing.entry)
        } else if record.session != nil {
            recovered = record
        }
        changed()
    }

    /// Logs the recovered session as `stopped`, ending at its last heartbeat.
    func logRecovered() {
        guard let record = recovered else { return }
        recovered = nil
        if let (day, entry) = Self.recoveredEntry(record, fallbackTimeZone: timeZone()) {
            log(day, entry)
        }
        changed()
    }

    func discardRecovered() {
        guard recovered != nil else { return }
        recovered = nil
        changed()
    }

    /// Local start time of the recovered session, such as "14:05".
    var recoveredStartTime: String? {
        guard let session = recovered?.session else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: session.timeZone) ?? timeZone()
        let parts = calendar.dateComponents([.hour, .minute], from: session.startDate)
        return LogTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0).string
    }

    static func recoveredEntry(_ record: RecoveryRecord, fallbackTimeZone: TimeZone) -> (day: LogDay, entry: LogEntry)? {
        guard let session = record.session else { return nil }
        let heartbeat = max(record.heartbeat, session.startDate)
        var paused = session.pausedSeconds
        let remaining: TimeInterval
        switch session.state {
        case .running(let endDate):
            remaining = max(0, endDate.timeIntervalSince(heartbeat))
        case .paused(let pausedRemaining, let since):
            remaining = pausedRemaining
            paused += max(0, heartbeat.timeIntervalSince(since))
        }
        return LogFormat.makeEntry(
            start: session.startDate,
            end: heartbeat,
            timeZone: TimeZone(identifier: session.timeZone) ?? fallbackTimeZone,
            description: record.taskText,
            type: session.type,
            plannedMinutes: session.plannedMinutes,
            actualSeconds: min(max(0, session.plannedSeconds - remaining), session.plannedSeconds),
            pausedSeconds: paused,
            status: .stopped,
            energy: nil
        )
    }

    private func changed() {
        onStateChange?()
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
