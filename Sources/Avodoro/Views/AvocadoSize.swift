import CoreGraphics

enum AvocadoSize: String, CaseIterable, Sendable {
    case small, medium, large

    /// `UserDefaults` key; the Settings window writes it.
    static let defaultsKey = "avocadoSize"

    var scale: CGFloat {
        switch self {
        case .small: 0.8
        case .medium: 1
        case .large: 1.25
        }
    }

    var panelSize: CGSize {
        CGSize(width: AvocadoView.baseSize.width * scale, height: AvocadoView.baseSize.height * scale)
    }

    init(defaultsValue: String?) {
        self = defaultsValue.flatMap(AvocadoSize.init(rawValue:)) ?? .medium
    }
}
