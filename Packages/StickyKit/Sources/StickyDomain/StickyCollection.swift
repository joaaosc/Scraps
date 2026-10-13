import Foundation

public enum StickyCollection: String, CaseIterable, Sendable, Identifiable {
    case notes, favorites, archived
    public var id: Self { self }
    public var localizedName: String {
        let key: String
        switch self {
        case .notes: key = "All Stickies"
        case .favorites: key = "Favorites"
        case .archived: key = "Archive"
        }
        return NSLocalizedString(key, bundle: .module, comment: "Note collection")
    }
    public var systemImage: String {
        switch self {
        case .notes: "note.text"
        case .favorites: "star"
        case .archived: "archivebox"
        }
    }
    public func notes(in notes: [Sticky], search: String = "", tag: String? = nil) -> [Sticky] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.filter { note in
            guard note.deletedAt == nil, note.isArchived == (self == .archived) else { return false }
            if self == .favorites, !note.isPinned { return false }
            if let tag, !note.tags.contains(tag) { return false }
            return query.isEmpty || note.text.localizedStandardContains(query) || note.tags.contains { $0.localizedStandardContains(query) }
        }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
