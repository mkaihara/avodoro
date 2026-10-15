import AppKit
import Testing
@testable import Avodoro

@MainActor
struct AvocadoPanelTests {
    let panel = AvocadoPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 320))

    @Test func isBorderlessAndNonActivating() {
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
    }

    @Test func becomesKeyButNotMain() {
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
    }

    @Test func floatsOnAllSpaces() {
        #expect(panel.level == .floating)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!panel.hidesOnDeactivate)
    }

    @Test func isTransparentWithShadow() {
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)
        #expect(panel.hasShadow)
    }

    @Test func dragsOnlyOnSkin() {
        let size = CGSize(width: 240, height: 320)
        #expect(AvocadoView.isOnSkin(CGPoint(x: 120, y: 3), in: size))
        #expect(!AvocadoView.isOnSkin(CGPoint(x: 120, y: 160), in: size))
        #expect(!AvocadoView.isOnSkin(CGPoint(x: 2, y: 2), in: size))
    }
}
