import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class PanelController {
    private(set) var isVisible = false
    private(set) var size: AvocadoSize

    /// The SwiftUI `openSettings` action, captured from the panel's environment.
    @ObservationIgnored var openSettings: (() -> Void)?

    @ObservationIgnored private let engine: TimerEngine
    @ObservationIgnored private let logService: LogService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private lazy var panel: AvocadoPanel = makePanel()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(engine: TimerEngine, logService: LogService, defaults: UserDefaults = .standard) {
        self.engine = engine
        self.logService = logService
        self.defaults = defaults
        size = AvocadoSize(defaultsValue: defaults.string(forKey: AvocadoSize.defaultsKey))
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

    // MARK: Setup

    private func makePanel() -> AvocadoPanel {
        let panelSize = size.panelSize
        let panel = AvocadoPanel(contentRect: NSRect(origin: .zero, size: panelSize))
        let hostingView = FirstMouseHostingView(rootView: PanelContent(engine: engine, logService: logService, controller: self))
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = hostingView

        // Restores the saved frame if there is one; AppKit saves it after every move.
        panel.setFrameAutosaveName("AvocadoPanel")
        panel.setFrame(PanelPlacement.resized(panel.frame, to: panelSize, screens: Self.visibleFrames), display: false)
        moveOnScreenIfNeeded(panel)

        panel.contextMenuProvider = { [weak self] in self?.makeContextMenu() }
        panel.onCommandPeriod = { [weak self] in self?.engine.stop() }
        panel.contentSizeChanged()
        observe()
        return panel
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.moveOnScreenIfNeeded(self.panel)
            }
        })
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySizeFromDefaults() }
        })
    }

    // MARK: Position and size

    private static var visibleFrames: [CGRect] { NSScreen.screens.map(\.visibleFrame) }

    /// If the panel is not on any connected screen, put it at the bottom right of the main screen.
    private func moveOnScreenIfNeeded(_ panel: AvocadoPanel) {
        guard !PanelPlacement.isVisible(panel.frame, on: Self.visibleFrames),
              let main = NSScreen.main?.visibleFrame
        else { return }
        Log.app.info("Avocado was off-screen, moving it to the bottom right")
        panel.setFrameOrigin(PanelPlacement.defaultOrigin(size: panel.frame.size, mainVisibleFrame: main))
    }

    private func applySizeFromDefaults() {
        let newSize = AvocadoSize(defaultsValue: defaults.string(forKey: AvocadoSize.defaultsKey))
        guard newSize != size else { return }
        size = newSize
        let frame = PanelPlacement.resized(panel.frame, to: newSize.panelSize, screens: Self.visibleFrames)
        panel.setFrame(frame, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentSizeChanged()
    }

    // MARK: Context menu

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        switch engine.phase {
        case .idle:
            menu.addItem(ActionMenuItem("Start") { [engine] in engine.start() })
        case .running:
            menu.addItem(ActionMenuItem("Pause") { [engine] in engine.pause() })
            menu.addItem(ActionMenuItem("Stop") { [engine] in engine.stop() })
        case .paused:
            menu.addItem(ActionMenuItem("Resume") { [engine] in engine.resume() })
            menu.addItem(ActionMenuItem("Stop") { [engine] in engine.stop() })
        case .finishing:
            break
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(ActionMenuItem("Settings…") { [weak self] in
            // Menu bar apps otherwise tend to open Settings behind other windows.
            NSApp.activate()
            self?.openSettings?()
        })
        menu.addItem(ActionMenuItem("Hide avocado") { [weak self] in self?.hide() })
        return menu
    }
}

private struct PanelContent: View {
    let engine: TimerEngine
    let logService: LogService
    let controller: PanelController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        AvocadoView(engine: engine, warning: logService.warning, scale: controller.size.scale)
            .onAppear {
                controller.openSettings = { openSettings() }
            }
    }
}

/// The panel never activates the app, so the first click on a control must already count.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// An `NSMenuItem` that runs a closure.
@MainActor
private final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
