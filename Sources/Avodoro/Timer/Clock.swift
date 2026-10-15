import Foundation

/// The engine's only source of time. Tests use a fake clock and never wait in real time.
/// (Inside this module the name shadows `Swift.Clock`.)
@MainActor
protocol Clock: AnyObject {
    var now: Date { get }
    /// Runs `action` once at `date`, or as soon as possible after it.
    func schedule(at date: Date, _ action: @escaping @MainActor @Sendable () -> Void) -> any ScheduledAction
}

@MainActor
protocol ScheduledAction: AnyObject {
    func cancel()
}

final class SystemClock: Clock {
    var now: Date { Date() }

    func schedule(at date: Date, _ action: @escaping @MainActor @Sendable () -> Void) -> any ScheduledAction {
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return TimerAction(timer: timer)
    }

    private final class TimerAction: ScheduledAction {
        let timer: Timer

        init(timer: Timer) { self.timer = timer }

        func cancel() { timer.invalidate() }
    }
}
