import Foundation

/// Keeps stickies across launches.
///
/// More than one process may share a store, so an implementation must
/// tolerate a sticky being created by one while another reads.
public protocol StickyStore: Sendable {
    /// Every active sticky that can be read, oldest first. One that cannot be
    /// read is left out, never removed.
    func stickies() async throws -> [Sticky]
    /// The identifiers of active stickies, including unreadable documents.
    /// Recently deleted notes are excluded. A window must close only when its
    /// sticky is gone or trashed, not when its file is momentarily unreadable.
    func existingIdentifiers() async throws -> Set<UUID>
    /// Creates the sticky, or replaces the stored one with the same identifier.
    func save(_ sticky: Sticky) async throws
    /// Removes the sticky. Removing one that is already gone is not an error.
    func delete(id: UUID) async throws
}

extension StickyStore {
    /// For stores that cannot hold anything unreadable.
    public func existingIdentifiers() async throws -> Set<UUID> {
        Set(try await stickies().map(\.id))
    }
}

/// Keeps deleted notes recoverable for thirty days. Ordinary reads and
/// identifier reconciliation expose only active notes.
public protocol RecentlyDeletedStickyStore: StickyStore {
    func recentlyDeleted() async throws -> [Sticky]
    func moveToTrash(_ sticky: Sticky, at date: Date) async throws
    @discardableResult
    func restore(id: UUID) async throws -> Sticky?
    func purgeExpired(now: Date) async throws
}

extension RecentlyDeletedStickyStore {
    public static var trashRetentionInterval: TimeInterval { 30 * 24 * 60 * 60 }

    public func moveToTrash(_ sticky: Sticky) async throws {
        try await moveToTrash(sticky, at: Date())
    }

    public func purgeExpired() async throws {
        try await purgeExpired(now: Date())
    }
}
