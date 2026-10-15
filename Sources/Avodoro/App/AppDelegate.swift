import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: SettingsStore
    let logService: LogService
    let engine: TimerEngine
    let panelController: PanelController
    let menuBarTicker: MenuBarTicker
    let completionAlerts: CompletionAlerts
    let sessionRecorder: SessionRecorder
    let systemEvents: SystemEvents
    private var isPoweringOff = false

    override init() {
        let settings = SettingsStore()
        let logService = LogService(folder: settings.logFolder)
        let engine = TimerEngine(clock: SystemClock(), configuration: settings.configuration) { day, entry in
            logService.write(day: day, entry: entry)
        }
        // A new folder also flushes the pending queue.
        settings.onLogFolderChange = { logService.setFolder($0) }
        settings.onConfigurationChange = { engine.configuration = $0 }
        self.settings = settings
        self.logService = logService
        self.engine = engine
        panelController = PanelController(engine: engine, logService: logService, settings: settings)
        menuBarTicker = MenuBarTicker(engine: engine)
        let completionAlerts = CompletionAlerts(settings: settings)
        engine.onComplete = { completionAlerts.sessionCompleted(type: $0, description: $1) }
        self.completionAlerts = completionAlerts

        // Attach the recorder before restoring, so a restored record is saved or cleared at once.
        let recoveryStore = RecoveryStore(fileURL: RecoveryStore.defaultURL)
        sessionRecorder = SessionRecorder(engine: engine, store: recoveryStore)
        if let record = recoveryStore.load() {
            Log.app.info("Found an unfinished session from a previous run")
            engine.restore(record)
        }
        systemEvents = SystemEvents(engine: engine)
        super.init()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isPoweringOff = true }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Launched")
        panelController.show()
    }

    /// Asks before quitting during a session, and waits until the line is written.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch engine.phase {
        case .running, .paused:
            if isPoweringOff {
                // Logging out or shutting down: a modal alert would block it.
                stopAndLog()
            } else {
                switch askStopAndLog() {
                case .alertFirstButtonReturn: stopAndLog()
                case .alertSecondButtonReturn: engine.discard()
                default: return .terminateCancel
                }
            }
        case .finishing:
            engine.skipEnergy()
        case .idle, .recovering:
            // Recovering: active-session.json stays, so the question comes back next launch.
            break
        }
        Task {
            await logService.waitForWrites()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func askStopAndLog() -> NSApplication.ModalResponse {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Stop and log this session?"
        alert.informativeText = "Quitting ends the running session."
        alert.addButton(withTitle: "Stop and log")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel") // also Escape
        return alert.runModal()
    }

    private func stopAndLog() {
        engine.stop()
        engine.skipEnergy()
    }
}
