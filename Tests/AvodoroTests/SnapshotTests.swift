import AppKit
import SwiftUI
import Testing
@testable import Avodoro

/// Renders `AvocadoView` in every state and size to `snapshots/*.png` (`make snapshot`).
@MainActor
struct SnapshotTests {
    /// `snapshots/` at the repo root, found from this file's path.
    static let outputDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent() // AvodoroTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
        .appending(path: "snapshots", directoryHint: .isDirectory)

    static let sizes: [(name: String, scale: CGFloat)] = [("small", 0.8), ("medium", 1), ("large", 1.25)]

    enum State: String, CaseIterable {
        case idle, running0, running50, running90, paused, finishing, warning
    }

    @Test(arguments: State.allCases)
    func render(_ state: State) throws {
        let clock = FakeClock(now: LogFormatTests.date(2026, 10, 15, 9, 0))
        let engine = TimerEngine(clock: clock, timeZone: { LogFormatTests.rome }, log: { _, _ in })
        var warning: String?

        func start() {
            engine.select(minutes: 20)
            engine.taskText = "Write blog post draft #writing"
            engine.start()
        }

        switch state {
        case .idle:
            break
        case .running0:
            start()
        case .running50:
            start(); clock.advance(by: 10 * 60)
        case .running90:
            start(); clock.advance(by: 18 * 60)
        case .paused:
            start(); clock.advance(by: 7 * 60 + 25); engine.pause()
        case .finishing:
            start(); clock.advance(by: 20 * 60)
        case .warning:
            warning = "Log folder not found. 2 sessions are waiting to be written."
        }

        for size in Self.sizes {
            let view = AvocadoView(engine: engine, warning: warning, scale: size.scale)
            try write(view, name: "\(state.rawValue)-\(size.name)")
        }
    }

    private func write(_ view: some View, name: String) throws {
        let renderer = ImageRenderer(content: view.environment(\.isSnapshot, true))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let data = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        )
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        try data.write(to: Self.outputDirectory.appending(path: "\(name).png"))
    }
}
