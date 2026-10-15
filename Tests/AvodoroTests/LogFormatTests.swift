import Foundation
import Testing
@testable import Avodoro

struct LogFormatTests {
    /// Copied from CLAUDE.md on purpose, so a change to `LogFormat.pattern` is caught.
    static let referencePattern = #"^- (\d{2}:\d{2})-(\d{2}:\d{2}) (.*?) \[type:: (focus|break)\] \[planned:: (\d+)\] \[actual:: (\d+)\] \[status:: (completed|stopped)\](?: \[paused:: (\d+)\])?(?: \[energy:: ([1-5])\])?(?: \[tz:: ([^\]]+)\])?$"#

    static let rome = TimeZone(identifier: "Europe/Rome")!

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0,
                     in timeZone: TimeZone = rome) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    static func matchesReference(_ line: String) -> Bool {
        line.range(of: referencePattern, options: .regularExpression) != nil
    }

    static func entry(
        type: SessionType = .focus, status: SessionStatus = .completed,
        paused: Int? = nil, energy: Int? = nil, timeZone: String = "Europe/Rome",
        description: String = "Write blog post draft #writing"
    ) -> LogEntry {
        LogEntry(
            start: LogTime(hour: 9, minute: 2), end: LogTime(hour: 9, minute: 27),
            description: description, type: type, planned: 25, actual: 25, status: status,
            paused: paused, energy: energy, timeZone: timeZone
        )
    }

    // MARK: Formatting

    @Test func examplesFromSpec() {
        #expect(LogFormat.format(Self.entry(energy: 4), fileTimeZone: "Europe/Rome")
            == "- 09:02-09:27 Write blog post draft #writing [type:: focus] [planned:: 25] [actual:: 25] [status:: completed] [energy:: 4]")

        let breakEntry = LogEntry(
            start: LogTime(hour: 9, minute: 27), end: LogTime(hour: 9, minute: 32),
            description: "Break", type: .break, planned: 5, actual: 5, status: .completed,
            paused: nil, energy: nil, timeZone: "Europe/Rome"
        )
        #expect(LogFormat.format(breakEntry, fileTimeZone: "Europe/Rome")
            == "- 09:27-09:32 Break [type:: break] [planned:: 5] [actual:: 5] [status:: completed]")

        let stopped = LogEntry(
            start: LogTime(hour: 10, minute: 40), end: LogTime(hour: 10, minute: 52),
            description: "Refactor parser #code", type: .focus, planned: 20, actual: 9, status: .stopped,
            paused: 3, energy: 2, timeZone: "Europe/Rome"
        )
        #expect(LogFormat.format(stopped, fileTimeZone: "Europe/Rome")
            == "- 10:40-10:52 Refactor parser #code [type:: focus] [planned:: 20] [actual:: 9] [status:: stopped] [paused:: 3] [energy:: 2]")
    }

    @Test(arguments: SessionType.allCases, SessionStatus.allCases)
    func everyCombinationMatchesAndRoundTrips(type: SessionType, status: SessionStatus) {
        for paused in [nil, 3] as [Int?] {
            for energy in (type == .focus ? [nil, 1, 5] : [nil]) as [Int?] {
                for timeZone in ["Europe/Rome", "America/New_York"] {
                    let entry = Self.entry(type: type, status: status, paused: paused,
                                           energy: energy, timeZone: timeZone)
                    let line = LogFormat.format(entry, fileTimeZone: "Europe/Rome")
                    #expect(Self.matchesReference(line), "\(line)")
                    #expect(LogFormat.parse(line, fileTimeZone: "Europe/Rome") == entry)
                    #expect(line.contains("[paused::") == (paused != nil))
                    #expect(line.contains("[energy::") == (energy != nil))
                    #expect(line.contains("[tz::") == (timeZone != "Europe/Rome"))
                }
            }
        }
    }

    @Test func fieldOrder() {
        let line = LogFormat.format(Self.entry(status: .stopped, paused: 3, energy: 2, timeZone: "Asia/Tokyo"),
                                    fileTimeZone: "Europe/Rome")
        #expect(line.hasSuffix("[type:: focus] [planned:: 25] [actual:: 25] [status:: stopped] [paused:: 3] [energy:: 2] [tz:: Asia/Tokyo]"))
    }

    @Test func tzWrittenWhenFileHasNoTimeZone() {
        let line = LogFormat.format(Self.entry(), fileTimeZone: nil)
        #expect(line.hasSuffix("[tz:: Europe/Rome]"))
    }

    @Test func zeroPausedIsOmitted() {
        let line = LogFormat.format(Self.entry(paused: 0), fileTimeZone: "Europe/Rome")
        #expect(!line.contains("paused"))
    }

    // MARK: Building entries

    @Test func makeEntryTruncatesAndRounds() {
        let (day, entry) = LogFormat.makeEntry(
            start: Self.date(2026, 10, 15, 9, 2, 59), end: Self.date(2026, 10, 15, 9, 27, 40),
            timeZone: Self.rome, description: "  Write\n post ", type: .focus, plannedMinutes: 25,
            actualSeconds: 89, pausedSeconds: 20, status: .stopped, energy: 3
        )
        #expect(day == LogDay(year: 2026, month: 10, day: 15))
        #expect(entry.start == LogTime(hour: 9, minute: 2))
        #expect(entry.end == LogTime(hour: 9, minute: 27))
        #expect(entry.description == "Write post")
        #expect(entry.actual == 1)
        #expect(entry.paused == nil)
        #expect(entry.energy == 3)
        #expect(entry.timeZone == "Europe/Rome")
    }

    @Test func roundsToNearestMinute() {
        #expect(LogFormat.roundedMinutes(29) == 0)
        #expect(LogFormat.roundedMinutes(30) == 1)
        #expect(LogFormat.roundedMinutes(89) == 1)
        #expect(LogFormat.roundedMinutes(90) == 2)
        #expect(LogFormat.roundedMinutes(-5) == 0)
    }

    @Test func midnightCrossingUsesStartDate() {
        let (day, entry) = LogFormat.makeEntry(
            start: Self.date(2026, 10, 15, 23, 50), end: Self.date(2026, 10, 16, 0, 15),
            timeZone: Self.rome, description: "Late", type: .focus, plannedMinutes: 25,
            actualSeconds: 1500, pausedSeconds: 0, status: .completed, energy: nil
        )
        #expect(day.fileName == "2026-10-15.md")
        let line = LogFormat.format(entry, fileTimeZone: "Europe/Rome")
        #expect(line.hasPrefix("- 23:50-00:15 Late "))
        #expect(LogFormat.parse(line, fileTimeZone: "Europe/Rome") == entry)
    }

    @Test func breakDropsEnergyAndInvalidEnergyIsDropped() {
        func energy(_ type: SessionType, _ value: Int?) -> Int? {
            LogFormat.makeEntry(
                start: Self.date(2026, 10, 15, 9, 0), end: Self.date(2026, 10, 15, 9, 5),
                timeZone: Self.rome, description: "", type: type, plannedMinutes: 5,
                actualSeconds: 300, pausedSeconds: 0, status: .completed, energy: value
            ).entry.energy
        }
        #expect(energy(.break, 4) == nil)
        #expect(energy(.focus, 0) == nil)
        #expect(energy(.focus, 6) == nil)
        #expect(energy(.focus, 5) == 5)
    }

    // MARK: Sanitizing

    @Test func sanitizeCollapsesWhitespace() {
        #expect(LogFormat.sanitize("  a\n\nb\t c \r\n", type: .focus) == "a b c")
    }

    @Test func sanitizeReplacesBrackets() {
        let text = LogFormat.sanitize("fix [type:: break] bug [[link]]", type: .focus)
        #expect(text == "fix (type:: break) bug ((link))")
        let line = LogFormat.format(Self.entry(description: text), fileTimeZone: "Europe/Rome")
        #expect(LogFormat.parse(line, fileTimeZone: "Europe/Rome")?.type == .focus)
    }

    @Test func sanitizeEmpty() {
        #expect(LogFormat.sanitize(" \n ", type: .focus) == "(untitled)")
        #expect(LogFormat.sanitize("", type: .break) == "Break")
    }

    @Test func sanitizeCutsAtWordBoundary() {
        let text = Array(repeating: "word", count: 60).joined(separator: " ") // 299 chars
        let result = LogFormat.sanitize(text, type: .focus)
        #expect(result.count <= 200)
        #expect(result.hasSuffix("word…"))
        #expect(!result.contains(" …"))
    }

    @Test func sanitizeKeepsWholeWordEndingAtLimit() {
        let text = String(repeating: "a", count: 199) + " tail"
        #expect(LogFormat.sanitize(text, type: .focus) == String(repeating: "a", count: 199) + "…")
    }

    @Test func sanitizeHardCutsSingleLongWord() {
        let result = LogFormat.sanitize(String(repeating: "x", count: 300), type: .focus)
        #expect(result == String(repeating: "x", count: 199) + "…")
    }

    @Test func sanitizeLeavesExactly200Alone() {
        let text = String(repeating: "y", count: 200)
        #expect(LogFormat.sanitize(text, type: .focus) == text)
    }

    // MARK: Parsing

    @Test func nonSessionLinesAreIgnored() {
        for line in [
            "",
            "My notes for today",
            "- 09:00 coffee",
            "- 9:02-9:27 Task [type:: focus] [planned:: 25] [actual:: 25] [status:: completed]",
            "- 09:02-09:27 Task [type:: nap] [planned:: 25] [actual:: 25] [status:: completed]",
            "- 09:02-09:27 Task [type:: focus] [planned:: 25] [actual:: 25] [status:: completed] [energy:: 6]",
            "- 09:02-09:27 Task [type:: focus] [planned:: 25] [actual:: 25] [status:: completed] [energy:: 2] [paused:: 1]",
            "---",
        ] {
            #expect(LogFormat.parse(line, fileTimeZone: "Europe/Rome") == nil, "\(line)")
        }
    }

    @Test func parseTakesFileTimeZoneWhenNoTzField() {
        let line = "- 09:27-09:32 Break [type:: break] [planned:: 5] [actual:: 5] [status:: completed]"
        #expect(LogFormat.parse(line, fileTimeZone: "Europe/Rome")?.timeZone == "Europe/Rome")
        #expect(LogFormat.parse(line, fileTimeZone: nil) == nil)
    }

    // MARK: Frontmatter

    @Test func frontmatterIsExact() {
        let text = LogFormat.frontmatter(day: LogDay(year: 2026, month: 10, day: 15), timeZone: "Europe/Rome")
        #expect(text == "---\ntype: pomodoro-log\ndate: 2026-10-15\ntz: Europe/Rome\nschema: 1\n---\n\n")
        #expect(LogFormat.frontmatterTimeZone(in: text) == "Europe/Rome")
    }

    @Test func frontmatterTimeZoneMissing() {
        #expect(LogFormat.frontmatterTimeZone(in: "- note\ntz: Europe/Rome\n") == nil)
        #expect(LogFormat.frontmatterTimeZone(in: "---\ntype: pomodoro-log\n---\ntz: Asia/Tokyo\n") == nil)
    }

    @Test func logDayCodableAsString() throws {
        let data = try JSONEncoder().encode(LogDay(year: 2026, month: 1, day: 5))
        #expect(String(decoding: data, as: UTF8.self) == "\"2026-01-05\"")
        #expect(try JSONDecoder().decode(LogDay.self, from: data) == LogDay(year: 2026, month: 1, day: 5))
    }
}
