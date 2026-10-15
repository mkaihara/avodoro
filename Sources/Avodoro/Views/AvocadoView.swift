import SwiftUI

extension EnvironmentValues {
    /// True when rendered by `ImageRenderer`, which cannot draw AppKit-backed views.
    @Entry var isSnapshot = false
}

/// Milestone 1 placeholder: an oval with skin and flesh so the panel is visible and draggable.
/// The real `AvocadoShape` replaces the ellipses in milestone 4.
struct AvocadoView: View {
    /// Skin thickness as a fraction of the width.
    static let skinFraction: CGFloat = 0.07

    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        GeometryReader { geometry in
            let inset = geometry.size.width * Self.skinFraction
            ZStack {
                Ellipse()
                    .fill(Palette.skin)
                if !isSnapshot {
                    DragHandle(hitArea: Self.isOnSkin)
                }
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Palette.fleshCenter, Palette.fleshEdge],
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.height / 2
                        )
                    )
                    .padding(inset)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: PanelController.defaultSize.width, height: PanelController.defaultSize.height)
    }

    /// True for points inside the outer ellipse but outside the inset flesh ellipse.
    static func isOnSkin(_ point: CGPoint, in size: CGSize) -> Bool {
        let inset = size.width * skinFraction
        let outer = CGRect(origin: .zero, size: size)
        return ellipse(outer, contains: point)
            && !ellipse(outer.insetBy(dx: inset, dy: inset), contains: point)
    }

    private static func ellipse(_ rect: CGRect, contains point: CGPoint) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        let dx = (point.x - rect.midX) / (rect.width / 2)
        let dy = (point.y - rect.midY) / (rect.height / 2)
        return dx * dx + dy * dy <= 1
    }
}
