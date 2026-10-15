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
        #expect(AvocadoShape.skinContains(CGPoint(x: 120, y: 4), in: size))      // top of the skin
        #expect(AvocadoShape.skinContains(CGPoint(x: 120, y: 316), in: size))    // bottom of the skin
        #expect(!AvocadoShape.skinContains(CGPoint(x: 120, y: 160), in: size))   // flesh
        #expect(!AvocadoShape.skinContains(CGPoint(x: 120, y: 224), in: size))   // pit
        #expect(!AvocadoShape.skinContains(CGPoint(x: 2, y: 2), in: size))       // transparent corner
    }

    func key(_ characters: String, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0
        )!
    }

    @Test func commandPeriodStops() {
        var count = 0
        panel.onCommandPeriod = { count += 1 }
        #expect(panel.performKeyEquivalent(with: key(".", .command)))
        #expect(count == 1)
    }

    @Test func otherKeysAreNotCommandPeriod() {
        #expect(!AvocadoPanel.isCommandPeriod(key(".", [])))
        #expect(!AvocadoPanel.isCommandPeriod(key(",", .command)))
        #expect(!AvocadoPanel.isCommandPeriod(key(".", [.command, .shift])))
    }
}
