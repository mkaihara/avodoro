import AppKit
import SwiftUI
import Testing
@testable import Avodoro

/// Renders `AppIconView` into the app icon set. Writes the PNGs only when `AVODORO_WRITE_ICON`
/// is set (`make icon`), so a normal test run never touches the source tree.
@MainActor
struct AppIconTests {
    static let iconSet = URL(filePath: #filePath)
        .deletingLastPathComponent() // AvodoroTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
        .appending(path: "Sources/Avodoro/Assets.xcassets/AppIcon.appiconset", directoryHint: .isDirectory)

    /// Pixel sizes the macOS icon set needs (16 to 512 pt at 1× and 2×).
    static let pixelSizes = [16, 32, 64, 128, 256, 512, 1024]

    @Test func renderIcon() throws {
        let write = ProcessInfo.processInfo.environment["AVODORO_WRITE_ICON"] != nil
        for pixels in Self.pixelSizes {
            let renderer = ImageRenderer(content: AppIconView())
            renderer.scale = CGFloat(pixels) / AppIconView.canvas
            let image = try #require(renderer.cgImage)
            #expect(image.width == pixels)
            guard write else { continue }
            let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: Self.iconSet.appending(path: "icon_\(pixels).png"))
        }
    }
}
