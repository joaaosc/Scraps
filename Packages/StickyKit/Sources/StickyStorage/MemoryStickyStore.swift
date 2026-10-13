import Foundation
import StickyDomain

/// Session notes never reach a file, including their Recently Deleted history.
/// Keeping this store alive keeps the session alive; a new instance is empty.
public actor MemoryStickyStore: RecentlyDeletedStickyStore {
    private var notes: [UUID: Sticky]
    private let limit: Int

    public init(stickies: [Sticky] = [], limit: Int = FileStickyStore.maximumCount) {
        notes = stickies.reduce(into: [:]) { $0[$1.id] = $1 }
        self.limit = max(1, limit)
    }

    public func stickies() -> [Sticky] {
        notes.values.filter { $0.deletedAt == nil }.sorted(by: Self.oldestFirst)
    }

    public func existingIdentifiers() async -> Set<UUID> {
        Set(notes.values.filter { $0.deletedAt == nil }.map(\.id))
    }

    public func save(_ sticky: Sticky) throws {
        if sticky.deletedAt == nil, notes[sticky.id]?.deletedAt != nil {
            throw FileStickyStoreError.recentlyDeleted(sticky.id)
        }
        if let current = notes[sticky.id], current.updatedAt > sticky.updatedAt {
            throw FileStickyStoreError.newerEditExists(sticky.id)
        }
        if sticky.deletedAt == nil, notes[sticky.id] == nil, stickies().count >= limit {
            throw FileStickyStoreError.limitReached(limit)
        }
        notes[sticky.id] = sticky
        StickyChanges.notifyInProcess()
    }

    public func delete(id: UUID) {
        guard notes.removeValue(forKey: id) != nil else { return }
        StickyChanges.notifyInProcess()
    }

    public func recentlyDeleted() -> [Sticky] {
        notes.values.filter { $0.deletedAt != nil }.sorted {
            if $0.deletedAt != $1.deletedAt { return $0.deletedAt! > $1.deletedAt! }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public func moveToTrash(_ sticky: Sticky, at date: Date) {
        guard notes[sticky.id]?.deletedAt == nil else { return }
        var trashed = sticky
        if let current = notes[sticky.id], current.updatedAt > sticky.updatedAt { trashed = current }
        trashed.deletedAt = date
        notes[sticky.id] = trashed
        StickyChanges.notifyInProcess()
    }

    @discardableResult
    public func restore(id: UUID) throws -> Sticky? {
        guard var sticky = notes[id] else { return nil }
        guard sticky.deletedAt != nil else { return sticky }
        guard stickies().count < limit else { throw FileStickyStoreError.limitReached(limit) }
        sticky.deletedAt = nil
        notes[id] = sticky
        StickyChanges.notifyInProcess()
        return sticky
    }

    public func purgeExpired(now: Date) {
        let expired = notes.values.filter {
            guard let deletedAt = $0.deletedAt else { return false }
            return now.timeIntervalSince(deletedAt) >= Self.trashRetentionInterval
        }.map(\.id)
        for id in expired { notes.removeValue(forKey: id) }
        if !expired.isEmpty { StickyChanges.notifyInProcess() }
    }

    /// Includes tombstones so the session router never writes their contents
    /// to its durable store during a late autosave or a restoration.
    func contains(id: UUID) -> Bool { notes[id] != nil }

    func stickyIncludingDeleted(id: UUID) -> Sticky? { notes[id] }

    private static func oldestFirst(_ lhs: Sticky, _ rhs: Sticky) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
