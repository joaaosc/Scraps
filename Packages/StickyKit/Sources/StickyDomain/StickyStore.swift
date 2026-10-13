import Foundation

/// Keeps stickies across launches.
///
/// More than one process may share a store, so an implementation must
/// tolerate a sticky being created by one while another reads.
public protocol StickyStore: Sendable {
    /// Every sticky that can be read, oldest first. One that cannot be read is
    /// left out, never removed.
    func stickies() async throws -> [Sticky]
    /// The identifiers of every sticky that exists, whether or not it can be
    /// read. A window must close only when its sticky is really gone, not when
    /// its file is momentarily unreadable.
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
