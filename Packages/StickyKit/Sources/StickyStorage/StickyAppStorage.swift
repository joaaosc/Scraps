import Foundation

/// The app and its widgets share one local store. Existing documents are copied
/// once without deleting or overwriting the original container's contents.
public enum StickyAppStorage {
    public static func sharedDirectoryURL() throws -> URL {
        #if canImport(Darwin)
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: StickyKitIdentity.appGroupIdentifier
        ) else { throw CocoaError(.fileReadNoPermission) }
        let directory = group.appending(path: "Library/Application Support")
            .appending(path: StickyKitIdentity.bundleIdentifier).appending(path: "Stickies")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
        #else
        return try FileStickyStore.defaultDirectoryURL()
        #endif
    }

    public static func makeStore() throws -> FileStickyStore {
        let oldDirectory = try FileStickyStore.defaultDirectoryURL()
        let directory: URL
        do { directory = try sharedDirectoryURL() }
        catch {
            // Development signing may not yet provision the App Group. Local
            // notes remain usable; widgets require the configured group.
            return try FileStickyStore(directoryURL: oldDirectory)
        }
        try migrateLegacy(from: oldDirectory, to: directory)
        return try FileStickyStore(directoryURL: directory)
    }

    static func migrateLegacy(from source: URL, to destination: URL) throws {
        guard source.standardizedFileURL != destination.standardizedFileURL else { return }
        let marker = destination.appending(path: ".legacy-migration-complete")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: source.path) {
            for file in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            where file.pathExtension == "json" {
                let target = destination.appending(path: file.lastPathComponent)
                guard !FileManager.default.fileExists(atPath: target.path) else { continue }
                try FileManager.default.copyItem(at: file, to: target)
            }
        }
        try Data().write(to: marker, options: .atomic)
    }
}
