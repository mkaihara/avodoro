import AppKit
import SwiftUI

/// Drags the panel when the mouse goes down on the avocado's skin.
///
/// Why this instead of `isMovableByWindowBackground`: SwiftUI content inside `NSHostingView`
/// does not reliably report `mouseDownCanMoveWindow`, so background dragging either does
/// nothing or competes with the controls inside the fruit. An explicit AppKit view that only
/// claims hits on the skin band (via `hitArea`) keeps dragging on the skin and leaves every
/// click inside the flesh to SwiftUI.
struct DragHandle: NSViewRepresentable {
    /// Returns true for points (in the view's own coordinates, y down) that should start a drag.
    let hitArea: @MainActor (CGPoint, CGSize) -> Bool

    func makeNSView(context: Context) -> DragHandleNSView {
        DragHandleNSView(hitArea: hitArea)
    }

    func updateNSView(_ nsView: DragHandleNSView, context: Context) {
        nsView.hitArea = hitArea
    }
}

final class DragHandleNSView: NSView {
    var hitArea: @MainActor (CGPoint, CGSize) -> Bool

    init(hitArea: @escaping @MainActor (CGPoint, CGSize) -> Bool) {
        self.hitArea = hitArea
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    // The panel never activates the app, so the first click must already start the drag.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return hitArea(local, bounds.size) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
