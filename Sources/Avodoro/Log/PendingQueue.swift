import Foundation

/// A session line that could not be written yet, with the day of the file it belongs to.
struct PendingLine: Codable, Hashable, Sendable {
    var day: LogDay
    var entry: LogEntry
}

/// Lines waiting to be written, one JSON object per line in `pending.jsonl`.
///
/// Stores the structured entry rather than the final text, so the `tz` field is decided against
/// the frontmatter of the file the line finally lands in.
struct PendingQueue: Sendable {
    enum Item: Hashable, Sendable {
        case line(PendingLine)
        /// A queue line that could not be decoded. Kept verbatim so nothing is lost.
        case raw(String)
    }

    let fileURL: URL

    static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Avodoro", directoryHint: .isDirectory)
            .appending(path: "pending.jsonl")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    func append(_ line: PendingLine) throws {
        var data = try Self.encoder.encode(line)
        data.append(0x0A)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: fileURL, options: .withoutOverwriting)
        }
    }

    func load() throws -> [Item] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return text.split(separator: "\n").map { rawLine in
            if let line = try? JSONDecoder().decode(PendingLine.self, from: Data(rawLine.utf8)) {
                return .line(line)
            }
            Log.log.error("Undecodable pending line kept: \(rawLine, privacy: .public)")
            return .raw(String(rawLine))
        }
    }

    func replace(with items: [Item]) throws {
        guard !items.isEmpty else {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            return
        }
        var data = Data()
        for item in items {
            switch item {
            case .line(let line): data.append(try Self.encoder.encode(line))
            case .raw(let text): data.append(Data(text.utf8))
            }
            data.append(0x0A)
        }
        try data.write(to: fileURL, options: .atomic)
    }
}
