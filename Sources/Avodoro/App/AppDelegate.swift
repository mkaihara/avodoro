import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panelController = PanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Launched")
        panelController.show()
    }
}
