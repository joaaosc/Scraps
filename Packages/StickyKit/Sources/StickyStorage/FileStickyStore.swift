import Foundation
import StickyDomain
import OSLog

public enum FileStickyStoreError: Error, Equatable, LocalizedError, Sendable {
    case limitReached(Int)

    public var errorDescription: String? {
        switch self {
        case let .limitReached(limit):
            "Up to \(limit) stickies can be kept and all of them are open. Close a sticky to make room."
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
public actor FileStickyStore: StickyStore {
    /// The most stickies that can exist at once.
    public static let maximumCount = 100

    private struct Document: Codable {
        let version: Int
        let sticky: Sticky
    }

    private static let currentVersion = 1
    private static let logger = Logger(
        subsystem: StickyKitIdentity.bundleIdentifier,
        category: "Stickies"
    )

    public let directoryURL: URL
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
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    /// Read from the file names alone, so a file that cannot be decoded still
    /// counts as existing.
    public func existingIdentifiers() async throws -> Set<UUID> {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        return Set(
            files
                .filter { $0.pathExtension == "json" }
                .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
        )
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
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let existing = try Self.readAll(in: directoryURL).count
            guard existing < limit else {
                throw FileStickyStoreError.limitReached(limit)
            }
        }

        try Self.coordinatedWrite(at: fileURL) { coordinatedURL in
            try Self.encode(sticky).write(to: coordinatedURL, options: .atomic)
        }
        announce()
    }

    public func delete(id: UUID) throws {
        let fileURL = Self.fileURL(for: id, in: directoryURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try Self.coordinatedWrite(at: fileURL) { coordinatedURL in
            try FileManager.default.removeItem(at: coordinatedURL)
        }
        announce()
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
                    logger.error(
                        "Skipped an unreadable sticky file \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                    return nil
                }
            }
    }

    private static func coordinatedRead(at fileURL: URL) throws -> Sticky {
        var coordinationError: NSError?
        var operationResult: Result<Sticky, Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: fileURL,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            operationResult = Result {
                let data = try Data(contentsOf: coordinatedURL)
                return try decode(data)
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let operationResult else {
            throw CocoaError(.fileReadUnknown)
        }
        return try operationResult.get()
    }

    private static func coordinatedWrite(
        at fileURL: URL,
        _ body: (URL) throws -> Void
    ) throws {
        var coordinationError: NSError?
        var operationResult: Result<Void, Error>?
        NSFileCoordinator().coordinate(
            writingItemAt: fileURL,
            options: [],
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
    }

    private static func encode(_ sticky: Sticky) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Document(version: currentVersion, sticky: sticky))
    }

    private static func decode(_ data: Data) throws -> Sticky {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(Document.self, from: data)
        guard document.version == currentVersion else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Unsupported sticky version \(document.version)")
            )
        }
        return document.sticky
    }
}
