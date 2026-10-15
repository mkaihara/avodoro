import SwiftUI

/// Shown in the task band after a crash: log the unfinished session, or discard it.
struct RecoveryPrompt: View {
    let engine: TimerEngine
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 5 * scale) {
            // Explicit breaks: the flesh is narrow here, and every size should wrap the same way.
            Text("Unfinished session\nfrom \(engine.recoveredStartTime ?? "earlier").\nLog it or discard?")
                .font(.rounded(12 * scale))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12 * scale) {
                Button("Log it") { engine.logRecovered() }
                    .accessibilityLabel("Log the unfinished session")
                Button("Discard") { engine.discardRecovered() }
                    .accessibilityLabel("Discard the unfinished session")
            }
            .buttonStyle(.plain)
            .font(.rounded(12 * scale, .medium))
            .underline()
        }
        .foregroundStyle(Palette.textOnFlesh)
    }
}
