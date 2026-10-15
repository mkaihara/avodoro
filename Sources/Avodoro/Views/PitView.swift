import SwiftUI

enum Countdown {
    /// `mm:ss`, rounding up so a fresh session shows its full length and the last second shows 00:01.
    static func string(_ remaining: TimeInterval) -> String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// The pit with the countdown, and the progress ring around it.
struct PitView: View {
    let engine: TimerEngine
    let now: Date
    let scale: CGFloat
    /// Pit diameter in points.
    let diameter: CGFloat

    private var ringWidth: CGFloat { 6 * scale }
    private var ringGap: CGFloat { 4 * scale }

    var body: some View {
        Button(action: tap) {
            ZStack {
                Circle()
                    .trim(from: 0, to: engine.progress(at: now))
                    .stroke(Palette.ring, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: diameter + 2 * ringGap + ringWidth, height: diameter + 2 * ringGap + ringWidth)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Palette.pitHighlight, Palette.pit],
                            center: UnitPoint(x: 0.32, y: 0.28),
                            startRadius: 0,
                            endRadius: diameter * 0.55
                        )
                    )
                    .frame(width: diameter, height: diameter)

                content
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder private var content: some View {
        switch engine.phase {
        case .finishing:
            Image(systemName: "checkmark")
                .font(.rounded(26 * scale, .semibold))
                .foregroundStyle(Palette.textOnPit)
        case .paused:
            VStack(spacing: 2 * scale) {
                countdown.opacity(0.5)
                Image(systemName: "pause.fill")
                    .font(.rounded(10 * scale))
                    .foregroundStyle(Palette.textOnPit)
            }
            .offset(y: 7 * scale) // keeps the digits where they sit while running
        case .idle, .running:
            countdown
        }
    }

    private var countdown: some View {
        Text(Countdown.string(engine.remaining(at: now)))
            .font(.rounded(26 * scale, .semibold).monospacedDigit())
            .foregroundStyle(Palette.textOnPit)
    }

    private func tap() {
        switch engine.phase {
        case .idle: engine.start()
        case .running, .paused: engine.togglePause()
        case .finishing: break
        }
    }

    private var accessibilityLabel: String {
        switch engine.phase {
        case .idle:
            let kind = engine.selectedType == .focus ? "focus" : "break"
            return "Start \(engine.selectedMinutes) minute \(kind) session"
        case .running: return "Pause"
        case .paused: return "Resume"
        case .finishing: return "Session finished"
        }
    }
}
