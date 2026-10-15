import Foundation

/// A running or paused session. Codable so it can be saved for crash recovery.
struct Session: Codable, Equatable, Sendable {
    enum State: Codable, Equatable, Sendable {
        case running(endDate: Date)
        case paused(remaining: TimeInterval, since: Date)
    }

    var type: SessionType
    var plannedMinutes: Int
    var startDate: Date
    /// IANA identifier of the time zone when the session started.
    var timeZone: String
    var state: State
    /// Total of the closed pause intervals. An open pause is not included.
    var pausedSeconds: TimeInterval = 0

    var plannedSeconds: TimeInterval { TimeInterval(plannedMinutes * 60) }

    func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .running(let endDate): max(0, endDate.timeIntervalSince(now))
        case .paused(let remaining, _): remaining
        }
    }
}

/// A finished focus session whose line waits for an energy rating.
struct FinishingSession: Equatable, Sendable {
    var day: LogDay
    var entry: LogEntry
}
