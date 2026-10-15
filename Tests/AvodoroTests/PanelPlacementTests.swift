import CoreGraphics
import Testing
@testable import Avodoro

struct PanelPlacementTests {
    // Two screens side by side, AppKit coordinates (y up).
    let main = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let right = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
    let size = CGSize(width: 240, height: 320)

    @Test func frameOnAScreenIsVisible() {
        #expect(PanelPlacement.isVisible(CGRect(x: 2000, y: 300, width: 240, height: 320), on: [main, right]))
    }

    @Test func frameOnADisconnectedScreenIsNotVisible() {
        let onRight = CGRect(x: 2000, y: 300, width: 240, height: 320)
        #expect(!PanelPlacement.isVisible(onRight, on: [main]))
    }

    @Test func sliverDoesNotCount() {
        let mostlyOff = CGRect(x: 1410, y: 300, width: 240, height: 320) // 30 pt on the main screen
        #expect(!PanelPlacement.isVisible(mostlyOff, on: [main]))
    }

    @Test func defaultOriginIsBottomRight() {
        let origin = PanelPlacement.defaultOrigin(size: size, mainVisibleFrame: main)
        #expect(origin == CGPoint(x: 1440 - 240 - 24, y: 24))
    }

    @Test func resizeKeepsCentre() {
        let frame = CGRect(x: 600, y: 300, width: 240, height: 320)
        let resized = PanelPlacement.resized(frame, to: CGSize(width: 300, height: 400), screens: [main, right])
        #expect(resized == CGRect(x: 570, y: 260, width: 300, height: 400))
    }

    @Test func resizeStaysInsideItsScreen() {
        let corner = CGRect(x: 1176, y: 24, width: 240, height: 320) // bottom right of main
        let resized = PanelPlacement.resized(corner, to: CGSize(width: 300, height: 400), screens: [main, right])
        #expect(resized.maxX <= main.maxX)
        #expect(resized.minY >= main.minY)
        #expect(resized.size == CGSize(width: 300, height: 400))
    }

    @Test func avocadoSizes() {
        #expect(AvocadoSize(defaultsValue: nil) == .medium)
        #expect(AvocadoSize(defaultsValue: "huge") == .medium)
        #expect(AvocadoSize(defaultsValue: "large").panelSize == CGSize(width: 300, height: 400))
        #expect(AvocadoSize.small.panelSize == CGSize(width: 192, height: 256))
    }
}
