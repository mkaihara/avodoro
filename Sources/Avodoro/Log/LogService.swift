import Foundation
import Observation

/// Connects the engine to the `LogWriter` actor and tracks what the warning dot should say.
@MainActor
@Observable
final class LogService {
    /// Until the Settings window exists (M6): `defaults write com.example.avodoro logFolderPath <path>`.
    static let folderKey = "logFolderPath"

    private(set) var folder: URL?
    private(set) var pendingCount = 0

    @ObservationIgnored private let writer: LogWriter
    @ObservationIgnored private var lastOperation: Task<Void, Never>?

    init(folder: URL?, queue: PendingQueue = PendingQueue(fileURL: PendingQueue.defaultURL)) {
        self.folder = folder
        writer = LogWriter(folder: folder, queue: queue)
        enqueue { await $0.flushPending() }
    }

    static func folderFromDefaults(_ defaults: UserDefaults = .standard) -> URL? {
        guard let path = defaults.string(forKey: folderKey), !path.isEmpty else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    func write(day: LogDay, entry: LogEntry) {
        enqueue { await $0.write(entry, day: day) }
    }

    func setFolder(_ url: URL?) {
        folder = url
        enqueue { await $0.setFolder(url) }
    }

    /// Waits until every write requested so far has finished.
    func waitForWrites() async {
        await lastOperation?.value
    }

    var todayLogURL: URL? {
        folder?.appending(path: LogDay(date: Date(), timeZone: .current).fileName)
    }

    /// Plain-words reason for the warning dot, or nil when all is well.
    var warning: String? {
        let waiting = switch pendingCount {
        case 0: ""
        case 1: " 1 session is waiting to be written."
        default: " \(pendingCount) sessions are waiting to be written."
        }
        guard let folder else { return "No log folder chosen." + waiting }
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            return "Log folder not found." + waiting
        }
        if pendingCount > 0 { return "The log could not be written." + waiting }
        return nil
    }

    /// Runs writer operations one after another, in the order they were requested.
    private func enqueue(_ operation: @escaping @Sendable (LogWriter) async -> Void) {
        let previous = lastOperation
        let writer = self.writer
        lastOperation = Task {
            await previous?.value
            await operation(writer)
            pendingCount = await writer.pendingCount
        }
    }
}
