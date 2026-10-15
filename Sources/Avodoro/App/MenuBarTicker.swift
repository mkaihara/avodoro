import Foundation
import Observation

/// Publishes the time once per second while a session runs, so the menu bar countdown redraws.
@MainActor
@Observable
final class MenuBarTicker {
    private(set) var now = Date()
    @ObservationIgnored private var timer: Timer?

    init(engine: TimerEngine) {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self, weak engine] _ in
            MainActor.assumeIsolated {
                // Idle and finishing show the leaf; don't redraw it every second.
                guard let self, let engine, engine.phase == .running else { return }
                self.now = engine.now
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
