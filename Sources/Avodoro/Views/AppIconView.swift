import SwiftUI

/// The app icon, drawn with the avocado's own shape and palette. Rendered to the asset catalog by
/// `AppIconTests` (`make icon`), never shown at runtime.
///
/// Follows the macOS icon grid: a 1024 pt canvas with an 824 pt rounded tile in the middle.
struct AppIconView: View {
    static let canvas: CGFloat = 1024
    private static let tile: CGFloat = 824

    var body: some View {
        let tile = Self.tile
        let avocadoHeight = tile * 0.80
        let avocadoWidth = avocadoHeight * 0.75 // the floating avocado's 240 × 320 proportions
        let pitDiameter = avocadoWidth * 0.40

        ZStack {
            RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(hex: 0xFBF6E6), Color(hex: 0xEADDBD)],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: tile, height: tile)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 10)

            ZStack {
                AvocadoShape()
                    .fill(RadialGradient(
                        colors: [Palette.fleshCenter, Palette.fleshEdge],
                        center: UnitPoint(x: 0.5, y: 0.6),
                        startRadius: 0,
                        endRadius: avocadoHeight * 0.5
                    ))
                AvocadoShape()
                    .stroke(Palette.skin, lineWidth: 2 * AvocadoShape.skinFraction * avocadoWidth)
                    .clipShape(AvocadoShape())
                Circle()
                    .fill(RadialGradient(
                        colors: [Palette.pitHighlight, Palette.pit],
                        center: UnitPoint(x: 0.32, y: 0.28),
                        startRadius: 0,
                        endRadius: pitDiameter * 0.55
                    ))
                    .frame(width: pitDiameter, height: pitDiameter)
                    .position(x: avocadoWidth * 0.5, y: avocadoHeight * 0.70)
            }
            .frame(width: avocadoWidth, height: avocadoHeight)
            .shadow(color: Palette.skin.opacity(0.35), radius: 10, y: 8)
        }
        .frame(width: Self.canvas, height: Self.canvas)
    }
}
