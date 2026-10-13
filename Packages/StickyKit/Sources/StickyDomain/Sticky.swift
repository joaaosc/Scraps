import Foundation

/// A piece of text kept on a small floating window, like a paper note stuck to
/// the screen.
///
/// A sticky is a place to put a thought for now. Its title comes from its
/// first line, rather than a separate field that can drift from its contents.
public struct Sticky: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var text: String
    public let createdAt: Date
    public var updatedAt: Date
    /// Where its window was last left. Nil until a window places it.
    public var frame: StickyFrame?
    /// Whether the window stays above other apps' windows.
    public var floatsOnTop: Bool
    public var color: StickyColor
    public var isCollapsed: Bool
    public var appearsOnAllSpaces: Bool
    /// Nil for an active note. Recently deleted notes keep all their contents.
    public var deletedAt: Date?
    /// Portable emphasis runs, measured in UTF-16 offsets into `text`.
    public var richText: StickyRichText?

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        frame: StickyFrame? = nil,
        floatsOnTop: Bool = true,
        color: StickyColor = .clear,
        isCollapsed: Bool = false,
        appearsOnAllSpaces: Bool = false,
        deletedAt: Date? = nil,
        richText: StickyRichText? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.frame = frame
        self.floatsOnTop = floatsOnTop
        self.color = color
        self.isCollapsed = isCollapsed
        self.appearsOnAllSpaces = appearsOnAllSpaces
        self.deletedAt = deletedAt
        self.richText = richText?.normalized(for: text)
    }

    /// Replaces the text and moves `updatedAt` forward. `createdAt` never moves.
    public mutating func edit(text newText: String, at date: Date = Date()) {
        guard newText != text else { return }
        text = newText
        // Plain-text edits cannot safely reuse ranges into the previous text.
        richText = nil
        updatedAt = max(date, max(createdAt, updatedAt))
    }

    /// Updates text and its formatting together, including formatting-only edits.
    public mutating func edit(
        text newText: String,
        richText newRichText: StickyRichText?,
        at date: Date = Date()
    ) {
        let normalized = newRichText?.normalized(for: newText)
        guard newText != text || normalized != richText else { return }
        text = newText
        richText = normalized
        updatedAt = max(date, max(createdAt, updatedAt))
    }

    public var title: String {
        let firstLine = String(text.prefix { !$0.isNewline })
        let title = firstLine.trimmingCharacters(in: .whitespaces)
        return title.isEmpty
            ? NSLocalizedString("Untitled", bundle: .module, comment: "A note with a blank first line")
            : title
    }

    /// Whether there is nothing worth keeping, so closing needs no question.
    public var isEmpty: Bool {
        text.allSatisfy(\.isWhitespace)
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, createdAt, updatedAt, frame, floatsOnTop
        case color, isCollapsed, appearsOnAllSpaces, deletedAt, richText
    }

    /// Version-one notes predate color, formatting, collapse, Spaces and trash.
    /// Missing fields migrate in memory; the next successful save writes them.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        frame = try values.decodeIfPresent(StickyFrame.self, forKey: .frame)
        floatsOnTop = try values.decodeIfPresent(Bool.self, forKey: .floatsOnTop) ?? true
        color = try values.decodeIfPresent(StickyColor.self, forKey: .color) ?? .clear
        isCollapsed = try values.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        appearsOnAllSpaces = try values.decodeIfPresent(Bool.self, forKey: .appearsOnAllSpaces) ?? false
        deletedAt = try values.decodeIfPresent(Date.self, forKey: .deletedAt)
        richText = try values.decodeIfPresent(StickyRichText.self, forKey: .richText)?
            .normalized(for: text)
    }
}
