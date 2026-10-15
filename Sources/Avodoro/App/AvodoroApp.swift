import AppKit
import SwiftUI

@main
struct AvodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(
                panel: appDelegate.panelController,
                engine: appDelegate.engine,
                logService: appDelegate.logService
            )
        } label: {
            MenuBarLabel(engine: appDelegate.engine, ticker: appDelegate.menuBarTicker)
        }

        Settings {
            SettingsView()
        }
    }
}

/// The leaf, or the remaining time while a session runs.
///
/// Not a `TimelineView`: inside a `MenuBarExtra` label it puts SwiftUI into an endless
/// update loop at launch (main thread at 100 %, seen on macOS 27). `MenuBarTicker` redraws instead.
private struct MenuBarLabel: View {
    let engine: TimerEngine
    let ticker: MenuBarTicker

    var body: some View {
        let _ = ticker.now // redraw on every tick; the value itself comes from the engine's clock
        switch engine.phase {
        case .running, .paused:
            Text(Countdown.string(engine.remaining(at: engine.now)))
                .monospacedDigit()
        case .idle, .finishing:
            Image(systemName: "leaf.fill")
        }
    }
}

private struct MenuContent: View {
    let panel: PanelController
    let engine: TimerEngine
    let logService: LogService
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(panel.isVisible ? "Hide avocado" : "Show avocado") {
            panel.toggle()
        }

        Divider()

        switch engine.phase {
        case .idle, .finishing:
            Button("Start") { engine.start() }
        case .running:
            Button("Pause") { engine.pause() }
            Button("Stop") { engine.stop() }
        case .paused:
            Button("Resume") { engine.resume() }
            Button("Stop") { engine.stop() }
        }

        Divider()

        Button("Open today's log") { openTodayLog() }
            .disabled(logService.folder == nil)

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

    /// Opens the file in Obsidian; if that fails, reveals it (or the folder) in Finder.
    private func openTodayLog() {
        guard let file = logService.todayLogURL, let folder = logService.folder else { return }
        let exists = FileManager.default.fileExists(atPath: file.path)

        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        if exists,
           let encoded = file.path.addingPercentEncoding(withAllowedCharacters: allowed),
           let url = URL(string: "obsidian://open?path=\(encoded)"),
           NSWorkspace.shared.open(url) {
            return
        }
        Log.app.info("Obsidian did not open today's log, revealing it in Finder")
        NSWorkspace.shared.activateFileViewerSelecting([exists ? file : folder])
    }
}
