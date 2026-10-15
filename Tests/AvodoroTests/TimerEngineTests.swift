import Foundation
import Testing
@testable import Avodoro

@MainActor
final class FakeClock: Clock {
    var now: Date
    private var actions: [FakeAction] = []

    init(now: Date) { self.now = now }

    func schedule(at date: Date, _ action: @escaping @MainActor @Sendable () -> Void) -> any ScheduledAction {
        let scheduled = FakeAction(date: date, action: action)
        actions.append(scheduled)
        return scheduled
    }

    /// Moves time forward, firing due actions in date order with `now` set to each action's date.
    func advance(by seconds: TimeInterval) {
        let target = now.addingTimeInterval(seconds)
        while let next = actions.filter({ !$0.isCancelled && $0.date <= target }).min(by: { $0.date < $1.date }) {
            actions.removeAll { $0 === next }
            now = max(now, next.date)
            next.action()
        }
        now = target
    }

    var pendingCount: Int { actions.filter { !$0.isCancelled }.count }

    @MainActor
    final class FakeAction: ScheduledAction {
        let date: Date
        let action: @MainActor @Sendable () -> Void
        private(set) var isCancelled = false

        init(date: Date, action: @escaping @MainActor @Sendable () -> Void) {
            self.date = date
            self.action = action
        }

        func cancel() { isCancelled = true }
    }
}

@MainActor
final class TimerEngineTests {
    let clock = FakeClock(now: LogFormatTests.date(2026, 10, 15, 9, 0))
    var lines: [(day: LogDay, entry: LogEntry)] = []
    var completed: [SessionType] = []
    var engine: TimerEngine!

    init() {
        makeEngine()
    }

    func makeEngine(_ configuration: TimerEngine.Configuration = .init()) {
        engine = TimerEngine(
            clock: clock,
            configuration: configuration,
            timeZone: { LogFormatTests.rome },
            log: { [unowned self] day, entry in lines.append((day, entry)) }
        )
        engine.onComplete = { [unowned self] type in completed.append(type) }
    }

    func minutes(_ value: Double) -> TimeInterval { value * 60 }

    func startFocus(_ minutes: Int = 25, text: String = "Write blog post #writing") {
        engine.select(type: .focus)
        engine.select(minutes: minutes)
        engine.taskText = text
        engine.start()
    }

    // MARK: Completion

    @Test func startToCompletion() {
        startFocus()
        #expect(engine.phase == .running)
        #expect(engine.remaining(at: clock.now) == minutes(25))

        clock.advance(by: minutes(10))
        #expect(engine.remaining(at: clock.now) == minutes(15))
        #expect(abs(engine.progress(at: clock.now) - 0.4) < 0.0001)

        clock.advance(by: minutes(15))
        #expect(engine.phase == .finishing)
        #expect(completed == [.focus])
        #expect(lines.isEmpty)

        engine.rate(energy: 4)
        #expect(engine.phase == .idle)
        #expect(lines.count == 1)
        let line = LogFormat.format(lines[0].entry, fileTimeZone: "Europe/Rome")
        #expect(line == "- 09:00-09:25 Write blog post #writing [type:: focus] [planned:: 25] [actual:: 25] [status:: completed] [energy:: 4]")
        #expect(lines[0].day == LogDay(year: 2026, month: 10, day: 15))
    }

    @Test func endTimeIsTimeUpNotRatingTime() {
        startFocus()
        clock.advance(by: minutes(25))
        clock.advance(by: minutes(1))
        engine.skipEnergy()
        #expect(lines[0].entry.end == LogTime(hour: 9, minute: 25))
        #expect(lines[0].entry.energy == nil)
    }

    // MARK: Pause and resume

    @Test func pauseAndResumeAccounting() {
        startFocus()
        clock.advance(by: minutes(5))
        engine.pause()
        #expect(engine.phase == .paused)

        clock.advance(by: minutes(3))
        #expect(engine.remaining(at: clock.now) == minutes(20))
        #expect(lines.isEmpty && completed.isEmpty)

        engine.resume()
        #expect(engine.remaining(at: clock.now) == minutes(20))
        clock.advance(by: minutes(19))
        #expect(engine.phase == .running)
        clock.advance(by: minutes(1))
        engine.skipEnergy()

        let entry = lines[0].entry
        #expect(entry.start == LogTime(hour: 9, minute: 0))
        #expect(entry.end == LogTime(hour: 9, minute: 28))
        #expect(entry.actual == 25)
        #expect(entry.paused == 3)
        #expect(entry.status == .completed)
    }

    @Test func togglePause() {
        startFocus()
        engine.togglePause()
        #expect(engine.phase == .paused)
        engine.togglePause()
        #expect(engine.phase == .running)
    }

    // MARK: Stop

    @Test func stopBelowThresholdDiscards() {
        startFocus()
        clock.advance(by: 59)
        engine.stop()
        #expect(engine.phase == .idle)
        #expect(lines.isEmpty)
        #expect(clock.pendingCount == 0)
        // Nothing changes after a discard.
        #expect(engine.selectedType == .focus)
        #expect(engine.taskText == "Write blog post #writing")
    }

    @Test func pausesDoNotCountTowardsThreshold() {
        startFocus()
        clock.advance(by: 30)
        engine.pause()
        clock.advance(by: minutes(5))
        engine.stop()
        #expect(lines.isEmpty)
        #expect(engine.phase == .idle)
    }

    @Test func stopAboveThresholdLogsStopped() {
        startFocus(20)
        clock.advance(by: minutes(10))
        engine.stop()
        #expect(engine.phase == .finishing)
        #expect(completed.isEmpty)
        engine.rate(energy: 2)

        let entry = lines[0].entry
        #expect(entry.status == .stopped)
        #expect(entry.actual == 10)
        #expect(entry.planned == 20)
        #expect(entry.end == LogTime(hour: 9, minute: 10))
        #expect(entry.energy == 2)
        #expect(clock.pendingCount == 0)
    }

    @Test func stopWhilePausedCountsOpenPause() {
        startFocus()
        clock.advance(by: minutes(9))
        engine.pause()
        clock.advance(by: minutes(3))
        engine.stop()
        engine.skipEnergy()
        #expect(lines[0].entry.actual == 9)
        #expect(lines[0].entry.paused == 3)
        #expect(lines[0].entry.end == LogTime(hour: 9, minute: 12))
    }

    // MARK: Sleep and lock

    @Test func sleepPausesAndNeverResumes() {
        startFocus()
        clock.advance(by: minutes(5))
        engine.systemWillSleep()
        #expect(engine.phase == .paused)
        clock.advance(by: minutes(60))
        #expect(engine.phase == .paused)
        #expect(engine.remaining(at: clock.now) == minutes(20))
        #expect(completed.isEmpty)
    }

    @Test func screenLockPausesOnlyWhenEnabled() {
        startFocus()
        engine.screenDidLock()
        #expect(engine.phase == .paused)

        makeEngine(.init(pauseOnScreenLock: false))
        startFocus()
        engine.screenDidLock()
        #expect(engine.phase == .running)
    }

    // MARK: Energy

    @Test func energyTimeoutWritesWithoutEnergy() {
        startFocus()
        clock.advance(by: minutes(25))
        clock.advance(by: 119)
        #expect(engine.phase == .finishing)
        #expect(lines.isEmpty)
        clock.advance(by: 1)
        #expect(engine.phase == .idle)
        #expect(lines.count == 1)
        #expect(lines[0].entry.energy == nil)
    }

    @Test func invalidEnergyIsIgnored() {
        startFocus()
        clock.advance(by: minutes(25))
        engine.rate(energy: 0)
        engine.rate(energy: 6)
        #expect(engine.phase == .finishing)
        engine.rate(energy: 1)
        #expect(lines[0].entry.energy == 1)
    }

    @Test func startDuringFinishingWritesPendingLineFirst() {
        startFocus()
        clock.advance(by: minutes(25))
        clock.advance(by: 30)
        engine.start()

        #expect(lines.count == 1)
        #expect(lines[0].entry.type == .focus)
        #expect(lines[0].entry.energy == nil)
        #expect(engine.phase == .running)
        #expect(engine.session?.type == .break)
        #expect(engine.session?.plannedMinutes == 5)

        // The old energy timeout must not fire into the new session.
        clock.advance(by: minutes(4))
        #expect(lines.count == 1)
        clock.advance(by: minutes(1))
        #expect(lines.count == 2)
        #expect(lines[1].entry.type == .break)
    }

    @Test func breakSkipsPickerAndWritesImmediately() {
        engine.select(type: .break)
        #expect(engine.selectedMinutes == 5)
        engine.start()
        clock.advance(by: minutes(5))
        #expect(engine.phase == .idle)
        #expect(completed == [.break])
        #expect(LogFormat.format(lines[0].entry, fileTimeZone: "Europe/Rome")
            == "- 09:00-09:05 Break [type:: break] [planned:: 5] [actual:: 5] [status:: completed]")
    }

    @Test func askEnergyOffWritesFocusImmediately() {
        makeEngine(.init(askEnergy: false))
        startFocus()
        clock.advance(by: minutes(25))
        #expect(engine.phase == .idle)
        #expect(lines.count == 1)
        #expect(clock.pendingCount == 0)
    }

    // MARK: Task text and suggestions

    @Test func loggedDescriptionIsTextAtFinish() {
        startFocus(text: "First idea")
        clock.advance(by: minutes(10))
        engine.taskText = "Better name [draft]"
        clock.advance(by: minutes(15))
        engine.taskText = "Typed after finish"
        engine.skipEnergy()
        #expect(lines[0].entry.description == "Better name (draft)")
    }

    @Test func suggestionsAlternate() {
        startFocus(20, text: "Refactor parser")
        clock.advance(by: minutes(20))
        engine.skipEnergy()
        #expect(engine.selectedType == .break)
        #expect(engine.selectedMinutes == 5)
        #expect(engine.taskText == "")

        engine.start()
        clock.advance(by: minutes(5))
        #expect(engine.selectedType == .focus)
        #expect(engine.selectedMinutes == 20)
        #expect(engine.taskText == "Refactor parser")
        #expect(engine.remaining(at: clock.now) == minutes(20))
    }

    @Test func defaultBreakLengthComesFromConfiguration() {
        makeEngine(.init(defaultBreakMinutes: 10))
        startFocus()
        clock.advance(by: minutes(25))
        engine.skipEnergy()
        #expect(engine.selectedMinutes == 10)
    }

    // MARK: Wrong phases

    @Test func actionsInWrongPhasesAreNoOps() {
        engine.pause()
        engine.resume()
        engine.stop()
        engine.rate(energy: 3)
        engine.skipEnergy()
        #expect(engine.phase == .idle)
        #expect(lines.isEmpty)

        startFocus()
        let session = engine.session
        engine.select(minutes: 5)
        engine.select(type: .break)
        engine.start()
        engine.rate(energy: 3)
        engine.resume()
        #expect(engine.session == session)
        #expect(engine.selectedMinutes == 25)
    }
}
