import Foundation

/// `~/Library/Application Support/Avodoro/active-session.json`.
struct RecoveryStore: Sendable {
    let fileURL: URL

    static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Avodoro", directoryHint: .isDirectory)
            .appending(path: "active-session.json")
    }

    /// Writes the record atomically; nil removes the file.
    func save(_ record: RecoveryRecord?) throws {
        guard let record else {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            return
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: fileURL, options: .atomic)
    }

    func load() -> RecoveryRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try JSONDecoder().decode(RecoveryRecord.self, from: Data(contentsOf: fileURL))
        } catch {
            Log.app.error("Cannot read \(self.fileURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

/// Saves the engine's active session on every state change, and a heartbeat every 30 s
/// while a session runs, so a crash loses at most 30 s.
@MainActor
final class SessionRecorder {
    static let heartbeatInterval: TimeInterval = 30

    private let engine: TimerEngine
    private let store: RecoveryStore
    private var timer: Timer?

    init(engine: TimerEngine, store: RecoveryStore) {
        self.engine = engine
        self.store = store
        engine.onStateChange = { [weak self] in self?.save() }

        let timer = Timer(timeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.engine.phase == .running else { return }
                self.save()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func save() {
        do {
            try store.save(engine.snapshot(heartbeat: engine.now))
        } catch {
            Log.app.error("Cannot save the active session: \(String(describing: error), privacy: .public)")
        }
    }
}
