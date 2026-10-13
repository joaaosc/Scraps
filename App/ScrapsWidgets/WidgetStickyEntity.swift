import AppIntents
import Foundation
import StickyDomain
import StickyStorage

struct WidgetStickyEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sticky")
    static let defaultQuery = WidgetStickyQuery()
    let id: UUID
    let title: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(title)") }
}

struct WidgetStickyQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WidgetStickyEntity] {
        try await notes().filter { identifiers.contains($0.id) }.map { .init(id: $0.id, title: $0.title) }
    }
    func suggestedEntities() async throws -> [WidgetStickyEntity] {
        try await notes().map { .init(id: $0.id, title: $0.title) }
    }
    private func notes() async throws -> [Sticky] {
        let store = try FileStickyStore(directoryURL: StickyAppStorage.sharedDirectoryURL())
        return try await store.stickies().filter { !$0.isArchived }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }
}
