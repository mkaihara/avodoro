import CoreGraphics
import SwiftUI

/// A halved avocado seen from the front, as one closed path in a normalized 0…1 frame (y down).
struct AvocadoShape: Shape {
    /// Skin thickness as a fraction of the width.
    static let skinFraction: CGFloat = 0.06

    func path(in rect: CGRect) -> Path {
        Path(Self.cgPath(in: rect))
    }

    static func cgPath(in rect: CGRect) -> CGPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let path = CGMutablePath()
        path.move(to: point(0.50, 0.00))
        // Right shoulder.
        path.addCurve(to: point(0.85, 0.42), control1: point(0.70, 0.00), control2: point(0.77, 0.24))
        // Right belly to bottom.
        path.addCurve(to: point(0.50, 1.00), control1: point(1.01, 0.78), control2: point(0.95, 1.00))
        // Left belly.
        path.addCurve(to: point(0.15, 0.42), control1: point(0.05, 1.00), control2: point(-0.01, 0.78))
        // Left shoulder.
        path.addCurve(to: point(0.50, 0.00), control1: point(0.23, 0.24), control2: point(0.30, 0.00))
        path.closeSubpath()
        return path
    }

    /// True for points on the skin band: inside the outline and within the skin width of it.
    /// `point` is in the coordinates of a frame of `size`, y down.
    static func skinContains(_ point: CGPoint, in size: CGSize) -> Bool {
        let outline = cgPath(in: CGRect(origin: .zero, size: size))
        guard outline.contains(point) else { return false }
        let band = outline.copy(
            strokingWithWidth: 2 * skinFraction * size.width,
            lineCap: .butt, lineJoin: .round, miterLimit: 10
        )
        return band.contains(point)
    }
}
