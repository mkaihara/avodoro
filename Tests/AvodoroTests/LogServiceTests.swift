import Foundation
import Testing
@testable import Avodoro

@MainActor
struct LogServiceTests {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "AvodoroTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    var queue: PendingQueue { PendingQueue(fileURL: root.appending(path: "support/pending.jsonl")) }
    let day = LogDay(year: 2026, month: 10, day: 15)

    func entry(_ description: String) -> LogEntry {
        LogEntry(
            start: LogTime(hour: 9, minute: 0), end: LogTime(hour: 9, minute: 5),
            description: description, type: .break, planned: 5, actual: 5, status: .completed,
            paused: nil, energy: nil, timeZone: TimeZone.current.identifier
        )
    }

    @Test func writesInRequestedOrder() async throws {
        let folder = root.appending(path: "log", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let service = LogService(folder: folder, queue: queue)

        for name in ["One", "Two", "Three", "Four", "Five"] {
            service.write(day: day, entry: entry(name))
        }
        await service.waitForWrites()

        let text = try String(contentsOf: folder.appending(path: day.fileName), encoding: .utf8)
        let names = text.split(separator: "\n").compactMap {
            LogFormat.parse(String($0), fileTimeZone: TimeZone.current.identifier)?.description
        }
        #expect(names == ["One", "Two", "Three", "Four", "Five"])
        #expect(service.warning == nil)
    }

    @Test func warningWithoutFolder() async {
        let service = LogService(folder: nil, queue: queue)
        await service.waitForWrites()
        #expect(service.warning == "No log folder chosen.")

        service.write(day: day, entry: entry("Waiting"))
        await service.waitForWrites()
        #expect(service.pendingCount == 1)
        #expect(service.warning == "No log folder chosen. 1 session is waiting to be written.")
    }

    @Test func warningForMissingFolderAndFlushOnSetFolder() async throws {
        let folder = root.appending(path: "missing", directoryHint: .isDirectory)
        let service = LogService(folder: folder, queue: queue)
        service.write(day: day, entry: entry("A"))
        service.write(day: day, entry: entry("B"))
        await service.waitForWrites()
        #expect(service.warning == "Log folder not found. 2 sessions are waiting to be written.")

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        service.setFolder(folder)
        await service.waitForWrites()
        #expect(service.pendingCount == 0)
        #expect(service.warning == nil)
    }
}
