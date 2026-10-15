import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: SettingsStore
    let logService: LogService
    let engine: TimerEngine
    let panelController: PanelController
    let menuBarTicker: MenuBarTicker
    let completionAlerts: CompletionAlerts

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
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Launched")
        panelController.show()
    }
}
