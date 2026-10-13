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
                  run.bold || run.italic else { return false }
            return isBoundary(run.location) && isBoundary(run.location + run.length)
        }
        // Imported attributes can overlap. Combine their emphasis instead of
        // allowing the last run to replace a previously applied style.
        let boundaries = valid.flatMap { run in
            [(run.location, run.bold ? 1 : 0, run.italic ? 1 : 0),
             (run.location + run.length, run.bold ? -1 : 0, run.italic ? -1 : 0)]
        }.sorted { $0.0 < $1.0 }
        var result: [StickyTextRun] = []
        var bold = 0
        var italic = 0
        var index = 0
        while index < boundaries.count {
            let location = boundaries[index].0
            while index < boundaries.count, boundaries[index].0 == location {
                bold += boundaries[index].1
                italic += boundaries[index].2
                index += 1
            }
            guard index < boundaries.count, bold > 0 || italic > 0 else { continue }
            let length = boundaries[index].0 - location
            if let previous = result.last, previous.location + previous.length == location,
               previous.bold == (bold > 0), previous.italic == (italic > 0) {
                result[result.count - 1].length += length
            } else {
                result.append(StickyTextRun(location: location, length: length, bold: bold > 0, italic: italic > 0))
            }
        }
        return StickyRichText(runs: result)
    }
}

public struct StickyTextRun: Codable, Equatable, Sendable {
    public var location: Int
    public var length: Int
    public var bold: Bool
    public var italic: Bool

    public init(location: Int, length: Int, bold: Bool = false, italic: Bool = false) {
        self.location = location
        self.length = length
        self.bold = bold
        self.italic = italic
    }

    private enum CodingKeys: String, CodingKey {
        case location, length, bold, italic
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        location = try values.decode(Int.self, forKey: .location)
        length = try values.decode(Int.self, forKey: .length)
        bold = try values.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try values.decodeIfPresent(Bool.self, forKey: .italic) ?? false
    }
}
