import SwiftUI

/// The avocado keeps these colors in light and dark mode: it is an object, not a UI surface.
enum Palette {
    enum Hex {
        static let skin: UInt32 = 0x34461C
        static let fleshEdge: UInt32 = 0x9BBE45
        static let fleshCenter: UInt32 = 0xE4ECA0
        static let ring: UInt32 = 0x5E7F2A
        static let pit: UInt32 = 0x6B4226
        static let pitHighlight: UInt32 = 0x8C5B35
        static let textOnFlesh: UInt32 = 0x2C3A12
        static let textOnPit: UInt32 = 0xF2E6CF
        static let warning: UInt32 = 0xB5432A
    }

    static let skin = Color(hex: Hex.skin)
    static let fleshEdge = Color(hex: Hex.fleshEdge)
    static let fleshCenter = Color(hex: Hex.fleshCenter)
    static let ring = Color(hex: Hex.ring)
    static let pit = Color(hex: Hex.pit)
    static let pitHighlight = Color(hex: Hex.pitHighlight)
    static let textOnFlesh = Color(hex: Hex.textOnFlesh)
    static let textOnPit = Color(hex: Hex.textOnPit)
    static let warning = Color(hex: Hex.warning)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Font {
    /// SF Pro Rounded, used everywhere on the avocado.
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
