import Foundation
import StickyDomain
#if canImport(OSLog)
import OSLog
#endif

public enum FileStickyStoreError: Error, Equatable, LocalizedError, Sendable {
    case limitReached(Int)
    case recentlyDeleted(UUID)
    case newerEditExists(UUID)

    public var errorDescription: String? {
        switch self {
        case let .limitReached(limit):
            String(
                format: NSLocalizedString(
                    "Up to %ld stickies can be kept and all of them are open. Close a sticky to make room.",
                    bundle: .module, comment: "Active sticky limit"
                ), limit
            )
        case .recentlyDeleted:
            NSLocalizedString(
                "This sticky is in Recently Deleted. Restore it before editing it.",
                bundle: .module, comment: "Late edit of a deleted note"
            )
        case .newerEditExists:
            NSLocalizedString(
                "A newer version of this sticky is already saved. Your edit remains open.",
                bundle: .module, comment: "An older snapshot cannot replace a newer saved note"
            )
        }
    }
}

/// Keeps each sticky in a file of its own.
///
/// One file per sticky rather than a single document: processes sharing the
/// folder never rewrite one another's data, so no write can lose a sticky
/// another process just made.
///
/// A file that cannot be decoded is skipped and logged, never deleted: it may
/// come from a newer version, and removing it would turn a reading problem into
/// lost text. The cap is a hard one. Reaching it fails the creation with a
/// message instead of evicting anything, because a sticky holds text that is
/// not kept anywhere else.
public actor FileStickyStore: RecentlyDeletedStickyStore {
    /// The most stickies that can exist at once.
    public static let maximumCount = 100

    private struct Document: Codable {
        let version: Int
        let sticky: Sticky
    }

    private static let currentVersion = 3
    #if canImport(OSLog)
    private static let logger = Logger(
        subsystem: StickyKitIdentity.bundleIdentifier,
        category: "Stickies"
    )
    #endif

    public nonisolated let directoryURL: URL
    private let limit: Int
    private let announcesChanges: Bool

    /// - Parameters:
    ///   - directoryURL: the folder holding one `<uuid>.json` per sticky.
    ///     Defaults to the one in Application Support.
    ///   - limit: how many stickies may exist; the default is the product's.
    ///   - announcesChanges: whether a write is announced to other processes.
    ///     Tests turn it off so they do not wake a running app's windows; this
    ///     process is always told.
    public init(
        directoryURL: URL? = nil,
        limit: Int = FileStickyStore.maximumCount,
        announcesChanges: Bool = true
    ) throws {
        self.directoryURL = try directoryURL ?? Self.defaultDirectoryURL()
        self.limit = max(1, limit)
        self.announcesChanges = announcesChanges
        try FileManager.default.createDirectory(
            at: self.directoryURL,
            withIntermediateDirectories: true
        )
    }

    public func stickies() throws -> [Sticky] {
        try Self.readAll(in: directoryURL)
            .filter { $0.deletedAt == nil }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    /// File names preserve unreadable identifiers; readable tombstones are
    /// excluded so their windows close after a move to Recently Deleted.
    public func existingIdentifiers() async throws -> Set<UUID> {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        return Set(files.compactMap { fileURL in
            guard fileURL.pathExtension == "json",
                  let id = UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent)
            else { return nil }
            // Unknown or temporarily unreadable files still keep their windows.
            if let sticky = try? Self.coordinatedRead(at: fileURL), sticky.deletedAt != nil {
                return nil
            }
            return id
        })
    }

    public func save(_ sticky: Sticky) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let fileURL = Self.fileURL(for: sticky.id, in: directoryURL)

        // The cap applies to creating, never to editing one that exists.
        // Counted over what can be read: an unreadable file is invisible to the
        // person and must not use up room they cannot free. Two processes
        // creating at the same instant could overshoot by one, which is
        // harmless; the next creation is refused.
        let previous: Sticky? = FileManager.default.fileExists(atPath: fileURL.path)
            ? try Self.coordinatedRead(at: fileURL) : nil
        if sticky.deletedAt == nil, previous?.deletedAt != nil {
            throw FileStickyStoreError.recentlyDeleted(sticky.id)
        }
        if sticky.deletedAt == nil, previous == nil {
            let existing = try Self.readAll(in: directoryURL).filter { $0.deletedAt == nil }.count
            guard existing < limit else {
                throw FileStickyStoreError.limitReached(limit)
            }
        }

        try Self.coordinatedWrite(at: fileURL) { coordinatedURL in
            if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                let current = try Self.readDocument(at: coordinatedURL)
                if sticky.deletedAt == nil, current.deletedAt != nil {
                    throw FileStickyStoreError.recentlyDeleted(sticky.id)
                }
                if current.updatedAt > sticky.updatedAt {
                    throw FileStickyStoreError.newerEditExists(sticky.id)
                }
            }
            try Self.encode(sticky).write(to: coordinatedURL, options: .atomic)
        }
        announce()
    }

    public func delete(id: UUID) throws {
        let fileURL = Self.fileURL(for: id, in: directoryURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try Self.coordinatedWrite(at: fileURL, deleting: true) { coordinatedURL in
            // An unsupported document must never be discarded as a side effect
            // of a stale window closing or an expiry pass.
            _ = try Self.readDocument(at: coordinatedURL)
            try FileManager.default.removeItem(at: coordinatedURL)
        }
        announce()
    }

    public func recentlyDeleted() throws -> [Sticky] {
        try Self.readAll(in: directoryURL)
            .filter { $0.deletedAt != nil }
            .sorted {
                if $0.deletedAt != $1.deletedAt { return $0.deletedAt! > $1.deletedAt! }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    /// Includes recoverable notes for CloudKit. Session notes never enter this store.
    public func synchronizationSnapshot() throws -> [Sticky] {
        try Self.readAll(in: directoryURL)
    }

    /// A remote merge is committed only if the locally read version is still
    /// current. It can restore a tombstone, which ordinary autosaves cannot do.
    public func applySynchronized(_ sticky: Sticky, replacing expected: Sticky?) throws {
        let file = Self.fileURL(for: sticky.id, in: directoryURL)
        try Self.coordinatedWrite(at: file) { target in
            let current = FileManager.default.fileExists(atPath: target.path) ? try Self.readDocument(at: target) : nil
            guard current == expected else { throw FileStickyStoreError.newerEditExists(sticky.id) }
            try Self.encode(sticky).write(to: target, options: .atomic)
        }
        announce()
    }

    public func deleteSynchronized(id: UUID, replacing expected: Sticky) throws {
        let file = Self.fileURL(for: id, in: directoryURL)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try Self.coordinatedWrite(at: file, deleting: true) { target in
            guard try Self.readDocument(at: target) == expected else { throw FileStickyStoreError.newerEditExists(id) }
            try FileManager.default.removeItem(at: target)
        }
        announce()
    }

    /// A tombstone lives in the same atomic document as its contents. There is
    /// no remove-then-write interval in which a failure could lose the note.
    public func moveToTrash(_ sticky: Sticky, at date: Date) throws {
        let fileURL = Self.fileURL(for: sticky.id, in: directoryURL)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var changed = false
        try Self.coordinatedWrite(at: fileURL) { coordinatedURL in
            var trashed = sticky
            if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                let current = try Self.readDocument(at: coordinatedURL)
                guard current.deletedAt == nil else { return }
                if current.updatedAt > sticky.updatedAt { trashed = current }
            }
            trashed.deletedAt = date
            try Self.encode(trashed).write(to: coordinatedURL, options: .atomic)
            changed = true
        }
        if changed { announce() }
    }

    @discardableResult
    public func restore(id: UUID) throws -> Sticky? {
        let fileURL = Self.fileURL(for: id, in: directoryURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        var sticky = try Self.coordinatedRead(at: fileURL)
        guard sticky.deletedAt != nil else { return sticky }
        let activeCount = try Self.readAll(in: directoryURL).filter { $0.deletedAt == nil }.count
        guard activeCount < limit else { throw FileStickyStoreError.limitReached(limit) }
        try Self.coordinatedWrite(at: fileURL) { coordinatedURL in
            // Preserve a concurrent edit or restoration, rather than writing
            // the snapshot read before coordination began.
            sticky = try Self.readDocument(at: coordinatedURL)
            sticky.deletedAt = nil
            try Self.encode(sticky).write(to: coordinatedURL, options: .atomic)
        }
        announce()
        return sticky
    }

    public func purgeExpired(now: Date) throws {
        for sticky in try recentlyDeleted() {
            guard let deletedAt = sticky.deletedAt,
                  now.timeIntervalSince(deletedAt) >= Self.trashRetentionInterval else { continue }
            let fileURL = Self.fileURL(for: sticky.id, in: directoryURL)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            var removed = false
            try Self.coordinatedWrite(at: fileURL, deleting: true) { coordinatedURL in
                let current = try Self.readDocument(at: coordinatedURL)
                guard let currentDeletion = current.deletedAt,
                      now.timeIntervalSince(currentDeletion) >= Self.trashRetentionInterval
                else { return }
                try FileManager.default.removeItem(at: coordinatedURL)
                removed = true
            }
            if removed { announce() }
        }
    }

    /// Inside the sandbox, Application Support is the app's own container, so
    /// no entitlement beyond the sandbox itself is needed to keep stickies.
    public static func defaultDirectoryURL(
        applicationSupportResolver: () throws -> URL = {
            try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
    ) throws -> URL {
        try applicationSupportResolver()
            .appending(path: StickyKitIdentity.bundleIdentifier)
            .appending(path: "Stickies")
    }

    static func fileURL(for id: UUID, in directoryURL: URL) -> URL {
        directoryURL.appending(path: "\(id.uuidString).json")
    }

    /// Signals this process directly, always, and the others through Darwin.
    private func announce() {
        StickyChanges.notifyInProcess()
        guard announcesChanges else { return }
        StickyChanges.notifyOtherProcesses()
    }

    private static func readAll(in directoryURL: URL) throws -> [Sticky] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { fileURL in
                do {
                    return try coordinatedRead(at: fileURL)
                } catch {
                    #if canImport(OSLog)
                    logger.error(
                        "Skipped an unreadable sticky file \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                    #endif
                    return nil
                }
            }
    }

    private static func coordinatedRead(at fileURL: URL) throws -> Sticky {
        #if canImport(Darwin)
        var coordinationError: NSError?
        var operationResult: Result<Sticky, Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: fileURL,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            operationResult = Result {
                try readDocument(at: coordinatedURL)
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let operationResult else {
            throw CocoaError(.fileReadUnknown)
        }
        return try operationResult.get()
        #else
        return try readDocument(at: fileURL)
        #endif
    }

    private static func coordinatedWrite(
        at fileURL: URL,
        deleting: Bool = false,
        _ body: (URL) throws -> Void
    ) throws {
        #if canImport(Darwin)
        var coordinationError: NSError?
        var operationResult: Result<Void, Error>?
        NSFileCoordinator().coordinate(
            writingItemAt: fileURL,
            options: deleting ? [.forDeleting] : [],
            error: &coordinationError
        ) { coordinatedURL in
            operationResult = Result { try body(coordinatedURL) }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let operationResult else {
            throw CocoaError(.fileWriteUnknown)
        }
        try operationResult.get()
        #else
        try body(fileURL)
        #endif
    }

    private static func encode(_ sticky: Sticky) throws -> Data {
        let encoder = JSONEncoder()
        // Date's Codable representation uses seconds since 2001. Retaining
        // its native reference epoch avoids rounding during epoch conversion.
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Document(version: currentVersion, sticky: sticky))
    }

    private static func readDocument(at fileURL: URL) throws -> Sticky {
        let sticky = try decode(Data(contentsOf: fileURL))
        guard UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent) == sticky.id else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [], debugDescription: "Sticky identifier does not match its document name"
            ))
        }
        return sticky
    }

    private static func decode(_ data: Data) throws -> Sticky {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            if let seconds = try? value.decode(Double.self), seconds.isFinite {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            let iso8601 = try value.decode(String.self)
            if let date = try? Date(iso8601, strategy: .iso8601), date.timeIntervalSince1970.isFinite {
                return date
            }
            if let date = try? Date(iso8601, strategy: .iso8601.time(includingFractionalSeconds: true)), date.timeIntervalSince1970.isFinite {
                return date
            }
            throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid sticky date")
        }
        let document = try decoder.decode(Document.self, from: data)
        guard (1...currentVersion).contains(document.version) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Unsupported sticky version \(document.version)")
            )
        }
        return document.sticky
    }
}
