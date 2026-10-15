import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class PanelController {
    static let defaultSize = CGSize(width: 240, height: 320)
    private static let screenMargin: CGFloat = 24

    private(set) var isVisible = false
    @ObservationIgnored private lazy var panel: AvocadoPanel = makePanel()

    func show() {
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel.orderOut(nil)
        isVisible = false
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    private func makePanel() -> AvocadoPanel {
        let panel = AvocadoPanel(contentRect: NSRect(origin: .zero, size: Self.defaultSize))
        let hostingView = NSHostingView(rootView: AvocadoView())
        hostingView.frame = NSRect(origin: .zero, size: Self.defaultSize)
        panel.contentView = hostingView
        panel.setFrameOrigin(Self.bottomRightOrigin(for: Self.defaultSize))
        panel.contentSizeChanged()
        return panel
    }

    private static func bottomRightOrigin(for size: CGSize) -> NSPoint {
        guard let visible = NSScreen.main?.visibleFrame else { return .zero }
        return NSPoint(
            x: visible.maxX - size.width - screenMargin,
            y: visible.minY + screenMargin
        )
    }
}
