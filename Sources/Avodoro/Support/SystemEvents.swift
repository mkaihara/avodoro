import AppKit

/// Pauses a running session when the Mac sleeps or the screen locks. Never resumes.
///
/// `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` are undocumented distributed
/// notifications. If they stop arriving, report it; don't build a workaround.
@MainActor
final class SystemEvents {
    private let engine: TimerEngine
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(engine: TimerEngine) {
        self.engine = engine

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Log.app.info("Will sleep")
                self?.engine.systemWillSleep()
            }
        }))

        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Log.app.info("Screen locked")
                self?.engine.screenDidLock()
            }
        }))
        observers.append((distributed, distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { _ in
            Log.app.info("Screen unlocked")
        }))
    }
}
