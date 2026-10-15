import AppKit
import SwiftUI

extension EnvironmentValues {
    /// True when rendered by `ImageRenderer`, which cannot draw AppKit-backed views.
    @Entry var isSnapshot = false
}

/// The floating avocado. Thin: it reads `TimerEngine` and calls its methods.
struct AvocadoView: View {
    nonisolated static let baseSize = CGSize(width: 240, height: 320)
    static let presets = [5, 10, 15, 20]

    @Bindable var engine: TimerEngine
    var warning: String?
    var scale: CGFloat = 1

    @Environment(\.isSnapshot) private var isSnapshot
    /// The warning reason is drawn in the panel: system tooltips don't show while the app is
    /// inactive, and the panel never activates the app.
    @State var showsWarningReason = false
    @FocusState private var taskFieldFocused: Bool

    private var width: CGFloat { Self.baseSize.width * scale }
    private var height: CGFloat { Self.baseSize.height * scale }

    var body: some View {
        if isSnapshot {
            content(now: engine.now)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                content(now: engine.now)
            }
        }
    }

    private func content(now: Date) -> some View {
        ZStack(alignment: .topLeading) {
            fruit
            if !isSnapshot {
                DragHandle(hitArea: AvocadoShape.skinContains)
            }

            modeLabel
                .position(x: width * 0.5, y: height * 0.17)

            if engine.phase == .idle {
                presetChips
                    .position(x: width * 0.5, y: height * 0.285)
            }

            if engine.phase == .finishing {
                // Lower than the task band: the flesh is too narrow for the question higher up.
                EnergyPicker(engine: engine, scale: scale)
                    .position(x: width * 0.5, y: height * 0.43)
            } else {
                taskField
                    .frame(width: width * 0.5, height: height * 0.14)
                    .position(x: width * 0.5, y: height * 0.43)
            }

            PitView(engine: engine, now: now, scale: scale, diameter: width * 0.40)
                .position(x: width * 0.5, y: height * 0.70)

            if let warning {
                warningDot(warning)
                    .position(x: width * 0.645, y: height * 0.105)
                if showsWarningReason {
                    warningBubble(warning)
                        // Whole points keep the 1 pt border on whole pixels.
                        .position(x: (width * 0.5).rounded(), y: (height * 0.43).rounded()) // over the task band

                }
            }
        }
        .frame(width: width, height: height)
        .foregroundStyle(Palette.textOnFlesh)
        // The avocado is an object with fixed colors; keep system controls (caret, text) dark on it.
        .environment(\.colorScheme, .light)
    }

    // MARK: Parts

    /// Flesh with a radial gradient, and a skin band of uniform width along the outline.
    private var fruit: some View {
        ZStack {
            AvocadoShape()
                .fill(
                    RadialGradient(
                        colors: [Palette.fleshCenter, Palette.fleshEdge],
                        center: UnitPoint(x: 0.5, y: 0.6),
                        startRadius: 0,
                        endRadius: height * 0.5
                    )
                )
            AvocadoShape()
                .stroke(Palette.skin, lineWidth: 2 * AvocadoShape.skinFraction * width)
                .clipShape(AvocadoShape())
        }
        .frame(width: width, height: height)
    }

    private var displayedType: SessionType {
        engine.session?.type ?? engine.finishing?.entry.type ?? engine.selectedType
    }

    private var modeLabel: some View {
        Button {
            engine.select(type: displayedType == .focus ? .break : .focus)
        } label: {
            Text(displayedType == .focus ? "Focus" : "Break")
                .font(.rounded(12 * scale, .medium))
                .padding(.horizontal, 6 * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(engine.phase == .idle) // not .disabled: dimming would hurt contrast
        .accessibilityLabel(displayedType == .focus ? "Focus" : "Break")
        .accessibilityHint(engine.phase == .idle ? "Switches between focus and break" : "")
    }

    private var presetChips: some View {
        HStack(spacing: 3 * scale) {
            ForEach(Self.presets, id: \.self) { minutes in
                let selected = minutes == engine.selectedMinutes
                Button {
                    engine.select(minutes: minutes)
                } label: {
                    Text("\(minutes)")
                        .font(.rounded(12 * scale, .medium).monospacedDigit())
                        .foregroundStyle(selected ? Palette.fleshCenter : Palette.textOnFlesh)
                        .frame(minWidth: 18 * scale, minHeight: 18 * scale)
                        .padding(.horizontal, 1 * scale)
                        .background(Capsule().fill(selected ? Palette.skin : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(minutes) minutes")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private var taskField: some View {
        if isSnapshot {
            // ImageRenderer cannot draw the AppKit-backed TextField.
            Text(engine.taskText.isEmpty ? "What are you doing?" : engine.taskText)
                .font(.rounded(12 * scale))
                .opacity(engine.taskText.isEmpty ? 0.6 : 1)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        } else {
            // Our own placeholder: the system one is nearly white in dark mode.
            // Empty title: macOS draws a TextField's title as a placeholder.
            TextField("", text: $engine.taskText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.rounded(12 * scale))
                .multilineTextAlignment(.center)
                .lineLimit(1...2)
                .background(alignment: .center) {
                    if engine.taskText.isEmpty {
                        Text("What are you doing?")
                            .font(.rounded(12 * scale))
                            .opacity(0.6)
                            .allowsHitTesting(false)
                    }
                }
                .focused($taskFieldFocused)
                .onSubmit {
                    if engine.phase == .idle { engine.start() }
                }
                .onChange(of: taskFieldFocused) { _, focused in
                    guard focused, engine.consumeTaskTextSelection() else { return }
                    // After the click has placed the caret, select everything so typing replaces it.
                    DispatchQueue.main.async {
                        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    }
                }
                .onChange(of: engine.phase) { old, new in
                    // Once a session starts, stray keys should not keep editing the task.
                    if old == .idle && new == .running { taskFieldFocused = false }
                }
                .accessibilityLabel("Task")
        }
    }

    private func warningDot(_ reason: String) -> some View {
        Circle()
            .fill(Palette.warning)
            .frame(width: 9 * scale, height: 9 * scale)
            .padding(4 * scale) // larger hover target
            .contentShape(Circle())
            .onHover { showsWarningReason = $0 }
            .onTapGesture { showsWarningReason.toggle() }
            .accessibilityElement()
            .accessibilityLabel(reason)
            .accessibilityAddTraits(.isButton)
    }

    private func warningBubble(_ reason: String) -> some View {
        EvenSize {
            Text(reason)
                .font(.rounded(11 * scale, .medium))
                .foregroundStyle(Palette.textOnFlesh)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8 * scale)
                .padding(.vertical, 6 * scale)
                .frame(width: (width * 0.56).rounded())
        }
        .background {
            RoundedRectangle(cornerRadius: 8 * scale)
                .fill(Palette.fleshCenter)
                .strokeBorder(Palette.warning, lineWidth: 1)
        }
        .onTapGesture { showsWarningReason = false }
        .accessibilityHidden(true) // the dot already carries the reason
    }
}

/// Rounds its content's size up to even whole points, so a centered frame's edges land on
/// whole pixels and thin borders stay the same width all around.
private struct EvenSize: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let size = subviews.first?.sizeThatFits(proposal) else { return .zero }
        return CGSize(width: (size.width / 2).rounded(.up) * 2, height: (size.height / 2).rounded(.up) * 2)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                              proposal: ProposedViewSize(bounds.size))
    }
}
