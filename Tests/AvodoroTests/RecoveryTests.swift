import Foundation
import Testing
@testable import Avodoro

struct RecoveryTests {
    let store = RecoveryStore(fileURL: FileManager.default.temporaryDirectory
        .appending(path: "AvodoroTests-\(UUID().uuidString)/support/active-session.json"))

    let record = RecoveryRecord(
        session: Session(
            type: .focus, plannedMinutes: 25, startDate: Date(timeIntervalSince1970: 1_792_000_000),
            timeZone: "Europe/Rome",
            state: .paused(remaining: 600, since: Date(timeIntervalSince1970: 1_792_000_900)),
            pausedSeconds: 30
        ),
        finishing: nil,
        taskText: "Write report #writing",
        heartbeat: Date(timeIntervalSince1970: 1_792_000_930)
    )

    @Test func saveLoadDelete() throws {
        #expect(store.load() == nil)
        try store.save(record)
        #expect(store.load() == record)
        try store.save(nil)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        try store.save(nil) // deleting twice is fine
    }

    @Test func corruptFileLoadsAsNil() throws {
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.fileURL)
        #expect(store.load() == nil)
    }

    @Test func finishingRecordRoundTrips() throws {
        let entry = LogEntry(
            start: LogTime(hour: 9, minute: 0), end: LogTime(hour: 9, minute: 25), description: "x",
            type: .focus, planned: 25, actual: 25, status: .completed, paused: nil, energy: nil,
            timeZone: "Europe/Rome"
        )
        let finished = RecoveryRecord(
            session: nil, finishing: FinishingSession(day: LogDay(year: 2026, month: 10, day: 16), entry: entry),
            taskText: "x", heartbeat: Date(timeIntervalSince1970: 0)
        )
        try store.save(finished)
        #expect(store.load() == finished)
    }
}
