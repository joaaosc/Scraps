import Foundation

/// Line-based list editing. The markers remain ordinary editable text, making
/// a checklist useful in Scraps, copied text and any sharing destination.
public enum StickyListEditing {
    public enum Style: Equatable, Sendable {
        case bullet, numbered, checklist
    }

    public struct Result: Equatable, Sendable {
        public var text: String
        public var richText: StickyRichText?
        public var selection: NSRange
    }

    private struct Line {
        var prefix: NSRange
        var style: Style?
        var checked: Bool
    }

    public static func toggle(
        _ style: Style,
        text: String,
        richText: StickyRichText?,
        selection: NSRange
    ) -> Result {
        let lines = selectedLines(in: text, selection: selection)
        let remove = lines.allSatisfy { $0.style == style }
        let edits = lines.enumerated().map { index, line in
            let prefix: String
            if remove {
                prefix = ""
            } else {
                switch style {
                case .bullet: prefix = "• "
                case .numbered: prefix = "\(index + 1). "
                case .checklist: prefix = line.style == .checklist && line.checked ? "☑ " : "☐ "
                }
            }
            return (line.prefix, prefix)
        }
        return applying(edits, to: text, richText: richText, selection: selection)
    }

    public static func toggleCompletion(
        text: String,
        richText: StickyRichText?,
        selection: NSRange
    ) -> Result {
        let lines = selectedLines(in: text, selection: selection)
        let checked = !lines.allSatisfy { $0.style == .checklist && $0.checked }
        let edits = lines.map { ($0.prefix, checked ? "☑ " : "☐ ") }
        return applying(edits, to: text, richText: richText, selection: selection)
    }

    public static func containsChecklist(text: String, selection: NSRange) -> Bool {
        selectedLines(in: text, selection: selection).contains { $0.style == .checklist }
    }

    private static func selectedLines(in text: String, selection: NSRange) -> [Line] {
        let string = text as NSString
        let start = min(max(selection.location, 0), string.length)
        let length = min(max(selection.length, 0), string.length - start)
        // A selection ending at the next line's start belongs to the preceding
        // lines, so a list command never changes an unselected paragraph.
        let expanded = string.lineRange(for: NSRange(location: start, length: max(0, length - 1)))
        var lines: [Line] = []
        var location = expanded.location
        repeat {
            let range = string.lineRange(for: NSRange(location: location, length: 0))
            let line = string.substring(with: range)
            let indentation = line.prefix { $0 == " " || $0 == "\t" }
            let content = String(line.dropFirst(indentation.count))
            var prefix = ""
            var style: Style?
            var checked = false
            if content.hasPrefix("☐ ") || content.hasPrefix("☑ ") {
                prefix = String(content.prefix(2))
                style = .checklist
                checked = content.hasPrefix("☑ ")
            } else if content.hasPrefix("• ") || content.hasPrefix("- ") || content.hasPrefix("* ") {
                prefix = String(content.prefix(2))
                style = .bullet
            } else if let range = content.range(of: "^[0-9]+[.)] ", options: .regularExpression) {
                prefix = String(content[range])
                style = .numbered
            }
            lines.append(Line(
                prefix: NSRange(location: location + indentation.utf16.count, length: prefix.utf16.count),
                style: style, checked: checked
            ))
            let next = NSMaxRange(range)
            guard next > location else { break }
            location = next
        } while location < NSMaxRange(expanded)
        return lines
    }

    private static func applying(
        _ edits: [(NSRange, String)],
        to text: String,
        richText: StickyRichText?,
        selection: NSRange
    ) -> Result {
        var text = text
        var runs = richText?.normalized(for: text).runs ?? []
        var lower = min(max(selection.location, 0), text.utf16.count)
        var upper = lower + min(max(selection.length, 0), text.utf16.count - lower)
        for (range, replacement) in edits.reversed() {
            let end = NSMaxRange(range)
            let inserted = replacement.utf16.count
            let delta = inserted - range.length
            func adjusted(_ offset: Int) -> Int {
                if offset < range.location { return offset }
                if offset <= end { return range.location + inserted }
                return offset + delta
            }
            lower = adjusted(lower)
            upper = adjusted(upper)
            var adjustedRuns: [StickyTextRun] = []
            for run in runs {
                let runEnd = run.location + run.length
                let beforeEnd = min(runEnd, range.location)
                if beforeEnd > run.location {
                    adjustedRuns.append(StickyTextRun(
                        location: run.location, length: beforeEnd - run.location,
                        bold: run.bold, italic: run.italic
                    ))
                }
                let afterStart = max(run.location, end)
                if runEnd > afterStart {
                    adjustedRuns.append(StickyTextRun(
                        location: afterStart + delta, length: runEnd - afterStart,
                        bold: run.bold, italic: run.italic
                    ))
                }
            }
            runs = adjustedRuns
            text = (text as NSString).replacingCharacters(in: range, with: replacement)
        }
        let formatting = StickyRichText(runs: runs).normalized(for: text)
        return Result(
            text: text,
            richText: formatting.runs.isEmpty ? nil : formatting,
            selection: NSRange(location: lower, length: max(0, upper - lower))
        )
    }
}
