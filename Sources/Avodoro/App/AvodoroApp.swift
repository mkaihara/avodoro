import SwiftUI

@main
struct AvodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Avodoro", systemImage: "leaf.fill") {
            MenuContent(panel: appDelegate.panelController)
        }

        Settings {
            SettingsView()
        }
    }
}

private struct MenuContent: View {
    let panel: PanelController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(panel.isVisible ? "Hide avocado" : "Show avocado") {
            panel.toggle()
        }

        Divider()

        Button("Settings…") {
            // Menu bar apps otherwise tend to open Settings behind other windows.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
