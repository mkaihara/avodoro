import SwiftUI

/// Shown in the task band after a focus session: rate energy 1 to 5, or skip.
struct EnergyPicker: View {
    let engine: TimerEngine
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 3 * scale) {
            Text("How was your energy?")
                .font(.rounded(12 * scale))

            HStack(spacing: 4 * scale) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        engine.rate(energy: level)
                    } label: {
                        Text("\(level)")
                            .font(.rounded(12 * scale, .medium))
                            .frame(width: 18 * scale, height: 18 * scale)
                            .background(Circle().stroke(Palette.textOnFlesh.opacity(0.6), lineWidth: 1))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Energy \(level) of 5")
                }
            }

            Button("Skip") {
                engine.skipEnergy()
            }
            .buttonStyle(.plain)
            .font(.rounded(12 * scale))
            .underline()
            .accessibilityLabel("Skip energy rating")
        }
        .foregroundStyle(Palette.textOnFlesh)
    }
}
