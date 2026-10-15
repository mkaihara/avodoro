import AppKit
import SwiftUI
import Testing
@testable import Avodoro

@MainActor
struct SnapshotTests {
    /// `snapshots/` at the repo root, found from this file's path.
    static let outputDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent() // AvodoroTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
        .appending(path: "snapshots", directoryHint: .isDirectory)

    @Test func placeholder() throws {
        try render(AvocadoView(), name: "placeholder")
    }

    private func render(_ view: some View, name: String) throws {
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
