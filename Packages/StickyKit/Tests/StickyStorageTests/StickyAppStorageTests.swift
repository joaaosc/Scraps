import Foundation
import StickyDomain
import Testing
@testable import StickyStorage

@Suite("Shared notes and navigation")
struct StickyAppStorageTests {
    @Test("Migration preserves originals, unreadable data and existing shared files")
    func migration() throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "Original")
        let target = root.appending(path: "Group")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let first = "\(UUID().uuidString).json"
        let broken = "\(UUID().uuidString).json"
        try Data("Original".utf8).write(to: source.appending(path: first))
        try Data("Newer shared".utf8).write(to: target.appending(path: first))
        try Data("Unreadable bytes".utf8).write(to: source.appending(path: broken))
        try StickyAppStorage.migrateLegacy(from: source, to: target)
        #expect(try Data(contentsOf: target.appending(path: first)) == Data("Newer shared".utf8))
        #expect(try Data(contentsOf: target.appending(path: broken)) == Data("Unreadable bytes".utf8))
        #expect(try Data(contentsOf: source.appending(path: broken)) == Data("Unreadable bytes".utf8))
        try FileManager.default.removeItem(at: target.appending(path: broken))
        try StickyAppStorage.migrateLegacy(from: source, to: target)
        #expect(!FileManager.default.fileExists(atPath: target.appending(path: broken).path))
    }

    @Test("A cloud merge or deletion cannot discard a newer local snapshot")
    func synchronizedWrites() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try FileStickyStore(directoryURL: folder, announcesChanges: false)
        let original = Sticky(text: "Original")
        try await store.save(original)
        var edited = original
        edited.edit(text: "Newer local", at: original.createdAt.addingTimeInterval(2))
        try await store.save(edited)
        await #expect(throws: FileStickyStoreError.newerEditExists(original.id)) {
            try await store.applySynchronized(original, replacing: original)
        }
        await #expect(throws: FileStickyStoreError.newerEditExists(original.id)) {
            try await store.deleteSynchronized(id: original.id, replacing: original)
        }
        #expect(try await store.stickies() == [edited])
    }

    @Test("Widget URLs accept only known actions and valid note identifiers")
    func links() {
        let id = UUID()
        for action in [StickyNavigation.note(id), .new, .library] {
            #expect(StickyNavigation(url: action.url) == action)
        }
        for value in ["https://note/\(id)", "scraps://note/not-an-id", "scraps://delete/\(id)", "scraps://new?text=unexpected"] {
            #expect(StickyNavigation(url: URL(string: value)!) == nil)
        }
    }
}
