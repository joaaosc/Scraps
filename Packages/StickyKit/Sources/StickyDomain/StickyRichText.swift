import Foundation

/// The emphasis supported by Scraps, independent of AppKit or UIKit archives.
/// The note's plain text remains the single source of truth for its contents.
public struct StickyRichText: Codable, Equatable, Sendable {
    public var runs: [StickyTextRun]

    public init(runs: [StickyTextRun] = []) {
        self.runs = runs
    }

    /// Drops stale or malformed ranges without changing the note's text.
    /// UTF-16 offsets match NSAttributedString on both native platforms.
    public func normalized(for text: String) -> StickyRichText {
        let units = Array(text.utf16)
        func isBoundary(_ offset: Int) -> Bool {
            guard offset > 0, offset < units.count else { return true }
            return !(0xD800...0xDBFF).contains(units[offset - 1])
                || !(0xDC00...0xDFFF).contains(units[offset])
        }
        let valid = runs.filter { run in
            guard run.location >= 0, run.length > 0,
                  run.location <= units.count,
                  run.length <= units.count - run.location,
                  run.hasFormatting else { return false }
            return isBoundary(run.location) && isBoundary(run.location + run.length)
        }
        let boundaries = valid.enumerated().flatMap { index, run in
            [(run.location, index, true), (run.location + run.length, index, false)]
        }.sorted { $0.0 < $1.0 }
        var result: [StickyTextRun] = []
        var active = Set<Int>()
        var index = 0
        while index < boundaries.count {
            let location = boundaries[index].0
            while index < boundaries.count, boundaries[index].0 == location {
                let event = boundaries[index]
                if event.2 { active.insert(event.1) } else { active.remove(event.1) }
                index += 1
            }
            guard index < boundaries.count, !active.isEmpty else { continue }
            let styles = active.sorted().map { valid[$0] }
            let value = StickyTextRun(
                location: location, length: boundaries[index].0 - location,
                bold: styles.contains { $0.bold }, italic: styles.contains { $0.italic },
                underline: styles.contains { $0.underline }, strikethrough: styles.contains { $0.strikethrough },
                highlight: styles.contains { $0.highlight },
                style: styles.last(where: { $0.style != .body })?.style ?? .body,
                link: styles.compactMap(\.link).last
            )
            if let previous = result.last, previous.location + previous.length == location,
               previous.sameAttributes(as: value) {
                result[result.count - 1].length += value.length
            } else { result.append(value) }
        }
        return StickyRichText(runs: result)
    }
}

public struct StickyTextRun: Codable, Equatable, Sendable {
    public var location: Int
    public var length: Int
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var strikethrough: Bool
    public var highlight: Bool
    public var style: StickyTextStyle
    public var link: URL?

    public init(location: Int, length: Int, bold: Bool = false, italic: Bool = false,
                underline: Bool = false, strikethrough: Bool = false, highlight: Bool = false,
                style: StickyTextStyle = .body, link: URL? = nil) {
        self.location = location
        self.length = length
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.highlight = highlight
        self.style = style
        self.link = Self.safeLink(link)
    }

    public var hasFormatting: Bool {
        bold || italic || underline || strikethrough || highlight || style != .body || link != nil
    }

    func sameAttributes(as other: StickyTextRun) -> Bool {
        bold == other.bold && italic == other.italic && underline == other.underline
            && strikethrough == other.strikethrough && highlight == other.highlight
            && style == other.style && link == other.link
    }

    public static func safeLink(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(), ["https", "http", "mailto", "tel"].contains(scheme) else { return nil }
        if scheme == "https" || scheme == "http" { return url.host?.isEmpty == false ? url : nil }
        return url
    }

    private enum CodingKeys: String, CodingKey {
        case location, length, bold, italic, underline, strikethrough, highlight, style, link
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        location = try values.decode(Int.self, forKey: .location)
        length = try values.decode(Int.self, forKey: .length)
        bold = try values.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try values.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        underline = try values.decodeIfPresent(Bool.self, forKey: .underline) ?? false
        strikethrough = try values.decodeIfPresent(Bool.self, forKey: .strikethrough) ?? false
        highlight = try values.decodeIfPresent(Bool.self, forKey: .highlight) ?? false
        style = (try? values.decodeIfPresent(StickyTextStyle.self, forKey: .style)) ?? .body
        link = Self.safeLink(try? values.decodeIfPresent(URL.self, forKey: .link))
    }
}
