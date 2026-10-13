import Foundation

/// Where a sticky's window sits on screen, in screen coordinates.
///
/// Plain numbers rather than `CGRect`: the domain does not import AppKit, and
/// the file the frame is stored in should not depend on how a framework
/// chooses to encode a rectangle.
public struct StickyFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
