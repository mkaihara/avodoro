import Foundation
import Testing
@testable import Avodoro

/// WCAG AA requires a contrast ratio of at least 4.5 for small text.
struct PaletteTests {
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(hex >> 16) + 0.7152 * channel(hex >> 8) + 0.0722 * channel(hex)
    }

    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    @Test func textOnFleshPassesAA() {
        #expect(Self.contrast(Palette.Hex.textOnFlesh, Palette.Hex.fleshCenter) >= 4.5)
        #expect(Self.contrast(Palette.Hex.textOnFlesh, Palette.Hex.fleshEdge) >= 4.5)
    }

    @Test func textOnPitPassesAA() {
        #expect(Self.contrast(Palette.Hex.textOnPit, Palette.Hex.pit) >= 4.5)
        #expect(Self.contrast(Palette.Hex.textOnPit, Palette.Hex.pitHighlight) >= 4.5)
    }

    @Test func selectedChipPassesAA() {
        #expect(Self.contrast(Palette.Hex.fleshCenter, Palette.Hex.skin) >= 4.5)
    }
}
