import Foundation
import StickyDomain

public enum SessionStickyStoreError: Error, Equatable, LocalizedError, Sendable {
    case identifierAlreadyExists(UUID)
    case recentlyDeletedUnavailable

    public var errorDescription: String? {
        switch self {
        case .identifierAlreadyExists:
            NSLocalizedString(
                "A sticky with this identifier already exists.",
                bundle: .module, comment: "Duplicate session identifier"
            )
        case .recentlyDeletedUnavailable:
            NSLocalizedString(
                "This store does not support Recently Deleted.",
                bundle: .module, comment: "Recovery unavailable"
            )
        }
    }
}

/// Routes session notes to RAM and ordinary notes to the durable store. Session
/// identity belongs to this router, never to a field serialized with a note.
public actor SessionStickyStore: RecentlyDeletedStickyStore {
    private let durable: any StickyStore
    private let session: MemoryStickyStore
    /// Retain routing even after permanent deletion, so a delayed session
    /// autosave can never escape to disk.
    private var sessionIdentifiers: Set<UUID> = []
    private var mutations: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]

    public init(durable: any StickyStore, session: MemoryStickyStore = MemoryStickyStore()) {
        self.durable = durable
        self.session = session
    }

    public func createSession(_ sticky: Sticky) async throws {
        try await serialize(id: sticky.id) { try await self.createSessionNow(sticky) }
    }

    private func createSessionNow(_ sticky: Sticky) async throws {
        guard !(try await durable.existingIdentifiers()).contains(sticky.id) else {
            throw SessionStickyStoreError.identifierAlreadyExists(sticky.id)
        }
        if let trash = durable as? any RecentlyDeletedStickyStore,
           try await trash.recentlyDeleted().contains(where: { $0.id == sticky.id }) {
            throw SessionStickyStoreError.identifierAlreadyExists(sticky.id)
        }
        try await session.save(sticky)
        sessionIdentifiers.insert(sticky.id)
    }

    public func isSessionOnly(id: UUID) async -> Bool {
        await belongsToSession(id: id)
    }

    public func stickies() async throws -> [Sticky] {
        let persisted = try await durable.stickies()
        let temporary = await session.stickies()
        return (persisted + temporary).sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public func existingIdentifiers() async throws -> Set<UUID> {
        let persisted = try await durable.existingIdentifiers()
        return persisted.union(await session.existingIdentifiers())
    }

    public func save(_ sticky: Sticky) async throws {
        try await serialize(id: sticky.id) { try await self.saveNow(sticky) }
    }

    public func save(_ sticky: Sticky, replacing expected: Sticky?) async throws {
        try await serialize(id: sticky.id) {
            if await self.belongsToSession(id: sticky.id) {
                try await self.session.save(sticky)
            } else if let files = self.durable as? FileStickyStore, let expected {
                try await files.applySynchronized(sticky, replacing: expected)
            } else { try await self.durable.save(sticky) }
        }
    }

    private func saveNow(_ sticky: Sticky) async throws {
        if await belongsToSession(id: sticky.id) {
            try await session.save(sticky)
        } else {
            try await durable.save(sticky)
        }
    }

    public func delete(id: UUID) async throws {
        try await serialize(id: id) { try await self.deleteNow(id: id) }
    }

    private func deleteNow(id: UUID) async throws {
        if await belongsToSession(id: id) {
            await session.delete(id: id)
        } else {
            try await durable.delete(id: id)
        }
    }

    public func recentlyDeleted() async throws -> [Sticky] {
        let persisted = try await (durable as? any RecentlyDeletedStickyStore)?.recentlyDeleted() ?? []
        return (persisted + (await session.recentlyDeleted())).sorted {
            if $0.deletedAt != $1.deletedAt { return $0.deletedAt! > $1.deletedAt! }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public func moveToTrash(_ sticky: Sticky, at date: Date) async throws {
        try await serialize(id: sticky.id) { try await self.moveToTrashNow(sticky, at: date) }
    }

    private func moveToTrashNow(_ sticky: Sticky, at date: Date) async throws {
        if await belongsToSession(id: sticky.id) {
            await session.moveToTrash(sticky, at: date)
        } else {
            guard let trash = durable as? any RecentlyDeletedStickyStore else {
                throw SessionStickyStoreError.recentlyDeletedUnavailable
            }
            try await trash.moveToTrash(sticky, at: date)
        }
    }

    @discardableResult
    public func restore(id: UUID) async throws -> Sticky? {
        try await serialize(id: id) { try await self.restoreNow(id: id) }
    }

    private func restoreNow(id: UUID) async throws -> Sticky? {
        if await belongsToSession(id: id) {
            return try await session.restore(id: id)
        }
        guard let trash = durable as? any RecentlyDeletedStickyStore else {
            throw SessionStickyStoreError.recentlyDeletedUnavailable
        }
        return try await trash.restore(id: id)
    }

    public func purgeExpired(now: Date) async throws {
        await session.purgeExpired(now: now)
        try await (durable as? any RecentlyDeletedStickyStore)?.purgeExpired(now: now)
    }

    /// The durable save must succeed before the RAM copy is released.
    public func makeDurable(id: UUID) async throws {
        try await serialize(id: id) { try await self.makeDurableNow(id: id) }
    }

    private func makeDurableNow(id: UUID) async throws {
        guard let sticky = await session.stickyIncludingDeleted(id: id) else { return }
        guard sticky.deletedAt == nil else { throw FileStickyStoreError.recentlyDeleted(id) }
        try await durable.save(sticky)
        await session.delete(id: id)
        sessionIdentifiers.remove(id)
    }

    /// Keep the original file when conversion fails. Session creation never
    /// calls this method implicitly, so ordinary session notes touch no disk.
    public func makeSessionOnly(id: UUID) async throws {
        try await serialize(id: id) { try await self.makeSessionOnlyNow(id: id) }
    }

    private func makeSessionOnlyNow(id: UUID) async throws {
        guard !(await belongsToSession(id: id)),
              let sticky = try await durable.stickies().first(where: { $0.id == id }) else { return }
        try await session.save(sticky)
        sessionIdentifiers.insert(id)
        do {
            try await durable.delete(id: id)
        } catch {
            await session.delete(id: id)
            sessionIdentifiers.remove(id)
            throw error
        }
    }

    private func belongsToSession(id: UUID) async -> Bool {
        if sessionIdentifiers.contains(id) { return true }
        guard await session.contains(id: id) else { return false }
        sessionIdentifiers.insert(id)
        return true
    }

    /// Actor methods can interleave while another store is writing. Serialize
    /// mutations of one note so a conversion cannot discard a concurrent edit.
    private func serialize<Value: Sendable>(
        id: UUID, _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let previous = mutations[id]?.task
        let write = Task {
            await previous?.value
            return try await operation()
        }
        let token = UUID()
        let barrier = Task { _ = try? await write.value }
        mutations[id] = (token, barrier)
        defer {
            if mutations[id]?.token == token { mutations[id] = nil }
        }
        return try await write.value
    }
}
