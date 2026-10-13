import Foundation

/// A piece of text kept on a small floating window, like a paper note stuck to
/// the screen.
///
/// Deliberately bare: no title, folder or tag. A sticky is a place to put a
/// thought for now; anything worth keeping can be sent to Apple Notes.
public struct Sticky: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var text: String
    public let createdAt: Date
    public var updatedAt: Date
    /// Where its window was last left. Nil until a window places it.
    public var frame: StickyFrame?
    /// Whether the window stays above other apps' windows.
    public var floatsOnTop: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        frame: StickyFrame? = nil,
        floatsOnTop: Bool = true
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.frame = frame
        self.floatsOnTop = floatsOnTop
    }

    /// Replaces the text and moves `updatedAt` forward. `createdAt` never moves.
    public mutating func edit(text newText: String, at date: Date = Date()) {
        guard newText != text else { return }
        text = newText
        updatedAt = max(date, createdAt)
    }

    /// Whether there is nothing worth keeping, so closing needs no question.
    public var isEmpty: Bool {
        text.allSatisfy(\.isWhitespace)
    }
}
