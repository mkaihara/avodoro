import Foundation

/// Appends session lines to `<folder>/YYYY-MM-DD.md`, falling back to the pending queue.
///
/// Append only: existing bytes are never rewritten. Writes only inside the log folder
/// (the queue lives in Application Support).
actor LogWriter {
    enum Outcome: Equatable, Sendable {
        case written
        /// Saved to the pending queue; it will be retried before the next write.
        case queued
        /// Neither the log nor the queue could be written. The line is in the system log.
        case lost
    }

    enum WriteError: Error {
        case noFolder
        case folderMissing(URL)
    }

    private(set) var folder: URL?
    private let queue: PendingQueue
    private let currentTimeZone: @Sendable () -> TimeZone

    init(
        folder: URL?,
        queue: PendingQueue = PendingQueue(fileURL: PendingQueue.defaultURL),
        currentTimeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.folder = folder
        self.queue = queue
        self.currentTimeZone = currentTimeZone
    }

    @discardableResult
    func write(_ entry: LogEntry, day: LogDay) -> Outcome {
        // Earlier lines go first, so a new line never jumps ahead of queued ones.
        if flushPending() {
            do {
                try append(entry, day: day)
                return .written
            } catch {
                Log.log.error("Write failed, queueing: \(String(describing: error), privacy: .public)")
            }
        }
        do {
            try queue.append(PendingLine(day: day, entry: entry))
            return .queued
        } catch {
            let line = LogFormat.format(entry, fileTimeZone: nil)
            Log.log.fault("Line lost for \(day.string, privacy: .public): \(line, privacy: .public) (\(String(describing: error), privacy: .public))")
            return .lost
        }
    }

    func setFolder(_ url: URL?) {
        folder = url
        flushPending()
    }

    /// Number of entries waiting in the queue, for the warning dot.
    var pendingCount: Int {
        (try? queue.load().count) ?? 0
    }

    /// Writes queued lines in their original order and stops at the first failure.
    /// Returns true when no session lines are left waiting.
    @discardableResult
    func flushPending() -> Bool {
        let items: [PendingQueue.Item]
        do {
            items = try queue.load()
        } catch {
            Log.log.error("Cannot read pending queue: \(String(describing: error), privacy: .public)")
            return false
        }
        guard !items.isEmpty else { return true }

        var remaining: [PendingQueue.Item] = []
        var failed = false
        for item in items {
            guard case .line(let pending) = item, !failed else {
                remaining.append(item)
                continue
            }
            do {
                try append(pending.entry, day: pending.day)
            } catch {
                failed = true
                remaining.append(item)
            }
        }

        do {
            try queue.replace(with: remaining)
        } catch {
            Log.log.error("Cannot update pending queue: \(String(describing: error), privacy: .public)")
        }
        return !remaining.contains { if case .line = $0 { true } else { false } }
    }

    // MARK: Appending

    private func append(_ entry: LogEntry, day: LogDay) throws {
        guard let folder else { throw WriteError.noFolder }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw WriteError.folderMissing(folder) }

        let fileURL = folder.appending(path: day.fileName)
        let newFileTimeZone = currentTimeZone().identifier
        var coordinationError: NSError?
        var writeError: Error?

        // The vault may live in iCloud Drive and Obsidian may have the file open.
        NSFileCoordinator().coordinate(
            writingItemAt: fileURL, options: .forMerging, error: &coordinationError
        ) { url in
            do {
                try Self.append(entry, day: day, to: url, newFileTimeZone: newFileTimeZone)
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    private static func append(_ entry: LogEntry, day: LogDay, to url: URL, newFileTimeZone: String) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let text = LogFormat.frontmatter(day: day, timeZone: newFileTimeZone)
                + LogFormat.format(entry, fileTimeZone: newFileTimeZone) + "\n"
            try Data(text.utf8).write(to: url, options: .withoutOverwriting)
            return
        }

        let existing = try Data(contentsOf: url)
        let fileTimeZone = LogFormat.frontmatterTimeZone(in: String(decoding: existing, as: UTF8.self))
        var text = LogFormat.format(entry, fileTimeZone: fileTimeZone) + "\n"
        if let last = existing.last, last != 0x0A {
            text = "\n" + text
        }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }
}
