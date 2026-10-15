import SwiftUI

enum Palette {
    static let skin = Color(hex: 0x34461C)
    static let fleshEdge = Color(hex: 0x9BBE45)
    static let fleshCenter = Color(hex: 0xE4ECA0)
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
