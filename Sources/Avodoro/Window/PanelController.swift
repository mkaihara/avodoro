import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class PanelController {
    private static let screenMargin: CGFloat = 24

    private(set) var isVisible = false
    @ObservationIgnored private let engine: TimerEngine
    @ObservationIgnored private let logService: LogService
    @ObservationIgnored private lazy var panel: AvocadoPanel = makePanel()

    init(engine: TimerEngine, logService: LogService) {
        self.engine = engine
        self.logService = logService
    }

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
        let size = AvocadoView.baseSize
        let panel = AvocadoPanel(contentRect: NSRect(origin: .zero, size: size))
        let hostingView = FirstMouseHostingView(rootView: PanelContent(engine: engine, logService: logService))
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView
        panel.setFrameOrigin(Self.bottomRightOrigin(for: size))
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

private struct PanelContent: View {
    let engine: TimerEngine
    let logService: LogService

    var body: some View {
        AvocadoView(engine: engine, warning: logService.warning)
    }
}

/// The panel never activates the app, so the first click on a control must already count.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
