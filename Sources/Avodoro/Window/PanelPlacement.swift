import CoreGraphics

/// Where the panel goes. Pure geometry in AppKit screen coordinates (y up), so it is testable.
enum PanelPlacement {
    static let margin: CGFloat = 24
    /// A frame only counts as visible if at least this much of it is on one screen.
    static let minimumVisible = CGSize(width: 40, height: 40)

    static func isVisible(_ frame: CGRect, on screens: [CGRect]) -> Bool {
        screens.contains { screen in
            let overlap = screen.intersection(frame)
            return !overlap.isNull
                && overlap.width >= minimumVisible.width
                && overlap.height >= minimumVisible.height
        }
    }

    /// Bottom right of the main screen's visible frame.
    static func defaultOrigin(size: CGSize, mainVisibleFrame: CGRect) -> CGPoint {
        CGPoint(x: mainVisibleFrame.maxX - size.width - margin, y: mainVisibleFrame.minY + margin)
    }

    /// The frame resized to `size` around its centre, then moved inside the screen it is on.
    static func resized(_ frame: CGRect, to size: CGSize, screens: [CGRect]) -> CGRect {
        var result = CGRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = screens.first(where: { $0.contains(center) }) ?? screens.first else { return result }
        result.origin.x = min(max(result.minX, screen.minX), screen.maxX - size.width)
        result.origin.y = min(max(result.minY, screen.minY), screen.maxY - size.height)
        return result
    }
}
