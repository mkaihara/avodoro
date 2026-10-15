import SwiftUI

/// Shown in the task band after a focus session: rate energy 1 to 5, or skip.
struct EnergyPicker: View {
    let engine: TimerEngine
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 4 * scale) {
            Text("How was your energy?")
                .font(.rounded(12 * scale))

            // Skip shares the row with the ratings so it stays clear of the pit below.
            HStack(spacing: 3 * scale) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        engine.rate(energy: level)
                    } label: {
                        Text("\(level)")
                            .font(.rounded(12 * scale, .medium))
                            .frame(width: 17 * scale, height: 17 * scale)
                            .background(Circle().stroke(Palette.textOnFlesh.opacity(0.6), lineWidth: 1))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Energy \(level) of 5")
                }

                Button("Skip") {
                    engine.skipEnergy()
                }
                .buttonStyle(.plain)
                .font(.rounded(12 * scale))
                .underline()
                .padding(.leading, 5 * scale)
                .accessibilityLabel("Skip energy rating")
            }
        }
        .foregroundStyle(Palette.textOnFlesh)
    }
}
