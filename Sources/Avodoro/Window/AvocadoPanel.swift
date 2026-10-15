import AppKit

/// Borderless, transparent panel that floats above other apps without activating Avodoro.
final class AvocadoPanel: NSPanel {
    /// Builds the right-click menu. Shown for a right click or control-click anywhere in the panel.
    var contextMenuProvider: (() -> NSMenu?)?
    /// `⌘.` while the panel is key.
    var onCommandPeriod: (() -> Void)?

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

    // Handled at window level so the skin's drag view and SwiftUI controls can't swallow it.
    override func sendEvent(_ event: NSEvent) {
        let isControlClick = event.type == .leftMouseDown
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control
        if event.type == .rightMouseDown || isControlClick,
           let menu = contextMenuProvider?(), let contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: contentView)
            return
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isCommandPeriod(event), let onCommandPeriod {
            onCommandPeriod()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    static func isCommandPeriod(_ event: NSEvent) -> Bool {
        event.type == .keyDown
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            && event.charactersIgnoringModifiers == "."
    }
}
