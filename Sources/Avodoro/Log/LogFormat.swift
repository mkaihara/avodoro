import Foundation

enum SessionType: String, Codable, Sendable, CaseIterable {
    case focus
    case `break`
}

enum SessionStatus: String, Codable, Sendable, CaseIterable {
    case completed
    case stopped
}

/// A local wall clock time, truncated to the minute.
struct LogTime: Codable, Hashable, Sendable {
    var hour: Int
    var minute: Int

    var string: String { String(format: "%02d:%02d", hour, minute) }

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init?(_ text: String) {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        self.init(hour: hour, minute: minute)
    }
}

/// The local date a session started on. It names the log file.
struct LogDay: Codable, Hashable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    var string: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var fileName: String { string + ".md" }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    init?(_ text: String) {
        let parts = text.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let day = LogDay(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid day \(text)")
        }
        self = day
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

/// The content of one log line (schema 1).
struct LogEntry: Codable, Hashable, Sendable {
    var start: LogTime
    var end: LogTime
    /// Already sanitized.
    var description: String
    var type: SessionType
    var planned: Int
    var actual: Int
    var status: SessionStatus
    var paused: Int?
    var energy: Int?
    /// IANA time zone of the session. Always set; written to the line only when it differs
    /// from the file's frontmatter `tz`.
    var timeZone: String
}

/// Schema 1 of the log. A contract with the future analysis tool: see CLAUDE.md before changing.
enum LogFormat {
    static let schema = 1
    static let maxDescriptionLength = 200

    /// The reference regex from CLAUDE.md, verbatim.
    static let pattern = #"^- (\d{2}:\d{2})-(\d{2}:\d{2}) (.*?) \[type:: (focus|break)\] \[planned:: (\d+)\] \[actual:: (\d+)\] \[status:: (completed|stopped)\](?: \[paused:: (\d+)\])?(?: \[energy:: ([1-5])\])?(?: \[tz:: ([^\]]+)\])?$"#

    private static let regex = try! NSRegularExpression(pattern: pattern)

    // MARK: Building

    static func makeEntry(
        start: Date,
        end: Date,
        timeZone: TimeZone,
        description: String,
        type: SessionType,
        plannedMinutes: Int,
        actualSeconds: TimeInterval,
        pausedSeconds: TimeInterval,
        status: SessionStatus,
        energy: Int?
    ) -> (day: LogDay, entry: LogEntry) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startParts = calendar.dateComponents([.hour, .minute], from: start)
        let endParts = calendar.dateComponents([.hour, .minute], from: end)

        let day = LogDay(date: start, timeZone: timeZone)
        let pausedMinutes = roundedMinutes(pausedSeconds)
        let entry = LogEntry(
            start: LogTime(hour: startParts.hour!, minute: startParts.minute!),
            end: LogTime(hour: endParts.hour!, minute: endParts.minute!),
            description: sanitize(description, type: type),
            type: type,
            planned: plannedMinutes,
            actual: roundedMinutes(actualSeconds),
            status: status,
            paused: pausedMinutes > 0 ? pausedMinutes : nil,
            energy: type == .focus ? energy.flatMap { (1...5).contains($0) ? $0 : nil } : nil,
            timeZone: timeZone.identifier
        )
        return (day, entry)
    }

    static func roundedMinutes(_ seconds: TimeInterval) -> Int {
        Int((max(0, seconds) / 60).rounded())
    }

    static func sanitize(_ text: String, type: SessionType) -> String {
        var result = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")

        if result.count > maxDescriptionLength {
            let limit = maxDescriptionLength - 1 // room for the ellipsis
            let head = result.prefix(limit)
            let nextIsSpace = result[head.endIndex] == " "
            var cut = Substring(head)
            if !nextIsSpace, let lastSpace = head.lastIndex(of: " ") {
                cut = head[..<lastSpace]
            }
            result = cut.trimmingCharacters(in: .whitespaces) + "…"
        }

        if result.isEmpty {
            return type == .focus ? "(untitled)" : "Break"
        }
        return result
    }

    // MARK: Formatting

    static func format(_ entry: LogEntry, fileTimeZone: String?) -> String {
        var line = "- \(entry.start.string)-\(entry.end.string) \(entry.description)"
        line += " [type:: \(entry.type.rawValue)]"
        line += " [planned:: \(entry.planned)]"
        line += " [actual:: \(entry.actual)]"
        line += " [status:: \(entry.status.rawValue)]"
        if let paused = entry.paused, paused > 0 {
            line += " [paused:: \(paused)]"
        }
        if let energy = entry.energy {
            line += " [energy:: \(energy)]"
        }
        if entry.timeZone != fileTimeZone {
            line += " [tz:: \(entry.timeZone)]"
        }
        return line
    }

    static func frontmatter(day: LogDay, timeZone: String) -> String {
        """
        ---
        type: pomodoro-log
        date: \(day.string)
        tz: \(timeZone)
        schema: \(schema)
        ---


        """
    }

    // MARK: Parsing

    /// Returns nil for any line that isn't a session, such as notes written by hand.
    static func parse(_ line: String, fileTimeZone: String?) -> LogEntry? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }

        func group(_ index: Int) -> String? {
            let nsRange = match.range(at: index)
            guard nsRange.location != NSNotFound, let range = Range(nsRange, in: line) else { return nil }
            return String(line[range])
        }

        guard let start = group(1).flatMap(LogTime.init),
              let end = group(2).flatMap(LogTime.init),
              let description = group(3),
              let type = group(4).flatMap(SessionType.init(rawValue:)),
              let planned = group(5).flatMap({ Int($0) }),
              let actual = group(6).flatMap({ Int($0) }),
              let status = group(7).flatMap(SessionStatus.init(rawValue:)),
              let timeZone = group(10) ?? fileTimeZone
        else { return nil }

        return LogEntry(
            start: start,
            end: end,
            description: description,
            type: type,
            planned: planned,
            actual: actual,
            status: status,
            paused: group(8).flatMap { Int($0) },
            energy: group(9).flatMap { Int($0) },
            timeZone: timeZone
        )
    }

    /// The `tz` value from a file's leading frontmatter block, if any.
    static func frontmatterTimeZone(in text: String) -> String? {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).makeIterator()
        guard lines.next() == "---" else { return nil }
        while let line = lines.next(), line != "---" {
            if line.hasPrefix("tz:") {
                let value = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}
