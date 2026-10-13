import Foundation

public enum StickyChecklist {
    public struct Item: Identifiable, Sendable {
        public let location: Int
        public let line: String
        public let text: String
        public let completed: Bool
        public var id: Int { location }
    }
    public static func items(in text: String) -> [Item] {
        var offset = 0
        return text.components(separatedBy: "\n").compactMap { line in
            defer { offset += line.utf16.count + 1 }
            let content = line.trimmingCharacters(in: .whitespaces)
            guard let marker = ["☑ ", "☐ ", "- [ ] ", "- [x] ", "- [X] ", "[ ] ", "[x] ", "[X] "].first(where: { content.hasPrefix($0) }) else { return nil }
            let completed = marker == "☑ " || marker.lowercased().contains("[x]")
            let markerCount = marker.count
            return Item(location: offset, line: line, text: String(content.dropFirst(markerCount)), completed: completed)
        }
    }
}
