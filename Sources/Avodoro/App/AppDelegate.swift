import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let logService: LogService
    let engine: TimerEngine
    let panelController: PanelController
    let menuBarTicker: MenuBarTicker

    override init() {
        let logService = LogService(folder: LogService.folderFromDefaults())
        let engine = TimerEngine(clock: SystemClock()) { day, entry in
            logService.write(day: day, entry: entry)
        }
        self.logService = logService
        self.engine = engine
        panelController = PanelController(engine: engine, logService: logService)
        menuBarTicker = MenuBarTicker(engine: engine)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Launched")
        panelController.show()
    }
}
