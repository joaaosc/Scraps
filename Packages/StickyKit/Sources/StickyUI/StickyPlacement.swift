import CoreGraphics
import StickyDomain

/// Where a sticky's window goes, and how small it may get.
///
/// Pure geometry, so the cascade and the "was left on a screen that is gone"
/// rule can be tested without a display.
enum StickyPlacement {
    static let defaultSize = CGSize(width: 260, height: 200)
    static let minimumSize = CGSize(width: 180, height: 120)

    private static let cascadeStep: CGFloat = 24
    private static let cascadeSlots = 10
    private static let screenMargin: CGFloat = 60
    /// How much of a stored frame must still be on a screen for it to count as
    /// reachable: enough to see it and grab it.
    private static let reachableExtent: CGFloat = 60

    /// The frame to open a sticky at.
    ///
    /// - Parameters:
    ///   - stored: where the person left it, if they ever did.
    ///   - visibleFrames: the usable area of each screen, the main one first.
    ///   - cascadeSlot: how many stickies are already open, so a new one does
    ///     not land exactly on top of another.
    static func frame(
        stored: StickyFrame?,
        visibleFrames: [CGRect],
        cascadeSlot: Int
    ) -> CGRect {
        let size = stored.map {
            CGSize(
                width: max(CGFloat($0.width), minimumSize.width),
                height: max(CGFloat($0.height), minimumSize.height)
            )
        } ?? defaultSize

        if let stored {
            let rect = CGRect(origin: CGPoint(x: stored.x, y: stored.y), size: size)
            let isReachable = visibleFrames.contains { screen in
                let overlap = screen.intersection(rect)
                return overlap.width >= reachableExtent && overlap.height >= reachableExtent
            }
            if isReachable { return rect }
        }

        let area = visibleFrames.first ?? CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let slot = CGFloat(max(0, cascadeSlot) % cascadeSlots)
        let x = min(
            area.minX + screenMargin + cascadeStep * slot,
            max(area.minX, area.maxX - size.width)
        )
        let y = max(
            area.maxY - screenMargin - size.height - cascadeStep * slot,
            area.minY
        )
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
