import AppKit

/// Borderless, transparent panel that floats above other apps without activating Avodoro.
final class AvocadoPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
    }

    // Borderless windows refuse key status by default; the task field needs keyboard input.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Call whenever the content changes size, otherwise the shadow keeps the old outline.
    func contentSizeChanged() {
        invalidateShadow()
    }
}
