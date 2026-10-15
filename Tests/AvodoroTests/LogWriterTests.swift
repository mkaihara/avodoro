import Foundation
import Testing
@testable import Avodoro

struct LogWriterTests {
    let root: URL
    let folder: URL
    let queue: PendingQueue
    let day = LogDay(year: 2026, month: 10, day: 15)

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "AvodoroTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        folder = root.appending(path: "vault/log", directoryHint: .isDirectory)
        queue = PendingQueue(fileURL: root.appending(path: "support/pending.jsonl"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    var logFile: URL { folder.appending(path: "2026-10-15.md") }

    func makeWriter(folder: URL? = nil, timeZone: String = "Europe/Rome") -> LogWriter {
        LogWriter(folder: folder ?? self.folder, queue: queue,
                  currentTimeZone: { TimeZone(identifier: timeZone)! })
    }

    func entry(_ description: String, timeZone: String = "Europe/Rome") -> LogEntry {
        LogEntry(
            start: LogTime(hour: 9, minute: 2), end: LogTime(hour: 9, minute: 27),
            description: description, type: .focus, planned: 25, actual: 25, status: .completed,
            paused: nil, energy: nil, timeZone: timeZone
        )
    }

    func line(_ description: String) -> String {
        "- 09:02-09:27 \(description) [type:: focus] [planned:: 25] [actual:: 25] [status:: completed]"
    }

    func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: Tests

    @Test func createsFileWithFrontmatter() async throws {
        let outcome = await makeWriter().write(entry("First"), day: day)
        #expect(outcome == .written)
        #expect(try read(logFile) == """
            ---
            type: pomodoro-log
            date: 2026-10-15
            tz: Europe/Rome
            schema: 1
            ---

            \(line("First"))

            """)
    }

    @Test func appendsWithoutChangingExistingContent() async throws {
        let existing = "---\ntype: pomodoro-log\ndate: 2026-10-15\ntz: Europe/Rome\nschema: 1\n---\n\n"
            + line("First") + "\n" + "My own note about the morning\n\n- a list item I wrote\n"
        try existing.write(to: logFile, atomically: true, encoding: .utf8)

        await makeWriter().write(entry("Second"), day: day)

        #expect(try read(logFile) == existing + line("Second") + "\n")
    }

    @Test func addsMissingTrailingNewline() async throws {
        let existing = "---\ntz: Europe/Rome\n---\n\nhand-written, no newline"
        try existing.write(to: logFile, atomically: true, encoding: .utf8)

        await makeWriter().write(entry("Next"), day: day)

        #expect(try read(logFile) == existing + "\n" + line("Next") + "\n")
    }

    @Test func writesTzWhenSessionZoneDiffersFromFile() async throws {
        let writer = makeWriter()
        await writer.write(entry("Rome"), day: day)
        await writer.write(entry("Tokyo", timeZone: "Asia/Tokyo"), day: day)

        let text = try read(logFile)
        #expect(text.contains(line("Rome") + "\n"))
        #expect(text.contains(line("Tokyo") + " [tz:: Asia/Tokyo]\n"))
    }

    @Test func missingFolderQueuesLine() async throws {
        let missing = root.appending(path: "nowhere", directoryHint: .isDirectory)
        let writer = makeWriter(folder: missing)

        #expect(await writer.write(entry("Lost?"), day: day) == .queued)
        #expect(await writer.pendingCount == 1)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        #expect(try queue.load() == [.line(PendingLine(day: day, entry: entry("Lost?")))])
    }

    @Test func noFolderQueuesLine() async throws {
        let writer = LogWriter(folder: nil, queue: queue)
        #expect(await writer.write(entry("No folder"), day: day) == .queued)
        #expect(await writer.pendingCount == 1)
    }

    @Test func pendingLinesFlushInOrderBeforeNextWrite() async throws {
        let missing = root.appending(path: "later", directoryHint: .isDirectory)
        let writer = makeWriter(folder: missing)
        await writer.write(entry("One"), day: day)
        await writer.write(entry("Two"), day: day)
        await writer.write(entry("Three"), day: day)
        #expect(await writer.pendingCount == 3)

        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
        #expect(await writer.write(entry("Four"), day: day) == .written)

        let text = try read(missing.appending(path: day.fileName))
        let lines = text.split(separator: "\n").filter { $0.hasPrefix("- ") }.map(String.init)
        #expect(lines == [line("One"), line("Two"), line("Three"), line("Four")])
        #expect(await writer.pendingCount == 0)
        #expect(!FileManager.default.fileExists(atPath: queue.fileURL.path))
    }

    @Test func pendingLinesGoToTheirOwnDayFile() async throws {
        let writer = LogWriter(folder: nil, queue: queue)
        let yesterday = LogDay(year: 2026, month: 10, day: 14)
        await writer.write(entry("Yesterday"), day: yesterday)
        await writer.write(entry("Today"), day: day)

        await writer.setFolder(folder)

        #expect(try read(folder.appending(path: "2026-10-14.md")).contains(line("Yesterday")))
        #expect(try read(logFile).contains(line("Today")))
        #expect(await writer.pendingCount == 0)
    }

    @Test func undecodableQueueLineIsKept() async throws {
        try FileManager.default.createDirectory(
            at: queue.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "not json\n".write(to: queue.fileURL, atomically: true, encoding: .utf8)

        #expect(await makeWriter().write(entry("Fine"), day: day) == .written)
        #expect(try read(queue.fileURL) == "not json\n")
        #expect(try read(logFile).contains(line("Fine")))
    }
}
